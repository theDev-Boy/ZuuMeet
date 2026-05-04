import 'package:firebase_database/firebase_database.dart';
import 'package:flutter_callkit_incoming/entities/android_params.dart';
import 'package:flutter_callkit_incoming/entities/call_event.dart';
import 'package:flutter_callkit_incoming/entities/call_kit_params.dart';
import 'package:flutter_callkit_incoming/entities/ios_params.dart';
import 'package:flutter_callkit_incoming/entities/notification_params.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';

import '../utils/constants.dart';

class SystemCallService {
  static final SystemCallService _instance = SystemCallService._internal();
  factory SystemCallService() => _instance;
  SystemCallService._internal();

  Stream<CallEvent?> get onEvent => FlutterCallkitIncoming.onEvent;

  Future<void> requestPermissions() async {
    await FlutterCallkitIncoming.requestNotificationPermission({
      'title': 'Notification Permission',
      'rationaleMessagePermission':
          'Notification permission is required to show calls and messages.',
      'postNotificationMessageRequired':
          'Please enable notification permission in settings.',
    });
    try {
      await FlutterCallkitIncoming.requestFullIntentPermission();
    } catch (_) {
      // Android < 14 and non-Android platforms do not need this.
    }
  }

  Map<String, dynamic> normalizedCallData(Map<dynamic, dynamic> data) {
    final normalized = data.map(
      (key, value) => MapEntry(key.toString(), value),
    );
    final extra = normalized['extra'];
    if (extra is Map) {
      final merged = Map<String, dynamic>.from(normalized);
      merged.addAll(extra.map((key, value) => MapEntry(key.toString(), value)));
      return merged;
    }
    return Map<String, dynamic>.from(normalized);
  }

  Map<String, dynamic> eventBodyToCallData(dynamic body) {
    if (body is Map) {
      return normalizedCallData(body);
    }
    return <String, dynamic>{};
  }

  Future<void> registerVoipToken(String uid) async {
    final voipToken = await FlutterCallkitIncoming.getDevicePushTokenVoIP();
    if (voipToken is String && voipToken.isNotEmpty) {
      await FirebaseDatabase.instance
          .ref(AppConstants.usersPath)
          .child(uid)
          .update({'voipToken': voipToken});
    }
  }

  Future<Map<String, dynamic>?> getActiveAcceptedCall() async {
    final calls = await FlutterCallkitIncoming.activeCalls();
    if (calls is! List || calls.isEmpty) return null;
    final raw = calls.first;
    if (raw is! Map) return null;
    final normalized = normalizedCallData(raw);
    final isAccepted = normalized['isAccepted'];
    if (isAccepted == true || isAccepted == 'true') {
      return normalized;
    }
    return null;
  }

  Future<void> showIncomingCall(Map<dynamic, dynamic> rawCallData) async {
    final callData = normalizedCallData(rawCallData);
    final params = _buildCallKitParams(callData: callData, outgoing: false);
    await FlutterCallkitIncoming.showCallkitIncoming(params);
  }

  Future<void> startOutgoingCall(Map<String, dynamic> callData) async {
    final params = _buildCallKitParams(callData: callData, outgoing: true);
    await FlutterCallkitIncoming.startCall(params);
  }

  Future<void> setCallConnected(String callId) async {
    await FlutterCallkitIncoming.setCallConnected(callId);
  }

  Future<void> endCall(String callId) async {
    await FlutterCallkitIncoming.endCall(callId);
  }

  Future<void> endAllCalls() async {
    await FlutterCallkitIncoming.endAllCalls();
  }

  CallKitParams _buildCallKitParams({
    required Map<String, dynamic> callData,
    required bool outgoing,
  }) {
    final isVideo = (callData['callType'] ?? 'video') == 'video';
    final remoteName = outgoing
        ? (callData['calleeName'] as String? ?? 'Unknown')
        : (callData['callerName'] as String? ?? 'Unknown');
    final remoteAvatar = outgoing
        ? (callData['calleeAvatar'] as String? ?? '')
        : (callData['callerAvatar'] as String? ?? '');

    return CallKitParams(
      id: (callData['callId'] ?? callData['matchId']).toString(),
      nameCaller: remoteName,
      appName: AppConstants.appName,
      avatar: remoteAvatar,
      handle: isVideo ? 'Video call' : 'Audio call',
      type: isVideo ? 1 : 0,
      duration: 30000,
      textAccept: 'Accept',
      textDecline: 'Decline',
      missedCallNotification: const NotificationParams(
        showNotification: true,
        isShowCallback: false,
        subtitle: 'Missed call',
        callbackText: 'Open app',
      ),
      callingNotification: const NotificationParams(
        showNotification: true,
        isShowCallback: false,
        subtitle: 'Calling...',
        callbackText: 'Hang up',
      ),
      extra: callData,
      android: AndroidParams(
        isCustomNotification: true,
        isShowLogo: true,
        logoUrl: 'new_logo.png',
        isShowCallID: false,
        ringtonePath: 'system_ringtone_default',
        backgroundColor: '#0F172A',
        backgroundUrl: remoteAvatar.isNotEmpty ? remoteAvatar : null,
        actionColor: '#10B981',
        textColor: '#FFFFFF',
        incomingCallNotificationChannelName: 'Incoming Call',
        missedCallNotificationChannelName: 'Missed Call',
        isShowFullLockedScreen: true,
        isImportant: true,
        isBot: false,
      ),
      ios: IOSParams(
        handleType: 'generic',
        supportsVideo: isVideo,
        maximumCallGroups: 1,
        maximumCallsPerCallGroup: 1,
        audioSessionMode: 'default',
        audioSessionActive: true,
        audioSessionPreferredSampleRate: 44100,
        audioSessionPreferredIOBufferDuration: 0.005,
        supportsDTMF: false,
        supportsHolding: false,
        supportsGrouping: false,
        supportsUngrouping: false,
      ),
    );
  }
}
