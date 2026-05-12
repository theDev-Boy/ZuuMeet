import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

import '../models/message_model.dart';

class LocalDbService {
  static final LocalDbService _instance = LocalDbService._internal();
  factory LocalDbService() => _instance;
  LocalDbService._internal();

  Database? _db;

  Future<Database> get db async {
    if (_db != null) return _db!;
    _db = await _initDb();
    return _db!;
  }

  Future<Database> _initDb() async {
    final databasesPath = await getDatabasesPath();
    final path = join(databasesPath, 'zuumeet_local.db');

    return await openDatabase(
      path,
      version: 2,
      onCreate: (Database db, int version) async {
        await db.execute('''
          CREATE TABLE cleared_chats (
            chatId TEXT PRIMARY KEY,
            clearedAt INTEGER
          )
        ''');
        await db.execute('''
          CREATE TABLE local_messages (
            id TEXT PRIMARY KEY,
            chatId TEXT,
            senderId TEXT,
            text TEXT,
            type TEXT,
            timestamp INTEGER,
            isEdited INTEGER,
            deletedFor TEXT,
            voiceBase64 TEXT,
            voiceMimeType TEXT,
            voiceDurationMs INTEGER,
            voiceSizeBytes INTEGER,
            status TEXT,
            replyToMessageId TEXT,
            replyToText TEXT,
            replyToSenderId TEXT,
            isPending INTEGER DEFAULT 0
          )
        ''');
      },
      onUpgrade: (Database db, int oldVersion, int newVersion) async {
        if (oldVersion < 2) {
          await db.execute('DROP TABLE IF EXISTS local_messages');
          await db.execute('''
            CREATE TABLE local_messages (
              id TEXT PRIMARY KEY,
              chatId TEXT,
              senderId TEXT,
              text TEXT,
              type TEXT,
              timestamp INTEGER,
              isEdited INTEGER,
              deletedFor TEXT,
              voiceBase64 TEXT,
              voiceMimeType TEXT,
              voiceDurationMs INTEGER,
              voiceSizeBytes INTEGER,
              status TEXT,
              replyToMessageId TEXT,
              replyToText TEXT,
              replyToSenderId TEXT,
              isPending INTEGER DEFAULT 0
            )
          ''');
        }
      },
    );
  }

  Map<String, dynamic> _messageToRow(
    String chatId,
    MessageModel message, {
    required bool isPending,
  }) {
    return {
      'id': message.id,
      'chatId': chatId,
      'senderId': message.senderId,
      'text': message.text,
      'type': message.type.name,
      'timestamp': message.timestamp.millisecondsSinceEpoch,
      'isEdited': message.isEdited ? 1 : 0,
      'deletedFor': message.deletedFor.join(','),
      'voiceBase64': message.voiceBase64,
      'voiceMimeType': message.voiceMimeType,
      'voiceDurationMs': message.voiceDurationMs,
      'voiceSizeBytes': message.voiceSizeBytes,
      'status': message.status,
      'replyToMessageId': message.replyToMessageId,
      'replyToText': message.replyToText,
      'replyToSenderId': message.replyToSenderId,
      'isPending': isPending ? 1 : 0,
    };
  }

  MessageModel _messageFromRow(Map<String, dynamic> row) {
    return MessageModel(
      id: row['id'] as String,
      senderId: row['senderId'] as String? ?? '',
      text: row['text'] as String? ?? '',
      type: MessageType.values.firstWhere(
        (value) => value.name == row['type'],
        orElse: () => MessageType.text,
      ),
      timestamp: DateTime.fromMillisecondsSinceEpoch(
        (row['timestamp'] as num?)?.toInt() ?? 0,
      ),
      isEdited: (row['isEdited'] as num?)?.toInt() == 1,
      deletedFor: ((row['deletedFor'] as String?) ?? '')
          .split(',')
          .where((value) => value.isNotEmpty)
          .toList(),
      voiceBase64: row['voiceBase64'] as String?,
      voiceMimeType: row['voiceMimeType'] as String?,
      voiceDurationMs: (row['voiceDurationMs'] as num?)?.toInt(),
      voiceSizeBytes: (row['voiceSizeBytes'] as num?)?.toInt(),
      status: row['status'] as String? ?? 'sent',
      replyToMessageId: row['replyToMessageId'] as String?,
      replyToText: row['replyToText'] as String?,
      replyToSenderId: row['replyToSenderId'] as String?,
    );
  }

  Future<void> cacheMessages(
    String chatId,
    List<MessageModel> messages,
  ) async {
    final dbClient = await db;
    final batch = dbClient.batch();
    for (final message in messages) {
      batch.insert(
        'local_messages',
        _messageToRow(chatId, message, isPending: false),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  Future<void> queuePendingMessage(String chatId, MessageModel message) async {
    final dbClient = await db;
    await dbClient.insert(
      'local_messages',
      _messageToRow(chatId, message, isPending: true),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> deleteLocalMessage(String messageId) async {
    final dbClient = await db;
    await dbClient.delete(
      'local_messages',
      where: 'id = ?',
      whereArgs: [messageId],
    );
  }

  Future<List<MessageModel>> getMessages(
    String chatId, {
    int afterTimestamp = 0,
  }) async {
    final dbClient = await db;
    final rows = await dbClient.query(
      'local_messages',
      where: 'chatId = ? AND timestamp > ?',
      whereArgs: [chatId, afterTimestamp],
      orderBy: 'timestamp ASC',
    );
    return rows.map(_messageFromRow).toList();
  }

  Future<List<MessageModel>> getPendingMessages({String? chatId}) async {
    final dbClient = await db;
    final rows = await dbClient.query(
      'local_messages',
      where: chatId == null ? 'isPending = 1' : 'chatId = ? AND isPending = 1',
      whereArgs: chatId == null ? null : [chatId],
      orderBy: 'timestamp ASC',
    );
    return rows.map(_messageFromRow).toList();
  }

  Future<List<MapEntry<String, MessageModel>>> getPendingMessageEntries() async {
    final dbClient = await db;
    final rows = await dbClient.query(
      'local_messages',
      where: 'isPending = 1',
      orderBy: 'timestamp ASC',
    );
    return rows
        .map(
          (row) => MapEntry(
            row['chatId'] as String? ?? '',
            _messageFromRow(row),
          ),
        )
        .toList();
  }

  Future<void> clearChatLocally(String chatId) async {
    final dbClient = await db;
    // The requirement: "Execute DELETE query on local SQLite/Hive box scoped to that chat ID."
    await dbClient.delete('local_messages', where: 'chatId = ?', whereArgs: [chatId]);
    
    // Also track the timestamp to hide remote messages older than this
    await dbClient.insert('cleared_chats', {
      'chatId': chatId,
      'clearedAt': DateTime.now().millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<int> getChatClearedAt(String chatId) async {
    final dbClient = await db;
    final List<Map<String, dynamic>> result = await dbClient.query(
      'cleared_chats',
      where: 'chatId = ?',
      whereArgs: [chatId],
    );
    if (result.isNotEmpty) {
      return result.first['clearedAt'] as int;
    }
    return 0;
  }
}
