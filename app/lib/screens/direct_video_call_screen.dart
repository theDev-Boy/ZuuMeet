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
  Offset _pipOffset = const Offset(20, 100);

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
          // 1. Remote Video (Full Screen)
          if (isConnected)
            Positioned.fill(
              child: RTCVideoView(
                call.remoteRenderer,
                objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
              ),
            )
          else
            _buildCallingState(widget.isOutgoing ? 'Calling...' : 'Connecting...'),

          // 2. Local Video (PIP) - Movable
          Positioned(
            left: _pipOffset.dx,
            top: _pipOffset.dy,
            child: GestureDetector(
              onPanUpdate: (details) {
                setState(() {
                  _pipOffset += details.delta;
                });
              },
              child: Container(
                width: 110,
                height: 160,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white24, width: 1),
                  boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 10)],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: RTCVideoView(
                    call.localRenderer,
                    mirror: true,
                    objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                  ),
                ),
              ),
            ),
          ),

          // 3. Top Info Bar
          Positioned(
            top: MediaQuery.of(context).padding.top + 10,
            left: 20,
            right: 20,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.black38,
                borderRadius: BorderRadius.circular(30),
              ),
              child: Row(
                children: [
                  const Icon(Icons.lock_rounded, color: Colors.white54, size: 14),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      widget.partnerName,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (isConnected)
                    Text(
                      call.callDurationFormatted,
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                    ),
                ],
              ),
            ),
          ),

          // 4. Professional Controls (Bottom)
          Positioned(
            bottom: 40,
            left: 20,
            right: 20,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 20),
              decoration: BoxDecoration(
                color: Colors.white12,
                borderRadius: BorderRadius.circular(40),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildControlBtn(
                    icon: call.isMicMuted ? Icons.mic_off : Icons.mic,
                    isActive: !call.isMicMuted,
                    onTap: call.toggleMic,
                  ),
                  _buildControlBtn(
                    icon: call.isCameraOff ? Icons.videocam_off : Icons.videocam,
                    isActive: !call.isCameraOff,
                    onTap: call.toggleCamera,
                  ),
                  _buildControlBtn(
                    icon: Icons.switch_camera,
                    onTap: call.switchCamera,
                  ),
                  _buildControlBtn(
                    icon: Icons.call_end,
                    color: Colors.red,
                    size: 64,
                    onTap: () async {
                      await call.endCall(auth.firebaseUser!.uid);
                      if (context.mounted) context.pop();
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCallingState(String status) {
    return Positioned.fill(
      child: Container(
        color: Colors.black.withValues(alpha: 0.6),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(color: Colors.white),
            const SizedBox(height: 24),
            Text(status, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(widget.partnerName, style: const TextStyle(color: Colors.white70, fontSize: 16)),
          ],
        ),
      ),
    );
  }

  Widget _buildControlBtn({
    required IconData icon,
    bool isActive = true,
    Color? color,
    required VoidCallback onTap,
    double size = 50,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: color ?? (isActive ? Colors.white24 : Colors.red),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: Colors.white, size: size * 0.5),
      ),
    );
  }
}
