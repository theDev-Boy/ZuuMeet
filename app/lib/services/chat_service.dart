import 'package:firebase_database/firebase_database.dart';
import '../models/message_model.dart';

class ChatService {
  final DatabaseReference _db = FirebaseDatabase.instance.ref();

  /// Get or create a chat ID between two users.
  String getChatId(String uid1, String uid2) {
    List<String> ids = [uid1, uid2];
    ids.sort();
    return ids.join('_');
  }

  /// Send a message to a chat.
  Future<void> sendMessage(String chatId, MessageModel message) async {
    final msgData = message.toMap();
    await _db.child('chats').child(chatId).child('messages').push().set(msgData);
    final participants = chatId.split('_');
    final metaRef = _db.child('chats_meta').child(chatId);
    final metaSnapshot = await metaRef.get();
    final currentMeta = metaSnapshot.value is Map
        ? Map<dynamic, dynamic>.from(metaSnapshot.value as Map)
        : const <dynamic, dynamic>{};
    final existingUnread = currentMeta['unreadCounts'] is Map
        ? Map<String, dynamic>.from(currentMeta['unreadCounts'] as Map)
        : <String, dynamic>{};
    final unreadCounts = <String, int>{};
    for (final uid in participants) {
      final currentCount = (existingUnread[uid] as num?)?.toInt() ?? 0;
      unreadCounts[uid] = uid == message.senderId ? 0 : currentCount + 1;
    }
    final lastMessage =
        message.type == MessageType.voice ? 'Voice message' : message.text;

    await metaRef.update({
      'lastMessage': lastMessage,
      'lastMessageTime': message.timestamp.millisecondsSinceEpoch,
      'participants': participants,
      'unreadCounts': unreadCounts,
    });
  }

  Future<void> markIncomingMessageStatus(
    String chatId,
    String myUid, {
    required String targetStatus,
  }) async {
    final messagesRef = _db.child('chats').child(chatId).child('messages');
    final snapshot = await messagesRef.get();
    if (!snapshot.exists || snapshot.value == null) return;
    if (snapshot.value is! Map) return;

    final updates = <String, Object?>{};
    final data = Map<dynamic, dynamic>.from(snapshot.value as Map);
    for (final entry in data.entries) {
      final msgId = entry.key.toString();
      final map = entry.value is Map
          ? Map<dynamic, dynamic>.from(entry.value as Map)
          : <dynamic, dynamic>{};
      final senderId = (map['senderId'] ?? '').toString();
      final currentStatus = (map['status'] ?? 'sent').toString();
      if (senderId.isEmpty || senderId == myUid) continue;
      if (targetStatus == 'delivered' && currentStatus == 'seen') continue;
      if (currentStatus == targetStatus) continue;
      updates['$msgId/status'] = targetStatus;
    }
    if (updates.isNotEmpty) {
      await messagesRef.update(updates);
    }
  }

  /// Listen for messages in a chat.
  Stream<DatabaseEvent> listenForMessages(String chatId) {
    return _db.child('chats').child(chatId).child('messages').orderByChild('timestamp').onValue;
  }

  /// Listen for all chats a user is part of.
  Stream<DatabaseEvent> listenForUserChats(String myUid) {
    // In a real app, we might use a user_chats index.
    // For simplicity, we filter in the provider or use a custom index.
    return _db.child('chats_meta').onValue;
  }

  /// Set typing status.
  Future<void> setTypingStatus(String chatId, String myUid, bool isTyping) async {
    await _db.child('chats_meta').child(chatId).child('typingStatus').update({
      myUid: isTyping,
    });
  }

  /// Mark message as deleted for everyone.
  Future<void> deleteMessage(String chatId, String messageId) async {
    // Implementation for 'delete for everyone'
    // Typically requires searching for the message key in the 'messages' list.
  }

  /// Clear chat locally (simplified for this app).
  Future<void> clearChatLocally(String chatId, String myUid) async {
    // In a real app, we store a 'lastClearedTimestamp' for the user locally or in DB.
  }
}
