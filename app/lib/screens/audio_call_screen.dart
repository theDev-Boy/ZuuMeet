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
      backgroundColor: const Color(0xFF0F172A),
      body: Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF1E293B),
              Color(0xFF0F172A),
            ],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              const SizedBox(height: 60),
              // Partner Identity
              Container(
                width: 140,
                height: 140,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white12, width: 4),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withValues(alpha: 0.4), blurRadius: 30, spreadRadius: 5)
                  ],
                ),
                child: CircleAvatar(
                  radius: 68,
                  backgroundColor: Colors.white.withValues(alpha: 0.05),
                  child: Text(
                    widget.partnerName.substring(0, 1).toUpperCase(),
                    style: const TextStyle(color: Colors.white, fontSize: 56, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              const SizedBox(height: 32),
              Text(
                widget.partnerName,
                style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold, letterSpacing: 1.1),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white12,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  isConnected ? call.callDurationFormatted : (widget.isOutgoing ? 'Calling...' : 'Connecting...'),
                  style: const TextStyle(color: Colors.white70, fontSize: 16, fontWeight: FontWeight.w500),
                ),
              ),
              
              const Spacer(),

              // Controls Action Bar
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 30, vertical: 40),
                padding: const EdgeInsets.symmetric(vertical: 24),
                decoration: BoxDecoration(
                  color: Colors.white12,
                  borderRadius: BorderRadius.circular(40),
                  border: Border.all(color: Colors.white10),
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
                      icon: Icons.call_end,
                      color: Colors.red,
                      size: 72,
                      onTap: () async {
                        await call.endCall(auth.firebaseUser!.uid);
                        if (context.mounted) context.pop();
                      },
                    ),
                    _buildControlBtn(
                      icon: Icons.volume_up_rounded,
                      onTap: () {}, // Speaker toggle logic if needed
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildControlBtn({
    required IconData icon,
    bool isActive = true,
    Color? color,
    required VoidCallback onTap,
    double size = 56,
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
        child: Icon(icon, color: Colors.white, size: size * 0.45),
      ),
    );
  }
}
