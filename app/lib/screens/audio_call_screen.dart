import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../providers/call_provider.dart';
import '../providers/auth_provider.dart';

class AudioCallScreen extends StatefulWidget {
  final String partnerUid;
  final String partnerName;
  final bool isOutgoing;
  final String? roomId;

  const AudioCallScreen({
    super.key,
    required this.partnerUid,
    required this.partnerName,
    this.isOutgoing = true,
    this.roomId,
  });

  @override
  State<AudioCallScreen> createState() => _AudioCallScreenState();
}

class _AudioCallScreenState extends State<AudioCallScreen> {
  bool _initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      final call = context.read<CallProvider>();
      final auth = context.read<AuthProvider>();

      if (widget.isOutgoing) {
        call.startDirectCall(auth.firebaseUser!.uid, widget.partnerUid, isVideo: false);
      } else if (widget.roomId != null) {
        call.answerDirectCall(widget.roomId!, isVideo: false);
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
      backgroundColor: const Color(0xFF1A1A1A),
      body: SafeArea(
        child: Column(
          children: [
            const Spacer(),
            // Avatar
            const CircleAvatar(
              radius: 60,
              backgroundColor: Colors.white12,
              child: Icon(Icons.person, size: 80, color: Colors.white24),
            ),
            const SizedBox(height: 24),
            Text(
              widget.partnerName,
              style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Text(
              isConnected ? call.callDurationFormatted : (widget.isOutgoing ? 'Calling...' : 'Connecting...'),
              style: const TextStyle(color: Colors.white70, fontSize: 18),
            ),
            const Spacer(),
            // Controls
            Padding(
              padding: const EdgeInsets.only(bottom: 60),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildActionBtn(
                    icon: call.isMicMuted ? Icons.mic_off : Icons.mic,
                    color: call.isMicMuted ? Colors.red : Colors.white12,
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
                    icon: Icons.volume_up,
                    color: Colors.white12,
                    onTap: () {
                      // Handled by device hardware typically, but can toggle speaker
                    },
                  ),
                ],
              ),
            ),
            if (call.error != null)
              Padding(
                padding: const EdgeInsets.all(20),
                child: Text(call.error!, style: const TextStyle(color: Colors.redAccent)),
              ),
          ],
        ),
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
