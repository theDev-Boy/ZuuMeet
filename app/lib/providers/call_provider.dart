import 'dart:async';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../models/match_model.dart';
import '../models/user_model.dart';
import '../services/call_notification_service.dart';
import '../services/database_service.dart';
import '../services/webrtc_service.dart';
import '../utils/constants.dart';

enum CallState { idle, searching, connecting, connected, ended, error }

class CallProvider extends ChangeNotifier {
  final DatabaseService _db = DatabaseService();
  final WebRTCService _webRTCService = WebRTCService();

  final RTCVideoRenderer localRenderer = RTCVideoRenderer();
  final RTCVideoRenderer remoteRenderer = RTCVideoRenderer();

  CallState _state = CallState.idle;
  MatchModel? _currentMatch;
  String? _partnerName;
  String? _partnerCountry;
  int _callDurationSeconds = 0;
  Timer? _callTimer;
  String? _error;

  bool _isMicMuted = false;
  bool _isCameraOff = false;
  bool _videoEnabled = true;
  String _connectionStatus = 'Idle';

  StreamSubscription? _matchStatusSub;
  StreamSubscription? _searchSub;
  bool _isMinimized = false;

  bool get isMinimized => _isMinimized;
  void toggleMinimize() {
    _isMinimized = !_isMinimized;
    notifyListeners();
  }

  CallState get state => _state;
  MatchModel? get currentMatch => _currentMatch;
  String? get partnerName => _partnerName;
  String? get partnerCountry => _partnerCountry;
  int get callDurationSeconds => _callDurationSeconds;
  String? get error => _error;
  bool get isMicMuted => _isMicMuted;
  bool get isCameraOff => _isCameraOff;
  bool get isVideoCall => _videoEnabled;
  String get connectionStatus => _connectionStatus;

