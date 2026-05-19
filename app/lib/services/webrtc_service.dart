import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../utils/logger.dart';

typedef StreamStateCallback = void Function(MediaStream stream);
typedef CallStateCallback = void Function(RTCPeerConnectionState state);

class WebRTCService {
  RTCPeerConnection? peerConnection;
  MediaStream? localStream;
  MediaStream? remoteStream;
  String? roomId;

  StreamStateCallback? onAddRemoteStream;
  CallStateCallback? onCallStateChange;
  VoidCallback? onConnectionConnected;

  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _roomSubscription;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _callerCandidatesSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _calleeCandidatesSub;

  // ICE candidate buffer — collect candidates before remote desc is set
  final List<RTCIceCandidate> _pendingCandidates = [];
  bool _remoteDescriptionSet = false;

  final FirebaseFirestore db = FirebaseFirestore.instance;

  /// ICE servers: multiple STUN + free TURN servers for NAT traversal
  final Map<String, dynamic> configuration = {
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'},
      {'urls': 'stun:stun1.l.google.com:19302'},
      {'urls': 'stun:stun2.l.google.com:19302'},
      {'urls': 'stun:stun3.l.google.com:19302'},
      {'urls': 'stun:stun4.l.google.com:19302'},
      {
        'urls': [
          'turn:openrelay.metered.ca:80',
          'turn:openrelay.metered.ca:443',
          'turn:openrelay.metered.ca:443?transport=tcp',
        ],
        'username': 'openrelayproject',
        'credential': 'openrelayproject',
      },
    ],
    'sdpSemantics': 'unified-plan',
    'iceTransportPolicy': 'all',
  };

  /// Initialize local media stream
  Future<void> initLocalStream(RTCVideoRenderer localVideo,
      {bool isVideo = true}) async {
    final Map<String, dynamic> mediaConstraints = {
      'audio': {
        'echoCancellation': true,
        'noiseSuppression': true,
        'autoGainControl': true,
      },
      'video': isVideo
          ? {
              'facingMode': 'user',
              'width': {'ideal': 640},
              'height': {'ideal': 480},
              'frameRate': {'ideal': 30},
            }
          : false,
    };

    try {
      if (localStream != null) {
        for (final track in localStream!.getTracks()) {
          track.stop();
        }
        await localStream!.dispose();
        localStream = null;
      }
      localStream =
          await navigator.mediaDevices.getUserMedia(mediaConstraints);
      localVideo.srcObject = localStream;
      logger.i('Local stream initialized: video=$isVideo');
    } catch (e) {
      logger.e('Error getting user media: $e');
      rethrow;
    }
  }

  /// Create a room (Caller / Initiator)
  Future<String> createRoom(String callerId, String calleeId,
      {bool isVideo = true}) async {
    _pendingCandidates.clear();
    _remoteDescriptionSet = false;

    peerConnection = await createPeerConnection(configuration);
    _registerPeerConnectionListeners();

    // Add local tracks FIRST — this creates SendRecv transceivers properly.
    // Do NOT call _ensureReceivers separately; addTrack already sets SendRecv.
    if (localStream != null) {
      for (final track in localStream!.getTracks()) {
        await peerConnection!.addTrack(track, localStream!);
      }
    }

    final roomRef = db.collection('calls').doc();
    final callerCandidatesRef = roomRef.collection('callerCandidates');

    peerConnection!.onIceCandidate = (RTCIceCandidate candidate) {
      if (candidate.candidate != null && candidate.candidate!.isNotEmpty) {
        callerCandidatesRef.add(candidate.toMap());
      }
    };

    final offer = await peerConnection!.createOffer({
      'offerToReceiveAudio': true,
      'offerToReceiveVideo': isVideo ? true : false,
    });
    await peerConnection!.setLocalDescription(offer);

    await roomRef.set({
      'callerId': callerId,
      'calleeId': calleeId,
      'type': isVideo ? 'video' : 'audio',
      'offer': offer.toMap(),
      'createdAt': FieldValue.serverTimestamp(),
    });

    roomId = roomRef.id;
    logger.i('WebRTC room created: $roomId');

    // Listen for remote answer
    _roomSubscription?.cancel();
    _roomSubscription = roomRef.snapshots().listen((snapshot) async {
      if (!snapshot.exists) return;
      final data = snapshot.data()!;
      if (!_remoteDescriptionSet && data['answer'] != null) {
        final answer = RTCSessionDescription(
          data['answer']['sdp'],
          data['answer']['type'],
        );
        try {
          await peerConnection?.setRemoteDescription(answer);
          _remoteDescriptionSet = true;
          logger.i('Remote description set (answer)');
          await _flushPendingCandidates();
        } catch (e) {
          logger.e('Error setting remote description: $e');
        }
      }
    });

    // Listen for callee ICE candidates
    _calleeCandidatesSub?.cancel();
    _calleeCandidatesSub =
        roomRef.collection('calleeCandidates').snapshots().listen((snapshot) {
      for (final change in snapshot.docChanges) {
        if (change.type == DocumentChangeType.added) {
          final data = change.doc.data()!;
          final candidate = RTCIceCandidate(
            data['candidate'],
            data['sdpMid'],
            data['sdpMLineIndex'],
          );
          if (_remoteDescriptionSet) {
            peerConnection?.addCandidate(candidate);
          } else {
            _pendingCandidates.add(candidate);
          }
        }
      }
    });

    return roomId!;
  }

  /// Join a room (Callee)
  Future<void> joinRoom(String roomId) async {
    this.roomId = roomId;
    _pendingCandidates.clear();
    _remoteDescriptionSet = false;

    final roomRef = db.collection('calls').doc(roomId);
    final roomSnapshot = await roomRef.get();

    if (!roomSnapshot.exists) {
      logger.e('Room $roomId does not exist!');
      return;
    }
    final data = roomSnapshot.data()!;
    final isVideo = data['type'] != 'audio';

    peerConnection = await createPeerConnection(configuration);
    _registerPeerConnectionListeners();

    // Add local tracks FIRST — creates SendRecv transceivers properly
    if (localStream != null) {
      for (final track in localStream!.getTracks()) {
        await peerConnection!.addTrack(track, localStream!);
      }
    }

    final calleeCandidatesRef = roomRef.collection('calleeCandidates');
    peerConnection!.onIceCandidate = (RTCIceCandidate candidate) {
      if (candidate.candidate != null && candidate.candidate!.isNotEmpty) {
        calleeCandidatesRef.add(candidate.toMap());
      }
    };

    // Set remote offer THEN create answer
    final offer = data['offer'];
    await peerConnection!.setRemoteDescription(
      RTCSessionDescription(offer['sdp'], offer['type']),
    );
    _remoteDescriptionSet = true;
    logger.i('Remote description set (offer)');

    final answer = await peerConnection!.createAnswer({
      'offerToReceiveAudio': true,
      'offerToReceiveVideo': isVideo ? true : false,
    });
    await peerConnection!.setLocalDescription(answer);

    await roomRef.update({
      'answer': {'type': answer.type, 'sdp': answer.sdp}
    });

    logger.i('Answer sent, joining room $roomId');

    // Listen for caller ICE candidates (some may have arrived before we joined)
    _callerCandidatesSub?.cancel();
    _callerCandidatesSub =
        roomRef.collection('callerCandidates').snapshots().listen((snapshot) {
      for (final change in snapshot.docChanges) {
        if (change.type == DocumentChangeType.added) {
          final data = change.doc.data()!;
          peerConnection?.addCandidate(RTCIceCandidate(
            data['candidate'],
            data['sdpMid'],
            data['sdpMLineIndex'],
          ));
        }
      }
    });
  }

  Future<void> _flushPendingCandidates() async {
    for (final candidate in _pendingCandidates) {
      try {
        await peerConnection?.addCandidate(candidate);
      } catch (e) {
        logger.w('Failed to add buffered ICE candidate: $e');
      }
    }
    _pendingCandidates.clear();
  }

  /// Hangup / Disconnect
  Future<void> hangUp(RTCVideoRenderer localVideo) async {
    await _roomSubscription?.cancel();
    await _callerCandidatesSub?.cancel();
    await _calleeCandidatesSub?.cancel();
    _roomSubscription = null;
    _callerCandidatesSub = null;
    _calleeCandidatesSub = null;
    _pendingCandidates.clear();
    _remoteDescriptionSet = false;

    localStream?.getTracks().forEach((track) => track.stop());
    remoteStream?.getTracks().forEach((track) => track.stop());

    try {
      await peerConnection?.close();
    } catch (_) {}
    peerConnection = null;

    try {
      await localStream?.dispose();
    } catch (_) {}
    try {
      await remoteStream?.dispose();
    } catch (_) {}

    localStream = null;
    remoteStream = null;
    localVideo.srcObject = null;

    if (roomId != null) {
      try {
        final roomRef = db.collection('calls').doc(roomId);
        final callerCands = await roomRef.collection('callerCandidates').get();
        for (final doc in callerCands.docs) {
          await doc.reference.delete();
        }
        final calleeCands = await roomRef.collection('calleeCandidates').get();
        for (final doc in calleeCands.docs) {
          await doc.reference.delete();
        }
        await roomRef.delete();
      } catch (e) {
        logger.w('Error cleaning up room: $e');
      }
      roomId = null;
    }
    logger.i('WebRTC hung up and cleaned up');
  }

  void _registerPeerConnectionListeners() {
    peerConnection?.onConnectionState = (RTCPeerConnectionState state) {
      debugPrint('WebRTC connection state: $state');
      onCallStateChange?.call(state);
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        onConnectionConnected?.call();
      }
    };

    peerConnection?.onIceConnectionState = (RTCIceConnectionState state) {
      debugPrint('WebRTC ICE state: $state');
    };

    peerConnection?.onIceGatheringState = (RTCIceGatheringState state) {
      debugPrint('WebRTC ICE gathering state: $state');
    };

    peerConnection?.onSignalingState = (RTCSignalingState state) {
      debugPrint('WebRTC signaling state: $state');
    };

    // onTrack is the modern way (Unified Plan)
    peerConnection?.onTrack = (RTCTrackEvent event) {
      debugPrint(
          'WebRTC: onTrack event — kind=${event.track.kind}, streams=${event.streams.length}');
      if (event.streams.isNotEmpty) {
        remoteStream = event.streams[0];
        onAddRemoteStream?.call(event.streams[0]);
      }
    };

    // onAddStream is the legacy fallback (Plan B)
    peerConnection?.onAddStream = (MediaStream stream) {
      debugPrint('WebRTC: onAddStream event — id=${stream.id}');
      remoteStream = stream;
      onAddRemoteStream?.call(stream);
    };
  }

  void toggleMicrophone(bool isMuted) {
    localStream?.getAudioTracks().forEach((track) {
      track.enabled = !isMuted;
    });
  }

  void toggleCamera(bool isVideoOff) {
    localStream?.getVideoTracks().forEach((track) {
      track.enabled = !isVideoOff;
    });
  }

  void switchCamera() {
    final videoTracks = localStream?.getVideoTracks();
    if (videoTracks != null && videoTracks.isNotEmpty) {
      Helper.switchCamera(videoTracks[0]);
    }
  }
}
