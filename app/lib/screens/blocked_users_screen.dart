import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../config/app_colors.dart';
import '../providers/auth_provider.dart';
import '../services/database_service.dart';
import '../models/user_model.dart';
import '../widgets/avatar_widget.dart';

class BlockedUsersScreen extends StatefulWidget {
  const BlockedUsersScreen({super.key});

  @override
  State<BlockedUsersScreen> createState() => _BlockedUsersScreenState();
}

class _BlockedUsersScreenState extends State<BlockedUsersScreen> {
  final DatabaseService _db = DatabaseService();

  Future<void> _unblockUser(String blockedUid) async {
    final auth = context.read<AuthProvider>();
    if (auth.firebaseUser == null) return;
    
    // Show confirmation
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Unblock User?', style: TextStyle(fontWeight: FontWeight.bold)),
        content: const Text('Are you sure you want to unblock this user? They will be able to message and call you again.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: AppColors.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Unblock', style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.primary)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _db.unblockUser(auth.firebaseUser!.uid, blockedUid);
      // Refresh user profile
      await auth.refreshUser();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('User unblocked')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final blockedIds = auth.userModel?.blockedUsers ?? [];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Blocked Users'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new),
          onPressed: () => context.pop(),
        ),
      ),
      body: blockedIds.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.block_rounded, size: 64, color: AppColors.textSecondary.withValues(alpha: 0.3)),
                  const SizedBox(height: 16),
                  const Text('No blocked users', style: TextStyle(fontSize: 18, color: AppColors.textSecondary)),
                ],
              ),
            )
          : ListView.separated(
              itemCount: blockedIds.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final blockedUid = blockedIds[index];
                return FutureBuilder<UserModel?>(
                  future: _db.getUser(blockedUid),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) {
                      return ListTile(
                        leading: CircleAvatar(backgroundColor: Colors.grey[300], radius: 24),
                        title: const Text('Loading...'),
                      );
                    }
                    final user = snapshot.data!;
                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      leading: AvatarWidget(name: user.name, avatarCode: user.avatarUrl, radius: 24),
                      title: Text(user.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text(user.displayId.isNotEmpty ? 'ID: ${user.displayId}' : 'User'),
                      trailing: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          foregroundColor: AppColors.primary,
                          elevation: 0,
                          side: const BorderSide(color: AppColors.primary),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                        onPressed: () => _unblockUser(blockedUid),
                        child: const Text('Unblock', style: TextStyle(fontWeight: FontWeight.w600)),
                      ),
                    );
                  },
                );
              },
            ),
    );
  }
}
