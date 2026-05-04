import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../config/app_colors.dart';
import '../providers/auth_provider.dart';
import '../providers/call_provider.dart';
import '../widgets/avatar_widget.dart';
import '../services/database_service.dart';

class CallScreen extends StatefulWidget {
  const CallScreen({super.key});

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  @override
  Widget build(BuildContext context) {
    final call = context.watch<CallProvider>();
    final auth = context.read<AuthProvider>();

    final isConnected = call.state == CallState.connected;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // 1. Remote Video (Full Screen)
          if (isConnected)
            Positioned.fill(
              child: RTCVideoView(
                call.remoteRenderer,
                objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
              ),
            ),

          // 2. Local Video (Picture-in-Picture)
          if (isConnected)
            Positioned(
              top: MediaQuery.of(context).padding.top + 20,
              right: 20,
              width: 100,
              height: 150,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: RTCVideoView(
                  call.localRenderer,
                  mirror: true,
                  objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                ),
              ),
            ),

          // 3. Searching Animation
          if (!isConnected)
            Positioned.fill(
              child: SearchingAnimation(
                isConnecting: call.state == CallState.connecting,
              ),
            ),

          // 4. In-Call Controls (Bottom)
          if (isConnected)
            Positioned(
              bottom: 40,
              left: 0,
              right: 0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildControlButton(
                    icon: call.isMicMuted ? Icons.mic_off : Icons.mic,
                    color: call.isMicMuted ? Colors.red : Colors.white24,
                    onTap: call.toggleMic,
                  ),
                  _buildControlButton(
                    icon: Icons.call_end,
                    color: Colors.red,
                    size: 64,
                    onTap: () async {
                      await call.stopCompletely(auth.firebaseUser!.uid);
                      if (context.mounted) context.go('/home');
                    },
                  ),
                  _buildControlButton(
                    icon: Icons.skip_next,
                    color: AppColors.primary,
                    onTap: () async {
                      await call.nextPartner(auth.userModel!);
                    },
                  ),
                ],
              ),
            ),

          // 5. Cancel Button (During Search)
          if (!isConnected)
            Positioned(
              bottom: MediaQuery.of(context).padding.bottom + 24,
              left: 0,
              right: 0,
              child: Center(
                child: TextButton.icon(
                  onPressed: () async {
                    await call.stopCompletely(auth.firebaseUser!.uid);
                    if (context.mounted) context.go('/home');
                  },
                  icon: const Icon(Icons.close, color: Colors.white54, size: 18),
                  label: const Text(
                    'Cancel Search',
                    style: TextStyle(color: Colors.white54, fontSize: 15),
                  ),
                ),
              ),
            ),

          // 6. Call Header (When Connected)
          if (isConnected)
            Positioned(
              top: MediaQuery.of(context).padding.top + 10,
              left: 20,
              right: 20,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.black45,
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(color: Colors.white10),
                ),
                child: Row(
                  children: [
                    AvatarWidget(
                      name: call.partnerName ?? 'Partner',
                      avatarCode: '', // In production, we'd fetch this or pass it
                      radius: 20,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            call.partnerName ?? 'Connecting...',
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            call.callDurationFormatted,
                            style: const TextStyle(color: AppColors.success, fontSize: 12, fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                    _buildCallActionMenu(context, call, auth),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCallActionMenu(BuildContext context, CallProvider call, AuthProvider auth) {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert, color: Colors.white),
      color: const Color(0xFF1E1E1E),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      onSelected: (value) async {
        if (call.currentMatch == null) return;
        final partnerUid = call.currentMatch!.user1 == auth.firebaseUser!.uid 
            ? call.currentMatch!.user2 
            : call.currentMatch!.user1;

        if (value == 'profile') {
          // View Profile Logic
        } else if (value == 'request') {
          await DatabaseService().sendFriendRequest(auth.firebaseUser!.uid, partnerUid);
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Request Sent!')));
          }
        } else if (value == 'block') {
          await DatabaseService().blockUser(auth.firebaseUser!.uid, partnerUid);
          await call.stopCompletely(auth.firebaseUser!.uid);
          if (context.mounted) context.go('/home');
        }
      },
      itemBuilder: (context) => [
        const PopupMenuItem(
          value: 'profile',
          child: Row(
            children: [Icon(Icons.person, color: Colors.white, size: 20), SizedBox(width: 10), Text('View Profile', style: TextStyle(color: Colors.white))],
          ),
        ),
        const PopupMenuItem(
          value: 'request',
          child: Row(
            children: [Icon(Icons.person_add, color: Colors.white, size: 20), SizedBox(width: 10), Text('Send Request', style: TextStyle(color: Colors.white))],
          ),
        ),
        const PopupMenuItem(
          value: 'block',
          child: Row(
            children: [Icon(Icons.block, color: AppColors.error, size: 20), SizedBox(width: 10), Text('Block User', style: TextStyle(color: AppColors.error))],
          ),
        ),
      ],
    );
  }

  Widget _buildControlButton({
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
    double size = 56,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: Colors.white, size: size * 0.5),
      ),
    );
  }
}

class SearchingAnimation extends StatefulWidget {
  final bool isConnecting;
  const SearchingAnimation({super.key, required this.isConnecting});

  @override
  State<SearchingAnimation> createState() => _SearchingAnimationState();
}

class _SearchingAnimationState extends State<SearchingAnimation> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Stack(
            alignment: Alignment.center,
            children: [
              AnimatedBuilder(
                animation: _controller,
                builder: (context, child) {
                  return Container(
                    width: 100 + (100 * _controller.value),
                    height: 100 + (100 * _controller.value),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.primary.withValues(alpha: 1.0 - _controller.value),
                    ),
                  );
                },
              ),
              Container(
                width: 100,
                height: 100,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.primary,
                ),
                child: const Icon(Icons.person_search_rounded, color: Colors.white, size: 40),
              ),
            ],
          ),
          const SizedBox(height: 40),
          Text(
            widget.isConnecting ? 'Connecting...' : 'Searching for Partner...',
            style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            'Hold tight, we\'re finding someone amazing!',
            style: TextStyle(color: Colors.white54, fontSize: 14),
          ),
        ],
      ),
    );
  }
}
