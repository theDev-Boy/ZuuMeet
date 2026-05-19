import 'dart:async';

import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';

import '../models/chat_model.dart';
import '../models/message_model.dart';
import '../services/chat_service.dart';
import '../services/connectivity_service.dart';
import '../services/database_service.dart';
import '../services/local_db_service.dart';

class ChatProvider extends ChangeNotifier {
  final ChatService _service = ChatService();
  final LocalDbService _localDb = LocalDbService();
  final ConnectivityService _connectivity = ConnectivityService();
  final DatabaseService _database = DatabaseService();

  List<ChatModel> _chats = [];
  String _myUid = '';
  final Map<String, bool> _statusUpdateInFlight = {};
  final Map<String, StreamController<List<MessageModel>>> _messageControllers =
      {};
  final Map<String, StreamSubscription<DatabaseEvent>> _messageSubscriptions = {};
  final Map<String, StreamSubscription<bool>> _connectivitySubscriptions = {};

  StreamSubscription<DatabaseEvent>? _chatSubscription;
  StreamSubscription<bool>? _globalConnectivitySubscription;

  List<ChatModel> get chats => _chats;

  void init(String myUid) {
    _myUid = myUid;
    _chatSubscription?.cancel();
    _chatSubscription = _service.listenForUserChats(myUid).listen((event) {
      if (event.snapshot.value != null) {
        final data = event.snapshot.value as Map<dynamic, dynamic>;
        _chats = data.entries
            .map((e) => ChatModel.fromMap(e.key, e.value))
            .where((chat) => chat.participants.contains(myUid))
            .toList();
        _chats.sort((a, b) => b.lastMessageTime.compareTo(a.lastMessageTime));
        notifyListeners();
      } else {
        _chats = [];
        notifyListeners();
      }
    });

    _globalConnectivitySubscription?.cancel();
    _globalConnectivitySubscription =
        _connectivity.onStatusChanged.listen((offline) {
      if (!offline) {
        unawaited(_flushPendingMessages());
      }
      for (final chatId in _messageControllers.keys) {
        unawaited(_emitMergedMessages(chatId));
      }
    });
  }

  Stream<List<MessageModel>> getMessages(String chatId) {
    if (_messageControllers.containsKey(chatId)) {
      return _messageControllers[chatId]!.stream;
    }

    final controller = StreamController<List<MessageModel>>.broadcast(
      onCancel: () => _disposeChatStream(chatId),
    );
    _messageControllers[chatId] = controller;

    _messageSubscriptions[chatId] =
        _service.listenForMessages(chatId).listen((event) async {
      final messages = <MessageModel>[];
      if (event.snapshot.value != null) {
        final data = event.snapshot.value as Map<dynamic, dynamic>;
        messages.addAll(
          data.entries.map((e) => MessageModel.fromMap(e.key, e.value)),
        );
        messages.sort((a, b) => a.timestamp.compareTo(b.timestamp));
        await _localDb.cacheMessages(chatId, messages);
      }
      await _emitMergedMessages(chatId, remoteMessages: messages);
    });

    _connectivitySubscriptions[chatId] =
        _connectivity.onStatusChanged.listen((_) async {
      await _emitMergedMessages(chatId);
    });

    unawaited(_emitMergedMessages(chatId));
    return controller.stream;
  }

  Future<void> _emitMergedMessages(
    String chatId, {
    List<MessageModel>? remoteMessages,
  }) async {
    final controller = _messageControllers[chatId];
    if (controller == null || controller.isClosed) {
      return;
    }

    final clearedAt = await _localDb.getChatClearedAt(chatId);
    final cached = remoteMessages ??
        await _localDb.getMessages(chatId, afterTimestamp: clearedAt);
    final pending = await _localDb.getPendingMessages(chatId: chatId);

    final merged = <String, MessageModel>{};
    for (final message in [...cached, ...pending]) {
      if (message.timestamp.millisecondsSinceEpoch <= clearedAt) {
        continue;
      }
      if (_myUid.isNotEmpty && message.deletedFor.contains(_myUid)) {
        continue;
      }
      merged[message.id] = message;
    }

    final values = merged.values.toList()
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    controller.add(values);
  }

  Stream<ChatModel?> getChatMeta(String chatId) {
    return FirebaseDatabase.instance.ref('chats_meta').child(chatId).onValue.map(
      (event) {
        if (event.snapshot.value == null) return null;
        return ChatModel.fromMap(chatId, event.snapshot.value as Map);
      },
    );
  }

