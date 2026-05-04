import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../config/app_colors.dart';
import '../providers/auth_provider.dart';
import '../providers/call_provider.dart';
import '../widgets/searching_animation.dart';

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
        ],
      ),
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
