import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_callkit_incoming/entities/call_event.dart';
import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import '../config/firebase_config.dart';
import 'system_call_service.dart';

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(
    options: const FirebaseOptions(
      apiKey: FirebaseConfig.apiKey,
      appId: FirebaseConfig.appId,
      messagingSenderId: FirebaseConfig.messagingSenderId,
      projectId: FirebaseConfig.projectId,
      databaseURL: FirebaseConfig.databaseURL,
      storageBucket: FirebaseConfig.storageBucket,
    ),
  );
  // Handle background messages
  debugPrint("Handling a background message: ${message.messageId}");
  if (message.data['type'] == 'call') {
    await SystemCallService().showIncomingCall(message.data);
  } else if (message.data['type'] == 'message') {
    await CallNotificationService().showMessageNotification(
      title: message.data['senderName'] ?? 'New message',
      body: message.data['body'] ?? 'Open chat',
      chatId: message.data['chatId'] ?? '',
    );
  }
}

class CallNotificationService {
  static final CallNotificationService _instance = CallNotificationService._internal();
  factory CallNotificationService() => _instance;
  CallNotificationService._internal();

  final FlutterLocalNotificationsPlugin _notifications = FlutterLocalNotificationsPlugin();
  final StreamController<String> _tapController = StreamController<String>.broadcast();
  Stream<String> get onNotificationTap => _tapController.stream;
  SystemCallService get _systemCalls => SystemCallService();

  Future<void> init() async {
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings();
    const initSettings = InitializationSettings(android: androidInit, iOS: iosInit);
    await _notifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (response) {
        final payload = response.payload;
        if (payload != null && payload.isNotEmpty) {
          _tapController.add(payload);
        }
      },
    );

    final androidImplementation = _notifications.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    await androidImplementation?.requestNotificationsPermission();

    // Create high importance channel
    const channel = AndroidNotificationChannel(
      'incoming_call_channel', 
      'Incoming Calls',
      description: 'Incoming call notification',
      importance: Importance.max,
      playSound: true,
      enableVibration: true,
    );
    await androidImplementation?.createNotificationChannel(channel);
    const msgChannel = AndroidNotificationChannel(
      'messages_channel',
      'Messages',
      description: 'New message notifications',
      importance: Importance.high,
    );
    await androidImplementation?.createNotificationChannel(msgChannel);

