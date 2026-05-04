enum MessageType { text, emoji, voice, callEvent }

class MessageModel {
  final String id;
  final String senderId;
  final String text;
  final MessageType type;
  final DateTime timestamp;
  final bool isEdited;
  final List<String> deletedFor;
  final String? voiceBase64;
  final String? voiceMimeType;
  final int? voiceDurationMs;
  final int? voiceSizeBytes;
  final String status;
  final String? replyToMessageId;
  final String? replyToText;
  final String? replyToSenderId;

  MessageModel({
    required this.id,
    required this.senderId,
    required this.text,
    required this.type,
    required this.timestamp,
    this.isEdited = false,
    this.deletedFor = const [],
    this.voiceBase64,
    this.voiceMimeType,
    this.voiceDurationMs,
    this.voiceSizeBytes,
    this.status = 'sent',
    this.replyToMessageId,
    this.replyToText,
    this.replyToSenderId,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'senderId': senderId,
      'text': text,
      'type': type.name,
      'timestamp': timestamp.millisecondsSinceEpoch,
      'isEdited': isEdited,
      'deletedFor': deletedFor,
      'voiceBase64': voiceBase64,
      'voiceMimeType': voiceMimeType,
      'voiceDurationMs': voiceDurationMs,
      'voiceSizeBytes': voiceSizeBytes,
      'status': status,
      'replyToMessageId': replyToMessageId,
      'replyToText': replyToText,
      'replyToSenderId': replyToSenderId,
    };
  }

  factory MessageModel.fromMap(String id, Map<dynamic, dynamic> map) {
    return MessageModel(
      id: id,
      senderId: map['senderId'] ?? '',
      text: map['text'] ?? '',
      type: MessageType.values.firstWhere(
        (e) => e.name == map['type'],
        orElse: () => MessageType.text,
      ),
      timestamp: DateTime.fromMillisecondsSinceEpoch(map['timestamp'] ?? 0),
      isEdited: map['isEdited'] ?? false,
      deletedFor: List<String>.from(map['deletedFor'] ?? []),
      voiceBase64: map['voiceBase64'] as String?,
      voiceMimeType: map['voiceMimeType'] as String?,
      voiceDurationMs: map['voiceDurationMs'] as int?,
      voiceSizeBytes: map['voiceSizeBytes'] as int?,
      status: (map['status'] as String?) ?? 'sent',
      replyToMessageId: map['replyToMessageId'] as String?,
      replyToText: map['replyToText'] as String?,
      replyToSenderId: map['replyToSenderId'] as String?,
    );
  }
}
