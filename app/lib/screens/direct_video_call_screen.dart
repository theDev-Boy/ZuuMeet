import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:go_router/go_router.dart';
import '../providers/call_provider.dart';
import '../providers/auth_provider.dart';

class DirectVideoCallScreen extends StatefulWidget {
  final String partnerUid;
  final String partnerName;
  final bool isOutgoing;
  final String? roomId;

  const DirectVideoCallScreen({
    super.key,
    required this.partnerUid,
    required this.partnerName,
    this.isOutgoing = true,
    this.roomId,
  });

  @override
  State<DirectVideoCallScreen> createState() => _DirectVideoCallScreenState();
}

class _DirectVideoCallScreenState extends State<DirectVideoCallScreen> {
  bool _initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      final call = context.read<CallProvider>();
      final auth = context.read<AuthProvider>();

      if (widget.isOutgoing) {
        call.startDirectCall(auth.firebaseUser!.uid, widget.partnerUid, isVideo: true);
      } else if (widget.roomId != null) {
        call.answerDirectCall(widget.roomId!, isVideo: true);
      }
      _initialized = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    final call = context.watch<CallProvider>();
    final auth = context.read<AuthProvider>();
    final isConnected = call.state == CallState.connected;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Remote Video (Full Screen)
          if (isConnected)
            Positioned.fill(
              child: RTCVideoView(
                call.remoteRenderer,
                objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
              ),
            )
          else
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const CircularProgressIndicator(color: Colors.white),
                  const SizedBox(height: 20),
                  Text(
                    widget.isOutgoing ? 'Calling ${widget.partnerName}...' : 'Connecting...',
                    style: const TextStyle(color: Colors.white, fontSize: 18),
                  ),
                ],
              ),
            ),
            
          // Local Video (PIP)
          Positioned(
            top: MediaQuery.of(context).padding.top + 20,
            right: 20,
            width: 120,
            height: 180,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(15),
              child: RTCVideoView(
                call.localRenderer,
                mirror: true,
                objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
              ),
            ),
          ),

          // Controls
          Positioned(
            bottom: 50,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildActionBtn(
                  icon: call.isMicMuted ? Icons.mic_off : Icons.mic,
                  color: call.isMicMuted ? Colors.red : Colors.white24,
                  onTap: call.toggleMic,
                ),
                _buildActionBtn(
                  icon: Icons.call_end,
                  color: Colors.red,
                  size: 72,
                  onTap: () async {
                    await call.endCall(auth.firebaseUser!.uid);
                    if (context.mounted) context.pop();
                  },
                ),
                _buildActionBtn(
                  icon: Icons.switch_camera,
                  color: Colors.white24,
                  onTap: call.switchCamera,
                ),
              ],
            ),
          ),

          // Error handling
          if (call.error != null)
            Positioned(
              top: 100,
              left: 20,
              right: 20,
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.8),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  call.error!,
                  style: const TextStyle(color: Colors.white),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildActionBtn({
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
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        child: Icon(icon, color: Colors.white, size: size * 0.5),
      ),
    );
  }
}