    // Setup Firebase Messaging
    await setupFcm();
    await _systemCalls.requestPermissions();
  }

  Future<void> setupFcm() async {
    FirebaseMessaging messaging = FirebaseMessaging.instance;

    // Request permissions (especially for iOS)
    await messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    // Get the token
    String? token = await messaging.getToken();
    debugPrint("FCM Token: $token");

    // Listen to background messages
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

    // Listen to foreground messages
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      debugPrint('Got a message whilst in the foreground!');
      unawaited(_handleForegroundMessage(message));
    });

    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      if (message.data['type'] == 'call') {
        _tapController.add(_callPayload(message.data));
        return;
      }
      final chatId = message.data['chatId'];
      if (chatId != null && chatId is String && chatId.isNotEmpty) {
        _tapController.add('chat:$chatId');
      }
    });
  }

  Future<void> _handleForegroundMessage(RemoteMessage message) async {
    if (message.data['type'] == 'call') {
      await _systemCalls.showIncomingCall(message.data);
      return;
    }
    if (message.data['type'] == 'message') {
      await showMessageNotification(
        title: message.data['senderName'] ?? 'New message',
        body: message.data['body'] ?? 'Open chat',
        chatId: message.data['chatId'] ?? '',
      );
    }
  }

  String _callPayload(Map<dynamic, dynamic> raw) {
    final data = raw.map(
      (key, value) => MapEntry(key.toString(), value?.toString() ?? ''),
    );
    final query = data.entries
        .map((entry) => '${entry.key}=${Uri.encodeComponent(entry.value)}')
        .join('&');
    return 'call:$query';
  }

  Stream<CallEvent?> get onSystemCallEvent => _systemCalls.onEvent;

  Future<void> registerCurrentUser(String uid) => _registerCurrentUser(uid);

  Future<void> _registerCurrentUser(String uid) async {
    final messaging = FirebaseMessaging.instance;
    final token = await messaging.getToken();
    if (token != null && token.isNotEmpty) {
      await FirebaseDatabase.instance.ref('users').child(uid).update({
        'fcmToken': token,
      });
    }
    await _systemCalls.registerVoipToken(uid);
    messaging.onTokenRefresh.listen((newToken) async {
      await FirebaseDatabase.instance.ref('users').child(uid).update({
        'fcmToken': newToken,
      });
    });
  }

  Map<String, dynamic> normalizedCallData(Map<dynamic, dynamic> data) {
    return _systemCalls.normalizedCallData(data);
  }

  Future<Map<String, dynamic>?> getActiveAcceptedCall() {
    return _systemCalls.getActiveAcceptedCall();
  }

  Future<void> showIncomingCallNotification(Map<dynamic, dynamic> callData) {
    return _systemCalls.showIncomingCall(callData);
  }

  Future<void> startOutgoingCallkit(Map<String, dynamic> callData) {
    return _systemCalls.startOutgoingCall(callData);
  }

  Future<void> setCallConnected(String callId) {
    return _systemCalls.setCallConnected(callId);
  }

  Future<void> endCallkit(String callId) {
    return _systemCalls.endCall(callId);
  }

  Future<void> endAllCallkits() {
    return _systemCalls.endAllCalls();
  }

  /// Show a persistent notification for an ongoing call.
  Future<void> showOngoingCallNotification(String partnerName) async {
    const androidDetails = AndroidNotificationDetails(
      'call_channel',
      'Ongoing Calls',
      channelDescription: 'Active call status',
      importance: Importance.max,
      priority: Priority.high,
      ongoing: true,
      autoCancel: false,
      showWhen: true,
      color: Color(0xFF6366F1),
      category: AndroidNotificationCategory.call,
    );
    const iosDetails = DarwinNotificationDetails();
    const details = NotificationDetails(android: androidDetails, iOS: iosDetails);

    await _notifications.show(
      10,
      'ZuuMeet · Active Call',
      'Ongoing call with $partnerName',
      details,
      payload: 'return_to_call',
    );
  }

  /// Show a simple incoming call notification fallback.
  Future<void> showIncomingCallBanner(String callerName) async {
    const androidDetails = AndroidNotificationDetails(
      'incoming_call_channel',
      'Incoming Calls',
      channelDescription: 'Incoming call notification',
      importance: Importance.max,
      priority: Priority.high,
      fullScreenIntent: true,
      category: AndroidNotificationCategory.call,
      playSound: true,
      enableVibration: true,
      color: Color(0xFF10B981),
    );
    const iosDetails = DarwinNotificationDetails(
      presentSound: true, 
      presentBadge: true, 
      presentAlert: true,
    );
    const details = NotificationDetails(android: androidDetails, iOS: iosDetails);

    await _notifications.show(
      11,
      'ZuuMeet · Incoming Call',
      '$callerName is calling you...',
      details,
      payload: 'answer_call',
    );
  }

  Future<void> showMessageNotification({
    required String title,
    required String body,
    required String chatId,
  }) async {
    const androidDetails = AndroidNotificationDetails(
      'messages_channel',
      'Messages',
      channelDescription: 'Message notifications',
      importance: Importance.high,
      priority: Priority.high,
      category: AndroidNotificationCategory.message,
    );
    const iosDetails = DarwinNotificationDetails(
      presentSound: true,
      presentBadge: true,
      presentAlert: true,
    );
    const details = NotificationDetails(android: androidDetails, iOS: iosDetails);
    await _notifications.show(
      12,
      title,
      body,
      details,
      payload: 'chat:$chatId',
    );
  }

  /// Dismiss the call notification.
  Future<void> dismissCallNotification() async {
    await _notifications.cancel(10);
  }
}
