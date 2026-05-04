import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:audioplayers/audioplayers.dart';
import '../providers/auth_provider.dart';
import '../providers/chat_provider.dart';
import '../models/message_model.dart';
import '../models/chat_model.dart';
import '../models/user_model.dart';
import '../widgets/avatar_widget.dart';
import '../config/app_colors.dart';
import '../config/app_typography.dart';
import '../services/call_notification_service.dart';
import '../services/database_service.dart';
import 'package:intl/intl.dart';

class ChatScreen extends StatefulWidget {
  final String chatId;
  const ChatScreen({super.key, required this.chatId});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _msgCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();
  bool _showEmoji = false;
  bool _isTyping = false;
  bool _isRecording = false;
  String? _editingMessageId;
  MessageModel? _replyToMessage;

  // Voice recording
  final Stopwatch _stopwatch = Stopwatch();
  Timer? _recordTimer;
  String _recordDurationStr = "0:00";
  final AudioRecorder _recorder = AudioRecorder();
  final AudioPlayer _voicePlayer = AudioPlayer();
  String? _recordPath;
  final Map<String, String> _voiceFileCache = {};
  String? _playingMessageId;
  Duration _playingPosition = Duration.zero;
  Duration _playingDuration = Duration.zero;

  // Partner data
  UserModel? _partner;
  String _partnerId = '';
  static const int _maxVoiceDurationMs = 20000;
  static const int _maxVoiceBytes = 200000;

  @override
  void initState() {
    super.initState();
    _loadPartnerInfo();
    _wireVoicePlayerStreams();
    _msgCtrl.addListener(() {
      // Show send button reactively
      setState(() {});
    });
  }

  @override
  void dispose() {
    // Clear typing status on leave
    final auth = context.read<AuthProvider>();
    context.read<ChatProvider>().setTyping(widget.chatId, auth.firebaseUser!.uid, false);
    _msgCtrl.dispose();
    _scrollCtrl.dispose();
    _recordTimer?.cancel();
    _stopwatch.stop();
    _voiceFileCache.clear();
    _recorder.dispose();
    _voicePlayer.dispose();
    super.dispose();
  }

  Future<void> _loadPartnerInfo() async {
    final auth = context.read<AuthProvider>();
    final myUid = auth.firebaseUser!.uid;

    // Parse partner UID from chatId (format: uid1_uid2, sorted)
    final parts = widget.chatId.split('_');
    _partnerId = parts.firstWhere((id) => id != myUid, orElse: () => parts.first);

    final partner = await DatabaseService().getUser(_partnerId);
    if (mounted && partner != null) {
      setState(() => _partner = partner);
    }
  }

