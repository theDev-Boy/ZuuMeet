import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../config/app_colors.dart';
import '../config/app_typography.dart';
import '../providers/auth_provider.dart';
import '../providers/theme_provider.dart';
import '../widgets/avatar_widget.dart';
import '../widgets/custom_button.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  Future<void> _showPasswordResetSheet(
    BuildContext context,
    String email,
  ) async {
    final controller = TextEditingController(text: email);
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            20,
            20,
            MediaQuery.of(ctx).viewInsets.bottom + 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Reset Password',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'Type your logged-in email to receive the reset link.',
                style: TextStyle(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: controller,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  hintText: 'Email address',
                ),
              ),
              const SizedBox(height: 16),
              CustomButton(
                text: 'Send Reset Email',
                onPressed: () async {
                  if (controller.text.trim() != email.trim()) {
                    ScaffoldMessenger.of(ctx).showSnackBar(
                      const SnackBar(
                        content: Text('Please enter your current account email.'),
                        backgroundColor: AppColors.error,
                      ),
                    );
                    return;
                  }
                  final auth = context.read<AuthProvider>();
                  final success = await auth.sendPasswordReset(
                    controller.text.trim(),
                  );
                  if (!ctx.mounted) {
                    return;
                  }
                  if (!success) {
                    ScaffoldMessenger.of(ctx).showSnackBar(
                      SnackBar(
                        content: Text(auth.error ?? 'Reset email failed.'),
                        backgroundColor: AppColors.error,
                      ),
                    );
                    return;
                  }
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Reset email sent. Check your inbox.'),
                    ),
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _logout(BuildContext context) async {
    final auth = context.read<AuthProvider>();
    final success = await auth.signOut();
    if (!context.mounted) {
      return;
    }
    if (!success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(auth.error ?? 'Logout failed.'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }
    context.go('/auth');
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final user = auth.userModel;
    final theme = context.watch<ThemeProvider>();
    if (user == null) {
      return const Scaffold(body: SizedBox.shrink());
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              children: [
                AvatarWidget(
                  name: user.name,
                  avatarCode: '',
                  showFrame: false,
                  radius: 28,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(user.name, style: AppTypography.headlineSmall),
                      const SizedBox(height: 4),
                      Text(
                        user.displayId,
                        style: const TextStyle(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        user.age.isEmpty ? 'Age not set' : 'Age ${user.age}',
                        style: const TextStyle(color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => context.push('/edit-profile'),
                  icon: const Icon(Icons.edit_rounded),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Text('Personal Data', style: AppTypography.headlineSmall),
          const SizedBox(height: 12),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Email'),
            subtitle: Text(user.email),
            leading: const Icon(Icons.email_outlined),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Reset Password'),
            subtitle: const Text('Send a Firebase reset email'),
            leading: const Icon(Icons.lock_reset_rounded),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => _showPasswordResetSheet(context, user.email),
          ),
          const Divider(height: 32),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Dark Mode'),
            leading: const Icon(Icons.dark_mode_outlined),
            trailing: Switch(
              value: theme.isDarkMode,
              onChanged: theme.toggleTheme,
            ),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Blocked Users'),
            subtitle: Text('${user.blockedUsers.length} users'),
            leading: const Icon(Icons.block_rounded, color: AppColors.error),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => context.push('/blocked-users'),
          ),
          const SizedBox(height: 32),
          CustomButton(
            text: 'Log Out',
            icon: Icons.logout,
            backgroundColor: AppColors.backgroundSecondary,
            textColor: AppColors.error,
            onPressed: () => _logout(context),
          ),
        ],
      ),
    );
  }
}