  Future<void> sendMessage(
    String chatId,
    MessageModel message, {
    String? senderName,
  }) async {
    final normalizedMessage = MessageModel(
      id: message.id.isEmpty
          ? 'local-${DateTime.now().microsecondsSinceEpoch}'
          : message.id,
      senderId: message.senderId,
      text: message.text,
      type: message.type,
      timestamp: message.timestamp,
      isEdited: message.isEdited,
      deletedFor: message.deletedFor,
      voiceBase64: message.voiceBase64,
      voiceMimeType: message.voiceMimeType,
      voiceDurationMs: message.voiceDurationMs,
      voiceSizeBytes: message.voiceSizeBytes,
      status: _connectivity.isOffline ? 'waiting' : message.status,
      replyToMessageId: message.replyToMessageId,
      replyToText: message.replyToText,
      replyToSenderId: message.replyToSenderId,
    );

    if (_connectivity.isOffline) {
      await _localDb.queuePendingMessage(chatId, normalizedMessage);
      await _emitMergedMessages(chatId);
      return;
    }

    await _service.sendMessage(
      chatId,
      normalizedMessage,
      senderName: senderName,
    );
    await _localDb.deleteLocalMessage(normalizedMessage.id);
    await _emitMergedMessages(chatId);
  }

  Future<void> _flushPendingMessages() async {
    if (_myUid.isEmpty) {
      return;
    }
    final pendingMessages = await _localDb.getPendingMessageEntries();
    for (final entry in pendingMessages) {
      final chatId = entry.key;
      final message = entry.value;
      if (chatId.isEmpty) {
        continue;
      }
      await _service.sendMessage(chatId, message);
      await _localDb.deleteLocalMessage(message.id);
      await _emitMergedMessages(chatId);
    }
  }

  Future<void> markDelivered(String chatId) async {
    await _markIncomingStatus(chatId, targetStatus: 'delivered');
  }

  Future<void> markSeen(String chatId) async {
    await _markIncomingStatus(chatId, targetStatus: 'seen');
    if (_myUid.isNotEmpty) {
      await FirebaseDatabase.instance
          .ref('chats_meta')
          .child(chatId)
          .child('unreadCounts')
          .child(_myUid)
          .set(0);
    }
  }

  Future<void> _markIncomingStatus(
    String chatId, {
    required String targetStatus,
  }) async {
    final key = '$chatId:$targetStatus';
    if (_statusUpdateInFlight[key] == true || _myUid.isEmpty) return;
    _statusUpdateInFlight[key] = true;
    try {
      await _service.markIncomingMessageStatus(
        chatId,
        _myUid,
        targetStatus: targetStatus,
      );
    } finally {
      _statusUpdateInFlight[key] = false;
    }
  }

  Future<void> setTyping(String chatId, String myUid, bool isTyping) async {
    if (_connectivity.isOffline) {
      return;
    }
    await _service.setTypingStatus(chatId, myUid, isTyping);
  }

  Future<void> deleteMessage(
    String chatId,
    String messageId, {
    bool everyone = false,
  }) async {
    final ref = FirebaseDatabase.instance
        .ref('chats')
        .child(chatId)
        .child('messages')
        .child(messageId);
    if (everyone) {
      // Write a ghost "deleted" record visible to everyone
      await ref.update({
        'text': '🗑️ This message was deleted',
        'type': 'text',
        'voiceBase64': null,
        'voiceMimeType': null,
        'voiceDurationMs': null,
        'voiceSizeBytes': null,
        'deletedForEveryone': true,
        'isEdited': false,
      });
    } else {
      if (_myUid.isNotEmpty) {
        final snap = await ref.child('deletedFor').get();
        List<String> current = [];
        if (snap.exists && snap.value != null) {
          final val = snap.value;
          if (val is List) {
            current = val.map((e) => e.toString()).toList();
          } else if (val is Map) {
            current = val.values.map((e) => e.toString()).toList();
          }
        }
        if (!current.contains(_myUid)) {
          current.add(_myUid);
          await ref.child('deletedFor').set(current);
        }
      }
    }
  }

  Future<void> editMessage(String chatId, String messageId, String newText) async {
    await FirebaseDatabase.instance
        .ref('chats')
        .child(chatId)
        .child('messages')
        .child(messageId)
        .update({
      'text': newText,
      'isEdited': true,
    });
  }

  Future<void> clearChat(String chatId) async {
    await _localDb.clearChatLocally(chatId);
    await _emitMergedMessages(chatId);
    notifyListeners();
  }

  Future<void> blockUser(String myUid, String partnerId) async {
    await _database.blockUser(myUid, partnerId);
  }

  void _disposeChatStream(String chatId) {
    _messageSubscriptions.remove(chatId)?.cancel();
    _connectivitySubscriptions.remove(chatId)?.cancel();
    _messageControllers.remove(chatId)?.close();
  }

  @override
  void dispose() {
    _chatSubscription?.cancel();
    _globalConnectivitySubscription?.cancel();
    for (final chatId in _messageControllers.keys.toList()) {
      _disposeChatStream(chatId);
    }
    super.dispose();
  }
}
