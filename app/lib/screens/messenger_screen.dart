import 'package:flutter/material.dart';
import 'dart:async';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_database/firebase_database.dart';
import '../providers/auth_provider.dart';
import '../providers/chat_provider.dart';
import '../widgets/avatar_widget.dart';
import '../config/app_colors.dart';
import '../config/app_typography.dart';
import '../models/user_model.dart';
import '../services/database_service.dart';
import '../services/chat_service.dart';
import 'package:intl/intl.dart';

class MessengerScreen extends StatefulWidget {
  const MessengerScreen({super.key});

  @override
  State<MessengerScreen> createState() => _MessengerScreenState();
}

class _MessengerScreenState extends State<MessengerScreen> {
  // Cache partner names so we don't re-fetch every build
  final Map<String, UserModel> _userCache = {};
  final DatabaseService _db = DatabaseService();

  @override
  void initState() {
    super.initState();
    final auth = context.read<AuthProvider>();
    if (auth.firebaseUser != null) {
      context.read<ChatProvider>().init(auth.firebaseUser!.uid);
    }
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<UserModel?> _getUser(String uid) async {
    if (_userCache.containsKey(uid)) return _userCache[uid];
    final user = await _db.getUser(uid);
    if (user != null) _userCache[uid] = user;
    return user;
  }

  @override
  Widget build(BuildContext context) {
    final chatProvider = context.watch<ChatProvider>();
    final auth = context.read<AuthProvider>();
    final myUid = auth.firebaseUser?.uid ?? '';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Messenger', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 22)),
        actions: [
          IconButton(
            icon: const Icon(Icons.search_rounded),
            onPressed: () {},
          ),
        ],
      ),
      body: chatProvider.chats.isEmpty
          ? _buildEmptyState()
          : ListView.separated(
              itemCount: chatProvider.chats.length,
              separatorBuilder: (context, index) => Divider(indent: 80, height: 1, color: Colors.grey.withValues(alpha: 0.15)),
              itemBuilder: (context, index) {
                final chat = chatProvider.chats[index];
                final partnerId = chat.participants.firstWhere(
                  (id) => id != myUid,
                  orElse: () => '',
                );

                return FutureBuilder<UserModel?>(
                  future: _getUser(partnerId),
                  builder: (context, snap) {
                      final partner = snap.data;
                    final partnerName = partner?.name ?? 'Loading...';
                    final partnerAvatar = partner?.avatarUrl ?? '';
                    final isBlocked = auth.userModel?.blockedUsers.contains(partnerId) ?? false;

                    return GestureDetector(
                      onLongPress: () => _showDeleteChatDialog(chat.chatId, partnerName),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                        tileColor: isBlocked ? AppColors.error.withValues(alpha: 0.1) : null,
                        leading: Stack(
                          children: [
                            Container(
                              decoration: isBlocked
                                  ? BoxDecoration(
                                      shape: BoxShape.circle,
                                      border: Border.all(color: AppColors.error, width: 2),
                                    )
                                  : null,
                              child: AvatarWidget(name: partnerName, avatarCode: partnerAvatar, radius: 28),
                            ),
                            // Online indicator
                            if (partner != null && partner.isOnline && !isBlocked)
                              Positioned(
                                right: 0,
                                bottom: 0,
                                child: Container(
                                  width: 14,
                                  height: 14,
                                  decoration: BoxDecoration(
                                    color: AppColors.success,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: Theme.of(context).scaffoldBackgroundColor,
                                      width: 2,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                        title: Text(
                          partnerName + (isBlocked ? ' (Blocked)' : ''),
                          style: TextStyle(
                            fontWeight: FontWeight.bold, 
                            fontSize: 16,
                            color: isBlocked ? AppColors.error : null,
                          ),
                        ),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            isBlocked ? 'Tap to view or unblock.' : chat.lastMessage,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: isBlocked ? AppColors.error.withValues(alpha: 0.8) : AppColors.textSecondary, fontSize: 14),
                          ),
                        ),
                        trailing: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              _formatTime(chat.lastMessageTime),
                              style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                            ),
                            const SizedBox(height: 6),
                            if (chat.unreadCounts[myUid] != null && chat.unreadCounts[myUid]! > 0 && !isBlocked)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                decoration: BoxDecoration(
                                  color: AppColors.primary,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  '${chat.unreadCounts[myUid]}',
                                  style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                                ),
                              ),
                          ],
                        ),
                        onTap: () {
                          if (isBlocked) {
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Cannot open chat with a blocked user.')));
                            return;
                          }
                          context.push('/chat/${chat.chatId}');
                        },
                      ),
                    );
                  },
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showNewChatPicker(),
        backgroundColor: AppColors.primary,
        child: const Icon(Icons.add_rounded, color: Colors.white, size: 28),
      ),
    );
  }

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final diff = now.difference(time);
    if (diff.inDays == 0) return DateFormat.jm().format(time);
    if (diff.inDays == 1) return 'Yesterday';
    if (diff.inDays < 7) return DateFormat.E().format(time);
    return DateFormat.MMMd().format(time);
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.chat_bubble_outline_rounded, size: 80, color: AppColors.primary.withValues(alpha: 0.1)),
          const SizedBox(height: 24),
          Text('No messages yet', style: AppTypography.headlineSmall),
          const SizedBox(height: 8),
          Text(
            'Tap + to start chatting\nwith your friends.',
            textAlign: TextAlign.center,
            style: AppTypography.bodyMedium.copyWith(color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }

  void _showDeleteChatDialog(String chatId, String partnerName) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Clear Chat?', style: TextStyle(fontWeight: FontWeight.bold)),
        content: const Text('This will delete all messages in this chat from this device only. This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: AppColors.textSecondary)),
          ),
          TextButton(
            onPressed: () {
              context.read<ChatProvider>().clearChat(chatId);
              Navigator.pop(ctx);
            },
            child: const Text('Clear', style: TextStyle(color: AppColors.error, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  /// Show a bottom sheet with friend list to start a new chat.
  void _showNewChatPicker() async {
    final auth = context.read<AuthProvider>();
    final myUid = auth.firebaseUser!.uid;
    final chatService = ChatService();

    // Fetch my friends list from DB
    final myData = await _db.getUser(myUid);
    if (myData == null || myData.friends.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('You have no friends yet. Add friends first!')),
        );
      }
      return;
    }

    // Fetch all friend user data
    final List<UserModel> friends = [];
    for (final fid in myData.friends) {
      final u = await _getUser(fid);
      if (u != null) friends.add(u);
    }

    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        return Container(
          height: MediaQuery.of(ctx).size.height * 0.7,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40, height: 4,
                  decoration: BoxDecoration(color: Colors.grey[400], borderRadius: BorderRadius.circular(2)),
                ),
              ),
              const SizedBox(height: 16),
              Text('New Chat', style: AppTypography.headlineMedium),
              const SizedBox(height: 4),
              const Text('Choose a friend to start chatting', style: TextStyle(color: AppColors.textSecondary)),
              const SizedBox(height: 16),
              Expanded(
                child: friends.isEmpty
                    ? const Center(child: Text('No friends found.'))
                    : ListView.separated(
                        itemCount: friends.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final friend = friends[index];
                          return ListTile(
                            contentPadding: const EdgeInsets.symmetric(vertical: 4),
                            leading: Stack(
                              children: [
                                AvatarWidget(name: friend.name, avatarCode: friend.avatarUrl, radius: 22),
                                if (friend.isOnline)
                                  Positioned(
                                    right: 0, bottom: 0,
                                    child: Container(
                                      width: 12, height: 12,
                                      decoration: BoxDecoration(
                                        color: AppColors.success, shape: BoxShape.circle,
                                        border: Border.all(color: isDark ? const Color(0xFF1E1E1E) : Colors.white, width: 2),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            title: Text(friend.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                            subtitle: Text(friend.isOnline ? 'Online' : 'Offline',
                              style: TextStyle(color: friend.isOnline ? AppColors.success : AppColors.textSecondary, fontSize: 12),
                            ),
                            onTap: () {
                              Navigator.pop(ctx);
                              final chatId = chatService.getChatId(myUid, friend.uid);
                              // Ensure chat meta exists
                              FirebaseDatabase.instance.ref('chats_meta').child(chatId).update({
                                'participants': [myUid, friend.uid],
                                'lastMessage': '',
                                'lastMessageTime': DateTime.now().millisecondsSinceEpoch,
                              });
                              context.push('/chat/$chatId');
                            },
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}