  String get callDurationFormatted {
    final m = (_callDurationSeconds ~/ 60).toString().padLeft(2, '0');
    final s = (_callDurationSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  CallProvider() {
    _initRenderers();
  }

  Future<void> _initRenderers() async {
    await localRenderer.initialize();
    await remoteRenderer.initialize();
    
    _webRTCService.onAddRemoteStream = (stream) {
      remoteRenderer.srcObject = stream;
      notifyListeners();
    };
    
    _webRTCService.onCallStateChange = (state) {
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        _connectionStatus = 'Connected';
        notifyListeners();
      } else if (state == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected ||
                 state == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
        _onPartnerEndedCall();
      }
    };
  }

  Future<void> startSearching(UserModel currentUser, {bool videoEnabled = true}) async {
    if (_state != CallState.idle && _state != CallState.ended) return;
    _videoEnabled = videoEnabled;

    _state = CallState.searching;
    _error = null;
    _callDurationSeconds = 0;
    _connectionStatus = 'Searching...';
    
    await _webRTCService.initLocalStream(localRenderer, isVideo: videoEnabled);
    notifyListeners();

    try {
      await _db.joinSearchQueue(currentUser);

      _searchSub = FirebaseDatabase.instance
          .ref(AppConstants.activeUsersPath)
          .onValue
          .listen((event) async {
            if (_state != CallState.searching || !event.snapshot.exists) return;

            final data = event.snapshot.value as Map<dynamic, dynamic>;
            for (final entry in data.entries) {
              final partnerUid = entry.key as String;
              if (partnerUid == currentUser.uid) continue;

              final partnerData = entry.value as Map<dynamic, dynamic>;
              final partnerStatus = partnerData['status'] as String? ?? '';

              if (partnerStatus == 'searching') {
                final isInitiator = currentUser.uid.compareTo(partnerUid) < 0;

                if (isInitiator) {
                  final matchId = await _db.createMatch(
                    user1: currentUser.uid,
                    user2: partnerUid,
                    user1Name: currentUser.name,
                    user2Name: partnerData['name'] as String? ?? 'Anonymous',
                  );

                  _partnerName = partnerData['name'] as String? ?? 'Anonymous';
                  _partnerCountry = partnerData['country'] as String? ?? '';
                  _currentMatch = await _db.getMatch(matchId);

                  await _startCallAsInitiator(matchId, currentUser.uid, partnerUid);
                  break;
                }
              }
            }
          });

      _db.listenForMatch(currentUser.uid).listen((event) {
        if (!event.snapshot.exists || event.snapshot.value == null) return;
        final data = event.snapshot.value as Map<dynamic, dynamic>;
        final status = data['status'] as String? ?? '';
        if (status == 'matched' && (_state == CallState.searching || _state == CallState.ended)) {
          final matchId = data['matchId'] as String?;
          final roomId = data['roomId'] as String?;
          if (matchId != null && roomId != null) {
            _onMatchedByPartner(matchId, roomId, currentUser);
          }
        }
      });
    } catch (e) {
      _error = 'Connection failed.';
      _state = CallState.idle;
      notifyListeners();
    }
  }

  Future<void> startDirectCall(String myUid, String partnerUid, {bool isVideo = true}) async {
    _videoEnabled = isVideo;
    _state = CallState.connecting;
    _connectionStatus = 'Calling...';
    notifyListeners();

    try {
      await _webRTCService.initLocalStream(localRenderer, isVideo: _videoEnabled);
      final roomId = await _webRTCService.createRoom(myUid, partnerUid, isVideo: _videoEnabled);
      debugPrint('WebRTC Room Created: $roomId');
      // RoomId would typically be sent to the partner via FCM or CallNotificationService here
      _state = CallState.connected;
      _startCallTimer();
      notifyListeners();
    } catch (e) {
      _error = 'Direct call failed.';
      _state = CallState.error;
      notifyListeners();
    }
  }

  Future<void> answerDirectCall(String roomId, {bool isVideo = true}) async {
    _videoEnabled = isVideo;
    _state = CallState.connecting;
    _connectionStatus = 'Connecting...';
    notifyListeners();

    try {
      await _webRTCService.initLocalStream(localRenderer, isVideo: _videoEnabled);
      await _webRTCService.joinRoom(roomId);
      _state = CallState.connected;
      _startCallTimer();
      notifyListeners();
    } catch (e) {
      _error = 'Failed to answer call.';
      _state = CallState.error;
      notifyListeners();
    }
  }

  Future<void> _startCallAsInitiator(String matchId, String myUid, String partnerUid) async {
    _state = CallState.connecting;
    _connectionStatus = 'Connecting...';
    notifyListeners();

    try {
      final roomId = await _webRTCService.createRoom(myUid, partnerUid, isVideo: _videoEnabled);
      await _db.updateMatch(matchId, {'roomId': roomId});
      
      _state = CallState.connected;
      _startCallTimer();
      _listenForMatchEnd(matchId);
      notifyListeners();
    } catch (e) {
      _error = 'Connection failed.';
      _state = CallState.error;
      notifyListeners();
    }
  }

  Future<void> _onMatchedByPartner(String matchId, String roomId, UserModel currentUser) async {
    if (_state != CallState.searching && _state != CallState.ended) return;

    try {
      _currentMatch = await _db.getMatch(matchId);
      if (_currentMatch == null) return;

      _partnerName = _currentMatch!.getPartnerName(currentUser.uid) ?? 'Partner';
      _searchSub?.cancel();

      _state = CallState.connecting;
      _connectionStatus = 'Connecting...';
      notifyListeners();

      await _webRTCService.joinRoom(roomId);

      _state = CallState.connected;
      _startCallTimer();
      _listenForMatchEnd(matchId);
      notifyListeners();
    } catch (e) {
      _error = 'Failed to accept call.';
      _state = CallState.error;
      notifyListeners();
    }
  }

  void _listenForMatchEnd(String matchId) {
    _matchStatusSub = _db.listenForMatchStatus(matchId).listen((event) {
      if (!event.snapshot.exists) return;
      final status = event.snapshot.value as String?;
      if ((status == 'ended' || status == 'declined' || status == 'busy') && _state == CallState.connected) {
        _onPartnerEndedCall();
      }
    });
  }

  void _onPartnerEndedCall() async {
    _stopCallTimer();
    _cancelSubscriptions();
    await _webRTCService.hangUp(localRenderer);
    CallNotificationService().dismissCallNotification();

    _currentMatch = null;
    _partnerName = null;
    _partnerCountry = null;
    _callDurationSeconds = 0;
    
    _state = CallState.ended;
    notifyListeners();

    Timer(const Duration(seconds: 2), () {
      if (_state == CallState.ended) {
        _state = CallState.idle;
        notifyListeners();
      }
    });
  }

  Future<void> endCall(String myUid) async {
    _stopCallTimer();
    _cancelSubscriptions();
    if (_currentMatch != null) {
      await _db.endMatch(_currentMatch!.matchId);
    }
    await _db.leaveSearchQueue(myUid);
    await _webRTCService.hangUp(localRenderer);
    CallNotificationService().dismissCallNotification();

    _currentMatch = null;
    _partnerName = null;
    _partnerCountry = null;
    _state = CallState.idle;
    _callDurationSeconds = 0;
    notifyListeners();
  }

  Future<void> stopCompletely(String myUid) async {
    await endCall(myUid);
  }

  void toggleMic() {
    _isMicMuted = !_isMicMuted;
    _webRTCService.toggleMicrophone(_isMicMuted);
    notifyListeners();
  }

  void toggleCamera() {
    _isCameraOff = !_isCameraOff;
    _webRTCService.toggleCamera(_isCameraOff);
    notifyListeners();
  }

  void switchCamera() {
    _webRTCService.switchCamera();
    notifyListeners();
  }

  Future<void> nextPartner(UserModel currentUser) async {
    await endCall(currentUser.uid);
    await startSearching(currentUser);
  }

  void _startCallTimer() {
    _callTimer?.cancel();
    _callDurationSeconds = 0;
    _callTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _callDurationSeconds++;
      notifyListeners();
    });
  }

  void _stopCallTimer() {
    _callTimer?.cancel();
    _callTimer = null;
  }

  void _cancelSubscriptions() {
    _matchStatusSub?.cancel();
    _searchSub?.cancel();
  }

  @override
  void dispose() {
    _stopCallTimer();
    _cancelSubscriptions();
    localRenderer.dispose();
    remoteRenderer.dispose();
    super.dispose();
  }
}
