import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../utils/logger.dart';

typedef StreamStateCallback = void Function(MediaStream stream);
typedef CallStateCallback = void Function(RTCPeerConnectionState state);

class WebRTCService {
  RTCPeerConnection? peerConnection;
  MediaStream? localStream;
  MediaStream? remoteStream;
  String? roomId;
  String? currentRoomText;
  StreamStateCallback? onAddRemoteStream;
  CallStateCallback? onCallStateChange;

  final FirebaseFirestore db = FirebaseFirestore.instance;

  final Map<String, dynamic> configuration = {
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'},
      {'urls': 'stun:stun1.l.google.com:19302'},
    ]
  };

  /// Initialize local media stream
  Future<void> initLocalStream(RTCVideoRenderer localVideo, {bool isVideo = true}) async {
    final Map<String, dynamic> mediaConstraints = {
      'audio': true,
      'video': isVideo ? {'facingMode': 'user'} : false,
    };

    try {
      localStream = await navigator.mediaDevices.getUserMedia(mediaConstraints);
      localVideo.srcObject = localStream;
    } catch (e) {
      logger.e('Error getting user media: $e');
    }
  }

  /// Create a room (Caller)
  Future<String> createRoom(String callerId, String calleeId, {bool isVideo = true}) async {
    peerConnection = await createPeerConnection(configuration);

    registerPeerConnectionListeners();

    localStream?.getTracks().forEach((track) {
      peerConnection?.addTrack(track, localStream!);
    });

    var roomRef = db.collection('calls').doc();
    var callerCandidatesRef = roomRef.collection('callerCandidates');

    peerConnection?.onIceCandidate = (RTCIceCandidate candidate) {
      callerCandidatesRef.add(candidate.toMap());
    };

    RTCSessionDescription offer = await peerConnection!.createOffer();
    await peerConnection!.setLocalDescription(offer);

    Map<String, dynamic> roomWithOffer = {
      'callerId': callerId,
      'calleeId': calleeId,
      'type': isVideo ? 'video' : 'audio',
      'offer': offer.toMap(),
    };

    await roomRef.set(roomWithOffer);
    roomId = roomRef.id;

    peerConnection?.onTrack = (RTCTrackEvent event) {
      event.streams[0].getTracks().forEach((track) {
        remoteStream?.addTrack(track);
      });
    };

    // Listen for remote answer
    roomRef.snapshots().listen((snapshot) async {
      if (!snapshot.exists) return;
      var data = snapshot.data() as Map<String, dynamic>;
      if (peerConnection?.getRemoteDescription() != null && data['answer'] != null) {
        var answer = RTCSessionDescription(
          data['answer']['sdp'],
          data['answer']['type'],
        );
        await peerConnection?.setRemoteDescription(answer);
      }
    });

    // Listen for remote ICE candidates
    roomRef.collection('calleeCandidates').snapshots().listen((snapshot) {
      for (var change in snapshot.docChanges) {
        if (change.type == DocumentChangeType.added) {
          var data = change.doc.data() as Map<String, dynamic>;
          peerConnection!.addCandidate(
            RTCIceCandidate(
              data['candidate'],
              data['sdpMid'],
              data['sdpMLineIndex'],
            ),
          );
        }
      }
    });

    return roomId!;
  }

  /// Join a room (Callee)
  Future<void> joinRoom(String roomId) async {
    var roomRef = db.collection('calls').doc(roomId);
    var roomSnapshot = await roomRef.get();

    if (!roomSnapshot.exists) return;

    peerConnection = await createPeerConnection(configuration);
    registerPeerConnectionListeners();

    localStream?.getTracks().forEach((track) {
      peerConnection?.addTrack(track, localStream!);
    });

    var calleeCandidatesRef = roomRef.collection('calleeCandidates');
    peerConnection?.onIceCandidate = (RTCIceCandidate candidate) {
      calleeCandidatesRef.add(candidate.toMap());
    };

    peerConnection?.onTrack = (RTCTrackEvent event) {
      event.streams[0].getTracks().forEach((track) {
        remoteStream?.addTrack(track);
      });
    };

    var data = roomSnapshot.data() as Map<String, dynamic>;
    var offer = data['offer'];
    await peerConnection?.setRemoteDescription(
      RTCSessionDescription(offer['sdp'], offer['type']),
    );

    var answer = await peerConnection!.createAnswer();
    await peerConnection!.setLocalDescription(answer);

    await roomRef.update({
      'answer': {'type': answer.type, 'sdp': answer.sdp}
    });

    roomRef.collection('callerCandidates').snapshots().listen((snapshot) {
      for (var change in snapshot.docChanges) {
        if (change.type == DocumentChangeType.added) {
          var data = change.doc.data() as Map<String, dynamic>;
          peerConnection!.addCandidate(
            RTCIceCandidate(
              data['candidate'],
              data['sdpMid'],
              data['sdpMLineIndex'],
            ),
          );
        }
      }
    });
  }

  /// Hangup / Disconnect
  Future<void> hangUp(RTCVideoRenderer localVideo) async {
    localStream?.getTracks().forEach((track) => track.stop());
    remoteStream?.getTracks().forEach((track) => track.stop());
    await peerConnection?.close();
    peerConnection = null;
    localStream?.dispose();
    remoteStream?.dispose();
    localVideo.srcObject = null;

    if (roomId != null) {
      var roomRef = db.collection('calls').doc(roomId);
      await roomRef.delete();
    }
  }

  void registerPeerConnectionListeners() {
    peerConnection?.onAddStream = (MediaStream stream) {
      onAddRemoteStream?.call(stream);
      remoteStream = stream;
    };
    peerConnection?.onConnectionState = (RTCPeerConnectionState state) {
      onCallStateChange?.call(state);
    };
  }

  void toggleMicrophone(bool isMuted) {
    if (localStream != null) {
      for (var track in localStream!.getAudioTracks()) {
        track.enabled = !isMuted;
      }
    }
  }

  void toggleCamera(bool isVideoOff) {
    if (localStream != null) {
      for (var track in localStream!.getVideoTracks()) {
        track.enabled = !isVideoOff;
      }
    }
  }

  void switchCamera() {
    if (localStream != null) {
      Helper.switchCamera(localStream!.getVideoTracks()[0]);
    }
  }
}
