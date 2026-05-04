import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../config/app_colors.dart';
import '../config/app_dimensions.dart';
import '../config/app_typography.dart';
import '../providers/auth_provider.dart';
import '../providers/call_provider.dart';
import '../services/permission_service.dart';
import '../widgets/custom_button.dart';
import 'friends_screen.dart';
import 'history_screen.dart';

import 'messenger_screen.dart';
import '../widgets/avatar_widget.dart';
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;

  Future<void> _onStartChatting(BuildContext context) async {
    final permissionService = PermissionService();
    final hasPermissions = await permissionService.requestCameraAndMic();

    if (hasPermissions) {
      if (context.mounted) {
        final callProvider = context.read<CallProvider>();
        // Return to active call
        if (callProvider.state != CallState.idle && callProvider.state != CallState.ended) {
          context.go('/call');
          return;
        }

        final currentUser = context.read<AuthProvider>().userModel;
        if (currentUser != null) {
          callProvider.startSearching(currentUser);
          context.go('/call');
        }
      }
    } else {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Camera & Microphone permissions are required'),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppDimensions.radiusM)),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: Text('Zuumeet', style: AppTypography.headlineMedium.copyWith(color: AppColors.primary)),
        centerTitle: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_rounded),
            tooltip: 'Settings',
            onPressed: () => context.push('/settings'),
          ),
        ],
      ),
      body: IndexedStack(
        index: _currentIndex,
        children: [
          _buildHomeTab(context),
          const MessengerScreen(),
          const FriendsScreen(),
          const HistoryScreen(),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        selectedItemColor: AppColors.primary,
        unselectedItemColor: AppColors.textSecondary,
        backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home_rounded), label: 'Home'),
          BottomNavigationBarItem(icon: Icon(Icons.message_rounded), label: 'Messenger'),
          BottomNavigationBarItem(icon: Icon(Icons.group_rounded), label: 'Friends'),
          BottomNavigationBarItem(icon: Icon(Icons.history_rounded), label: 'History'),
        ],
      ),
    );
  }

  Widget _buildHomeTab(BuildContext context) {
    final user = context.watch<AuthProvider>().userModel;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final screenW = MediaQuery.sizeOf(context).width;

    return SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: EdgeInsets.symmetric(
              horizontal: constraints.maxWidth > 500 ? constraints.maxWidth * 0.12 : 20,
              vertical: 16,
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight - 32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (user != null)
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                        borderRadius: BorderRadius.circular(AppDimensions.radiusXL),
                        boxShadow: [
                          if (!isDark)
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.04),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                        ],
                      ),
                      child: Row(
                        children: [
                          AvatarWidget(
                            name: user.name,
                            avatarCode: user.avatarUrl,
                            radius: screenW < 360 ? 22 : 28,
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  user.name,
                                  style: AppTypography.headlineSmall.copyWith(fontSize: screenW < 360 ? 15 : 18),
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 2),
                                Row(
                                  children: [
                                    if (user.flagEmoji.isNotEmpty) ...[
                                      Text(user.flagEmoji, style: const TextStyle(fontSize: 16)),
                                      const SizedBox(width: 6),
                                    ],
                                    Expanded(
                                      child: Text(
                                        user.country.isNotEmpty ? user.country : 'Unknown Location',
                                        style: AppTypography.caption,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: AppColors.success.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(AppDimensions.radiusS),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(width: 8, height: 8, decoration: const BoxDecoration(color: AppColors.success, shape: BoxShape.circle)),
                                const SizedBox(width: 6),
                                Text('Online', style: AppTypography.caption.copyWith(color: AppColors.success, fontWeight: FontWeight.w600)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                  const SizedBox(height: 32),

                  Column(
                    children: [
                      Image.asset(
                        'new_logo.png',
                        width: screenW < 360 ? 100 : 140,
                        height: screenW < 360 ? 100 : 140,
                      ),
                      const SizedBox(height: 20),
                      Text(
                        'Ready to meet\nnew people?',
                        textAlign: TextAlign.center,
                        style: AppTypography.displayMedium.copyWith(
                          fontSize: screenW < 360 ? 22 : 28,
                          height: 1.2,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Tap Start to connect with someone\nrandom around the world',
                        textAlign: TextAlign.center,
                        style: AppTypography.bodyMedium.copyWith(color: AppColors.textSecondary, height: 1.5),
                      ),
                    ],
                  ),

                  const SizedBox(height: 40),
                  
                  // RETURN TO CALL BANNER
                  if (context.watch<CallProvider>().state != CallState.idle && context.watch<CallProvider>().state != CallState.ended)
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: screenW > 500 ? screenW * 0.1 : 16, vertical: 8),
                      child: Material(
                        color: AppColors.secondary,
                        borderRadius: BorderRadius.circular(AppDimensions.radiusL),
                        child: InkWell(
                          onTap: () => context.go('/call'),
                          borderRadius: BorderRadius.circular(AppDimensions.radiusL),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.call_made_rounded, color: Colors.white),
                                const SizedBox(width: 8),
                                Text(
                                  'RETURN TO ACTIVE CALL',
                                  style: AppTypography.button.copyWith(color: Colors.white),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),

                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: screenW > 500 ? screenW * 0.1 : 16),
                    child: CustomButton(
                      text: 'START CHATTING',
                      icon: Icons.videocam_rounded,
                      height: 60,
                      onPressed: () => _onStartChatting(context),
                    ),
                  ),

                  const SizedBox(height: 24),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