  void _sendMessage() {
    if (_msgCtrl.text.trim().isEmpty) return;

    final auth = context.read<AuthProvider>();
    final chat = context.read<ChatProvider>();

    if (_editingMessageId != null) {
      // Edit existing message
      chat.editMessage(widget.chatId, _editingMessageId!, _msgCtrl.text.trim());
      _editingMessageId = null;
    } else {
      // Send new message
      final msg = MessageModel(
        id: '',
        senderId: auth.firebaseUser!.uid,
        text: _msgCtrl.text.trim(),
        type: _isOnlyEmoji(_msgCtrl.text.trim()) ? MessageType.emoji : MessageType.text,
        timestamp: DateTime.now(),
        replyToMessageId: _replyToMessage?.id,
        replyToText: _replyToMessage?.text,
        replyToSenderId: _replyToMessage?.senderId,
      );
      chat.sendMessage(widget.chatId, msg);
    }

    _msgCtrl.clear();
    _replyToMessage = null;
    _updateTyping(false);

    // Scroll to bottom
    Future.delayed(const Duration(milliseconds: 200), () {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent + 60,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _startRecording() async {
    if (!await _recorder.hasPermission()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Microphone permission required.')),
        );
      }
      return;
    }

    final tempDir = await getTemporaryDirectory();
    _recordPath =
        '${tempDir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
    await _recorder.start(
      const RecordConfig(encoder: AudioEncoder.aacLc, bitRate: 128000),
      path: _recordPath!,
    );

    setState(() {
      _isRecording = true;
      _stopwatch.reset();
      _stopwatch.start();
      _recordDurationStr = "0:00";
    });
    _recordTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      if (!mounted) return;
      setState(() {
        final sec = _stopwatch.elapsed.inSeconds;
        final min = sec ~/ 60;
        final remainingSec = sec % 60;
        _recordDurationStr = "$min:${remainingSec.toString().padLeft(2, '0')}";
      });
    });
  }

  Future<void> _stopRecording({required bool cancel}) async {
    if (!_isRecording) return;
    final auth = context.read<AuthProvider>();
    final chat = context.read<ChatProvider>();
    _recordTimer?.cancel();
    _stopwatch.stop();
    setState(() => _isRecording = false);
    final finalPath = await _recorder.stop();

    if (!cancel && _stopwatch.elapsedMilliseconds > 500 && finalPath != null) {
      final elapsedMs = _stopwatch.elapsedMilliseconds;
      if (elapsedMs > _maxVoiceDurationMs) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Voice clip too long. Keep it under 20 seconds.')),
          );
        }
        return;
      }

      final bytes = await File(finalPath).readAsBytes();
      if (bytes.length > _maxVoiceBytes) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Voice clip too large. Send a shorter clip.')),
          );
        }
        return;
      }

      final msg = MessageModel(
        id: '',
        senderId: auth.firebaseUser!.uid,
        text: 'Voice message',
        type: MessageType.voice,
        timestamp: DateTime.now(),
        voiceBase64: base64Encode(bytes),
        voiceMimeType: 'audio/mp4',
        voiceDurationMs: elapsedMs,
        voiceSizeBytes: bytes.length,
        replyToMessageId: _replyToMessage?.id,
        replyToText: _replyToMessage?.text,
        replyToSenderId: _replyToMessage?.senderId,
      );
      chat.sendMessage(widget.chatId, msg);
      _replyToMessage = null;
      
      Future.delayed(const Duration(milliseconds: 200), () {
        if (_scrollCtrl.hasClients) {
          _scrollCtrl.animateTo(
            _scrollCtrl.position.maxScrollExtent + 60,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      });
    }
  }

  void _wireVoicePlayerStreams() {
    _voicePlayer.onPositionChanged.listen((value) {
      if (!mounted) return;
      setState(() => _playingPosition = value);
    });
    _voicePlayer.onDurationChanged.listen((value) {
      if (!mounted) return;
      setState(() => _playingDuration = value);
    });
    _voicePlayer.onPlayerComplete.listen((_) {
      if (!mounted) return;
      setState(() {
        _playingMessageId = null;
        _playingPosition = Duration.zero;
      });
    });
  }

  bool _isOnlyEmoji(String text) {
    if (text.isEmpty) return false;
    final cleaned = text.replaceAll(RegExp(r'\s'), '');
    if (cleaned.isEmpty) return false;
    // Simple heuristic: if all characters are emoji (non-ASCII above a threshold)
    final runes = cleaned.runes.toList();
    return runes.every((r) => r > 0x1F000 || (r >= 0x2600 && r <= 0x27BF) || (r >= 0x2300 && r <= 0x23FF));
  }

  void _updateTyping(bool typing) {
    if (_isTyping == typing) return;
    _isTyping = typing;
    final auth = context.read<AuthProvider>();
    context.read<ChatProvider>().setTyping(widget.chatId, auth.firebaseUser!.uid, typing);
  }

  Future<void> _startAudioCall() async {
    if (_partner == null) return;
    final me = context.read<AuthProvider>().userModel;
    if (me == null) return;
    final callData = await DatabaseService().createDirectCall(
      caller: me,
      calleeUid: _partnerId,
      calleeName: _partner!.name,
      calleeAvatar: _partner!.avatarUrl,
      isVideo: false,
    );
    await CallNotificationService().startOutgoingCallkit(callData);
    if (!mounted) return;
    context.push('/audio-call', extra: {
      'callId': callData['callId'] as String,
      'matchId': callData['matchId'] as String,
      'channelName': callData['channelName'] as String,
      'partnerUid': _partnerId,
      'partnerName': _partner!.name,
      'partnerAvatar': _partner!.avatarUrl,
      'isOutgoing': true,
    });
  }

  Future<void> _startVideoCall() async {
    if (_partner == null) return;
    final me = context.read<AuthProvider>().userModel;
    if (me == null) return;
    final callData = await DatabaseService().createDirectCall(
      caller: me,
      calleeUid: _partnerId,
      calleeName: _partner!.name,
      calleeAvatar: _partner!.avatarUrl,
      isVideo: true,
    );
    await CallNotificationService().startOutgoingCallkit(callData);
    if (!mounted) return;
    context.push('/video-call', extra: {
      'callId': callData['callId'] as String,
      'matchId': callData['matchId'] as String,
      'channelName': callData['channelName'] as String,
      'partnerUid': _partnerId,
      'partnerName': _partner!.name,
      'partnerAvatar': _partner!.avatarUrl,
      'isOutgoing': true,
    });
  }

  void _showPartnerProfile() {
    if (_partner == null) return;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AvatarWidget(name: _partner!.name, avatarCode: _partner!.avatarUrl, radius: 50),
            const SizedBox(height: 16),
            Text(_partner!.name, style: AppTypography.headlineMedium),
            const SizedBox(height: 4),
            Text(_partner!.email, style: const TextStyle(color: AppColors.textSecondary)),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 10, height: 10,
                  decoration: BoxDecoration(
                    color: _partner!.isOnline ? AppColors.success : Colors.grey,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  _partner!.isOnline ? 'Online' : 'Offline',
                  style: TextStyle(
                    color: _partner!.isOnline ? AppColors.success : AppColors.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _profileAction(Icons.call_rounded, 'Audio Call', _startAudioCall),
                _profileAction(Icons.videocam_rounded, 'Video Call', _startVideoCall),
              ],
            ),
            SizedBox(height: MediaQuery.of(ctx).padding.bottom + 12),
          ],
        ),
      ),
    );
  }

  Widget _profileAction(IconData icon, String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: () {
        Navigator.pop(context);
        onTap();
      },
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: AppColors.primary, size: 26),
          ),
          const SizedBox(height: 8),
          Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.read<AuthProvider>();
    final chatProvider = context.watch<ChatProvider>();
    final myUid = auth.firebaseUser!.uid;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: GestureDetector(
          onTap: _showPartnerProfile,
          child: StreamBuilder<ChatModel?>(
            stream: chatProvider.getChatMeta(widget.chatId),
            builder: (context, snapshot) {
              final chat = snapshot.data;
              final isPartnerTyping = chat?.typingStatus[_partnerId] == true;

              return Row(
                children: [
                  Stack(
                    alignment: Alignment.bottomRight,
                    children: [
                      AvatarWidget(
                        name: _partner?.name ?? '...',
                        avatarCode: _partner?.avatarUrl ?? '',
                        radius: 18,
                      ),
                      if (_partner != null)
                        Container(
                          width: 10, height: 10,
                          decoration: BoxDecoration(
                            color: _partner!.isOnline ? AppColors.success : Colors.grey,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: Theme.of(context).appBarTheme.backgroundColor ?? Colors.white,
                              width: 1.5,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _partner?.name ?? 'Loading...',
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          isPartnerTyping
                              ? 'typing...'
                              : (_partner?.isOnline == true ? 'Online' : 'Offline'),
                          style: TextStyle(
                            fontSize: 12,
                            color: isPartnerTyping
                                ? AppColors.primary
                                : (_partner?.isOnline == true ? AppColors.success : AppColors.textSecondary),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.videocam_rounded),
            onPressed: _startVideoCall,
          ),
          IconButton(
            icon: const Icon(Icons.call_rounded),
            onPressed: _startAudioCall,
          ),
          PopupMenuButton<String>(
            onSelected: (val) {
              if (val == 'clear') {
                context.read<ChatProvider>().clearChat(widget.chatId);
              } else if (val == 'block') {
                context.read<ChatProvider>().blockUser(myUid, _partnerId);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('User blocked'), backgroundColor: AppColors.error),
                );
                context.pop();
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'clear', child: Text('Clear Chat')),
              const PopupMenuItem(
                value: 'block',
                child: Text('Block User', style: TextStyle(color: AppColors.error)),
              ),
            ],
          ),
        ],
      ),

      body: Column(
        children: [
          // Edit mode banner
          if (_editingMessageId != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: AppColors.primary.withValues(alpha: 0.1),
              child: Row(
                children: [
                  const Icon(Icons.edit_rounded, size: 18, color: AppColors.primary),
                  const SizedBox(width: 8),
                  const Expanded(child: Text('Editing message', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w600))),
                  IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () {
                      setState(() {
                        _editingMessageId = null;
                        _msgCtrl.clear();
                      });
                    },
                  ),
                ],
              ),
            ),

          // Messages
          Expanded(
            child: StreamBuilder<List<MessageModel>>(
              stream: chatProvider.getMessages(widget.chatId),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator(color: AppColors.primary));
                }

                final messages = snapshot.data!;
                unawaited(chatProvider.markDelivered(widget.chatId));
                unawaited(chatProvider.markSeen(widget.chatId));

                if (messages.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.waving_hand_rounded, size: 48, color: AppColors.primary.withValues(alpha: 0.2)),
                        const SizedBox(height: 16),
                        Text('Say hello! 👋', style: AppTypography.headlineSmall),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  controller: _scrollCtrl,
                  padding: const EdgeInsets.all(12),
                  itemCount: messages.length + 1, // +1 for typing indicator
                  itemBuilder: (context, index) {
                    // Typing indicator at the end
                    if (index == messages.length) {
                      return StreamBuilder<ChatModel?>(
                        stream: chatProvider.getChatMeta(widget.chatId),
                        builder: (context, metaSnap) {
                          final isPartnerTyping = metaSnap.data?.typingStatus[_partnerId] == true;
                          if (!isPartnerTyping) return const SizedBox.shrink();

                          return Align(
                            alignment: Alignment.centerLeft,
                            child: Container(
                              margin: const EdgeInsets.symmetric(vertical: 4),
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                              decoration: BoxDecoration(
                                color: Theme.of(context).brightness == Brightness.dark
                                    ? const Color(0xFF2A2A2A)
                                    : Colors.grey[200],
                                borderRadius: const BorderRadius.only(
                                  topLeft: Radius.circular(16),
                                  topRight: Radius.circular(16),
                                  bottomRight: Radius.circular(16),
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  _buildTypingDots(),
                                ],
                              ),
                            ),
                          );
                        },
                      );
                    }

                    final msg = messages[index];
                    final isMe = msg.senderId == myUid;
                    return _buildMessageBubble(msg, isMe);
                  },
                );
              },
            ),
          ),

          // Emoji picker
          if (_showEmoji)
            SizedBox(
              height: 250,
              child: EmojiPicker(
                onEmojiSelected: (category, emoji) {
                  _msgCtrl.text += emoji.emoji;
                  _msgCtrl.selection = TextSelection.fromPosition(
                    TextPosition(offset: _msgCtrl.text.length),
                  );
                },
                config: const Config(
                  emojiViewConfig: EmojiViewConfig(
                    columns: 7,
                    emojiSizeMax: 32,
                  ),
                ),
              ),
            ),

          // Input area
          _buildInputArea(),
        ],
      ),
    );
  }

  Widget _buildTypingDots() {
    return SizedBox(
      width: 40,
      height: 20,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(3, (i) {
          return TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.0, end: 1.0),
            duration: Duration(milliseconds: 600 + (i * 200)),
            builder: (context, value, child) {
              return Container(
                margin: const EdgeInsets.symmetric(horizontal: 2),
                width: 6, height: 6,
                decoration: BoxDecoration(
                  color: AppColors.textSecondary.withValues(alpha: 0.4 + 0.6 * value),
                  shape: BoxShape.circle,
                ),
              );
            },
          );
        }),
      ),
    );
  }

  Widget _buildMessageBubble(MessageModel msg, bool isMe) {
    final isEmoji = msg.type == MessageType.emoji;
    final isCallEvent = msg.type == MessageType.callEvent;
    final timeStr = DateFormat.jm().format(msg.timestamp);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Call event display
    if (isCallEvent) {
      return Center(
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 8),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: isDark ? Colors.white10 : Colors.grey[200],
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            msg.text,
            style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
          ),
        ),
      );
    }

    if (msg.type == MessageType.voice) {
      final duration = msg.voiceDurationMs != null
          ? _formatMillis(msg.voiceDurationMs!)
          : '0:00';
      final isPlaying = _playingMessageId == msg.id;
      final total = _playingDuration.inMilliseconds == 0
          ? (msg.voiceDurationMs ?? 1)
          : _playingDuration.inMilliseconds;
      final progress = (_playingPosition.inMilliseconds / total).clamp(0.0, 1.0);
      return Align(
        alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
        child: GestureDetector(
          onLongPress: () => _showMessageOptions(msg, isMe),
          child: Container(
            margin: const EdgeInsets.only(bottom: 4),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: isMe ? AppColors.primary : (isDark ? const Color(0xFF2A2A2A) : Colors.grey[100]),
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(18),
                topRight: const Radius.circular(18),
                bottomLeft: Radius.circular(isMe ? 18 : 4),
                bottomRight: Radius.circular(isMe ? 4 : 18),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.mic_rounded,
                  color: isMe ? Colors.white : AppColors.primary,
                  size: 18,
                ),
                const SizedBox(width: 6),
                IconButton(
                  icon: Icon(
                    isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    color: isMe ? Colors.white : AppColors.primary,
                    size: 28,
                  ),
                  onPressed: () async {
                    if (msg.voiceBase64 == null || msg.voiceBase64!.isEmpty) return;
                    if (isPlaying) {
                      await _voicePlayer.pause();
                      setState(() => _playingMessageId = null);
                    } else {
                      final cached = _voiceFileCache[msg.id];
                      final path = cached ?? await _decodeVoiceToTempPath(msg);
                      if (path == null) return;
                      _voiceFileCache[msg.id] = path;
                      await _voicePlayer.play(DeviceFileSource(path));
                      setState(() => _playingMessageId = msg.id);
                    }
                  },
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 42,
                  height: 18,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: List.generate(5, (index) {
                      final isActive = isPlaying && index.isEven;
                      final height = isActive ? 16.0 - (index * 1.5) : 8.0;
                      return AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        width: 4,
                        height: height,
                        decoration: BoxDecoration(
                          color: isMe
                              ? Colors.white.withValues(alpha: 0.85)
                              : AppColors.primary.withValues(alpha: 0.8),
                          borderRadius: BorderRadius.circular(999),
                        ),
                      );
                    }),
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  width: 90,
                  child: Slider(
                    value: progress,
                    onChanged: (value) async {
                      final target = Duration(
                        milliseconds: (total * value).round(),
                      );
                      await _voicePlayer.seek(target);
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  duration,
                  style: TextStyle(color: isMe ? Colors.white : (isDark ? Colors.white : Colors.black87)),
                ),
                if (isMe) ...[
                  const SizedBox(width: 6),
                  _buildStatusIcon(msg.status, isMe: isMe),
                ],
              ],
            ),
          ),
        ),
      );
    }

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onLongPress: () => _showMessageOptions(msg, isMe),
        child: Container(
          margin: const EdgeInsets.only(bottom: 4),
          constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
          child: Column(
            crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              Container(
                padding: isEmoji
                    ? const EdgeInsets.all(4)
                    : const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: isEmoji
                    ? null
                    : BoxDecoration(
                        color: isMe
                            ? AppColors.primary
                            : (isDark ? const Color(0xFF2A2A2A) : Colors.grey[100]),
                        borderRadius: BorderRadius.only(
                          topLeft: const Radius.circular(18),
                          topRight: const Radius.circular(18),
                          bottomLeft: Radius.circular(isMe ? 18 : 4),
                          bottomRight: Radius.circular(isMe ? 4 : 18),
                        ),
                      ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    if ((msg.replyToText ?? '').isNotEmpty && !isEmoji)
                      Container(
                        margin: const EdgeInsets.only(bottom: 6),
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                        decoration: BoxDecoration(
                          color: isMe
                              ? Colors.white.withValues(alpha: 0.16)
                              : AppColors.primary.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          msg.replyToText!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: isMe ? Colors.white70 : AppColors.textSecondary,
                          ),
                        ),
                      ),
                    Text(
                      msg.text,
                      style: TextStyle(
                        color: isEmoji
                            ? null
                            : (isMe ? Colors.white : (isDark ? Colors.white : Colors.black87)),
                        fontSize: isEmoji ? 42 : 15,
                        height: 1.3,
                      ),
                    ),
                    if (!isEmoji) ...[
                      const SizedBox(height: 2),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (msg.isEdited)
                            Padding(
                              padding: const EdgeInsets.only(right: 4),
                              child: Text(
                                'edited',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontStyle: FontStyle.italic,
                                  color: isMe ? Colors.white60 : AppColors.textSecondary,
                                ),
                              ),
                            ),
                          Text(
                            timeStr,
                            style: TextStyle(
                              fontSize: 10,
                              color: isMe ? Colors.white60 : AppColors.textSecondary,
                            ),
                          ),
                          if (isMe) ...[
                            const SizedBox(width: 4),
                            _buildStatusIcon(msg.status, isMe: isMe),
                          ],
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showMessageOptions(MessageModel msg, bool isMe) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Handle bar
                Container(
                  width: 40, height: 4, margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(color: Colors.grey[400], borderRadius: BorderRadius.circular(2)),
                ),
                if (isMe && msg.type == MessageType.text)
                  ListTile(
                    leading: const Icon(Icons.edit_rounded, color: AppColors.primary),
                    title: const Text('Edit Message'),
                    onTap: () {
                      Navigator.pop(ctx);
                      setState(() {
                        _editingMessageId = msg.id;
                        _msgCtrl.text = msg.text;
                      });
                    },
                  ),
                ListTile(
                  leading: const Icon(Icons.reply_rounded, color: AppColors.primary),
                  title: const Text('Reply'),
                  onTap: () {
                    Navigator.pop(ctx);
                    setState(() => _replyToMessage = msg);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.delete_outline_rounded, color: Colors.orange),
                  title: const Text('Delete for Me'),
                  onTap: () {
                    context.read<ChatProvider>().deleteMessage(widget.chatId, msg.id, everyone: false);
                    Navigator.pop(ctx);
                  },
                ),
                if (isMe)
                  ListTile(
                    leading: const Icon(Icons.delete_forever_rounded, color: AppColors.error),
                    title: const Text('Delete for Everyone'),
                    onTap: () {
                      context.read<ChatProvider>().deleteMessage(widget.chatId, msg.id, everyone: true);
                      Navigator.pop(ctx);
                    },
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildInputArea() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final hasText = _msgCtrl.text.trim().isNotEmpty;

    return Container(
      padding: EdgeInsets.fromLTRB(8, 8, 8, MediaQuery.of(context).padding.bottom + 8),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, -2)),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_replyToMessage != null)
            Container(
              margin: const EdgeInsets.only(bottom: 8, left: 46, right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF242424) : Colors.grey[200],
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Replying: ${_replyToMessage!.text}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () => setState(() => _replyToMessage = null),
                    child: const Icon(Icons.close_rounded, size: 16, color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
          Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // Emoji toggle
          IconButton(
            icon: Icon(
              _showEmoji ? Icons.keyboard_rounded : Icons.emoji_emotions_outlined,
              color: AppColors.textSecondary,
            ),
            onPressed: () => setState(() => _showEmoji = !_showEmoji),
          ),

          // Text field
          Expanded(
            child: Container(
              constraints: const BoxConstraints(maxHeight: 120),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E1E1E) : Colors.grey[100],
                borderRadius: BorderRadius.circular(24),
              ),
              child: _isRecording
                  ? _buildRecordingUI()
                  : TextField(
                      controller: _msgCtrl,
                      maxLines: 5,
                      minLines: 1,
                      onChanged: (val) => _updateTyping(val.isNotEmpty),
                      decoration: const InputDecoration(
                        hintText: 'Type a message...',
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(vertical: 10),
                      ),
                    ),
            ),
          ),

          const SizedBox(width: 6),

          // Send or Mic button
          hasText || _editingMessageId != null
              ? GestureDetector(
                  onTap: _sendMessage,
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: const BoxDecoration(
                      color: AppColors.primary,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.send_rounded, color: Colors.white, size: 22),
                  ),
                )
              : GestureDetector(
                  onLongPressStart: (_) => _startRecording(),
                  onLongPressEnd: (_) => _stopRecording(cancel: false),
                  onLongPressMoveUpdate: (details) {
                    // Cancel if drag too far left
                    if (details.localOffsetFromOrigin.dx < -50) {
                      _stopRecording(cancel: true);
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: _isRecording ? AppColors.error : AppColors.primary,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      _isRecording ? Icons.stop_rounded : Icons.mic_rounded,
                      color: Colors.white,
                      size: 22,
                    ),
                  ),
                ),
        ],
      ),
        ],
      ),
    );
  }

  Widget _buildRecordingUI() {
    return Row(
      children: [
        Container(
          width: 10, height: 10,
          decoration: const BoxDecoration(color: AppColors.error, shape: BoxShape.circle),
        ),
        const SizedBox(width: 10),
        Text('Recording... $_recordDurationStr', style: const TextStyle(color: AppColors.error, fontWeight: FontWeight.bold, fontSize: 14)),
        const Spacer(),
        const Text('< Slide to cancel', style: TextStyle(color: Colors.grey, fontSize: 12)),
      ],
    );
  }

  String _formatMillis(int milliseconds) {
    final totalSeconds = (milliseconds / 1000).round();
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  Future<String?> _decodeVoiceToTempPath(MessageModel msg) async {
    try {
      if (msg.voiceBase64 == null) return null;
      final tempDir = await getTemporaryDirectory();
      final path = '${tempDir.path}/voice_${msg.id}.m4a';
      final bytes = base64Decode(msg.voiceBase64!);
      await File(path).writeAsBytes(bytes, flush: true);
      return path;
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to play voice message.')),
        );
      }
      return null;
    }
  }

  Widget _buildStatusIcon(String status, {required bool isMe}) {
    final color = isMe ? Colors.white60 : AppColors.textSecondary;
    switch (status) {
      case 'seen':
        return const Icon(Icons.done_all_rounded, size: 14, color: Colors.lightBlueAccent);
      case 'delivered':
        return Icon(Icons.done_all_rounded, size: 14, color: color);
      case 'sent':
      default:
        return Icon(Icons.done_rounded, size: 14, color: color);
    }
  }
}
