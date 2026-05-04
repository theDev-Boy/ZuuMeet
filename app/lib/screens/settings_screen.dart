import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../config/app_colors.dart';
import '../config/app_dimensions.dart';
import '../config/app_typography.dart';
import '../providers/auth_provider.dart';
import '../providers/theme_provider.dart';
import '../widgets/custom_button.dart';
import '../widgets/avatar_widget.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _nameCtrl = TextEditingController();
  String _gender = 'Male';
  bool _isEditing = false;

  @override
  void initState() {
    super.initState();
    final user = context.read<AuthProvider>().userModel;
    if (user != null) {
      _nameCtrl.text = user.name;
      _gender = user.gender.isNotEmpty ? user.gender : 'Male';
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  void _showLogoutDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirm Logout', style: TextStyle(fontWeight: FontWeight.bold)),
        content: const Text('Are you sure you want to log out of Zuumeet?'),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppDimensions.radiusL)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () {
              Navigator.pop(ctx); // close dialog
              context.read<AuthProvider>().signOut();
              context.go('/auth'); // redirect to auth
            },
            child: const Text('Logout'),
          ),
        ],
      ),
    );
  }

  Future<void> _saveChanges() async {
    final auth = context.read<AuthProvider>();
    await auth.updateProfile(
      name: _nameCtrl.text.trim(),
      gender: _gender,
    );
    setState(() => _isEditing = false);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile updated successfully!')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final user = auth.userModel;
    final themeProv = context.watch<ThemeProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new),
          onPressed: () => context.pop(),
        ),
        actions: [
          if (user != null)
            TextButton(
              onPressed: () {
                if (_isEditing) {
                  _saveChanges();
                } else {
                  setState(() => _isEditing = true);
                }
              },
              child: Text(_isEditing ? 'SAVE' : 'EDIT', style: const TextStyle(fontWeight: FontWeight.bold)),
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Profile Card
            if (user != null)
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                  borderRadius: BorderRadius.circular(AppDimensions.radiusXL),
                  boxShadow: [
                    if (!isDark)
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.05),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                  ],
                ),
                child: Column(
                  children: [
                    AvatarWidget(
                      name: user.name,
                      avatarCode: '', // Force empty so it shows initials
                      radius: 40,
                      showFrame: false,
                    ),
                    const SizedBox(height: 16),
                    if (_isEditing) ...[
                       TextField(
                         controller: _nameCtrl,
                         decoration: const InputDecoration(labelText: 'Name', border: OutlineInputBorder()),
                       ),
                       const SizedBox(height: 16),
                       Row(
                         children: [
                           const Text('Gender: ', style: TextStyle(fontWeight: FontWeight.bold)),
                           const SizedBox(width: 8),
                           DropdownButton<String>(
                             value: _gender,
                             items: ['Male', 'Female', 'Other'].map((String value) {
                               return DropdownMenuItem<String>(value: value, child: Text(value));
                             }).toList(),
                             onChanged: (v) {
                               if (v != null) setState(() => _gender = v);
                             },
                           ),
                         ],
                       ),
                    ] else ...[
                      Text(user.name, style: AppTypography.headlineMedium),
                      const SizedBox(height: 4),
                      Text(user.gender, style: AppTypography.bodyMedium.copyWith(color: AppColors.textSecondary)),
                      const SizedBox(height: 12),
                    ],
                    
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        'UID: ${user.displayId.isNotEmpty ? user.displayId : 'N/A'}',
                        style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(user.flagEmoji, style: const TextStyle(fontSize: 18)),
                        const SizedBox(width: 8),
                        Text(user.country, style: const TextStyle(fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ],
                ),
              ),
            
            const SizedBox(height: 32),
            Text('App Preferences', style: AppTypography.headlineSmall),
            const SizedBox(height: 16),
            
            // Dark Mode Toggle
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(isDark ? Icons.dark_mode : Icons.light_mode, color: AppColors.primary),
              ),
              title: const Text('Dark Mode', style: TextStyle(fontWeight: FontWeight.w600)),
              trailing: Switch(
                value: themeProv.isDarkMode,
                activeThumbColor: AppColors.primary,
                onChanged: (val) => themeProv.toggleTheme(val),
              ),
            ),
            const Divider(height: 32),
            
            // Blocked Users
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.error.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.block_rounded, color: AppColors.error),
              ),
              title: const Text('Blocked Users', style: TextStyle(fontWeight: FontWeight.w600)),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => context.push('/blocked-users'),
            ),
            const Divider(height: 32),
            
            // About
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.blue.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.info_outline, color: Colors.blue),
              ),
              title: const Text('About Zuumeet', style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: const Text('Version 1.0.0'),
            ),
            
            const SizedBox(height: 48),
            
            // Logout Button
            CustomButton(
              text: 'Log Out',
              icon: Icons.logout,
              backgroundColor: AppColors.backgroundSecondary,
              textColor: AppColors.error,
              onPressed: () => _showLogoutDialog(context),
            ),
          ],
        ),
      ),
    );
  }
}
