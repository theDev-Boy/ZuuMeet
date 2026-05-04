import 'package:flutter/material.dart';
import '../config/app_colors.dart';

/// Bottom control bar for the video call screen.
class CallControls extends StatefulWidget {
  final bool isMicMuted;
  final bool isCameraOff;
  final VoidCallback onToggleMic;
  final VoidCallback onToggleCamera;
  final VoidCallback onSwitchCamera;
  final VoidCallback onNext;
  final VoidCallback onEndCall;

  const CallControls({
    super.key,
    required this.isMicMuted,
    required this.isCameraOff,
    required this.onToggleMic,
    required this.onToggleCamera,
    required this.onSwitchCamera,
    required this.onNext,
    required this.onEndCall,
  });

  @override
  State<CallControls> createState() => _CallControlsState();
}

class _CallControlsState extends State<CallControls> with SingleTickerProviderStateMixin {
  late final AnimationController _shakeCtrl;

  @override
  void initState() {
    super.initState();
    _shakeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
  }

  @override
  void dispose() {
    _shakeCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 20,
        vertical: 16,
      ),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: Colors.white10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ControlButton(
            icon: widget.isMicMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
            isActive: !widget.isMicMuted,
            onTap: widget.onToggleMic,
          ),
          const SizedBox(width: 14),
          _ControlButton(
            icon: widget.isCameraOff ? Icons.videocam_off_rounded : Icons.videocam_rounded,
            isActive: !widget.isCameraOff,
            onTap: widget.onToggleCamera,
          ),
          const SizedBox(width: 14),
          _ControlButton(
            icon: Icons.flip_camera_ios_rounded,
            isActive: true,
            onTap: widget.onSwitchCamera,
          ),
          const SizedBox(width: 14),
          _ControlButton(
            icon: Icons.skip_next_rounded,
            isActive: true,
            onTap: widget.onNext,
            color: AppColors.primary,
          ),
          const SizedBox(width: 14),
          _ControlButton(
            icon: Icons.call_end_rounded,
            isActive: false,
            onTap: widget.onEndCall,
            color: AppColors.error,
          ),
        ],
      ),
    );
  }
}

class _ControlButton extends StatelessWidget {
  final IconData icon;
  final bool isActive;
  final VoidCallback onTap;
  final Color? color;

  const _ControlButton({
    required this.icon,
    required this.isActive,
    required this.onTap,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final bgColor = color ?? (isActive ? Colors.white.withValues(alpha: 0.15) : AppColors.error.withValues(alpha: 0.3));
    final iconColor = isActive ? Colors.white : (color != null ? Colors.white : AppColors.error);

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          color: bgColor,
          shape: BoxShape.circle,
          boxShadow: color != null ? [
            BoxShadow(color: color!.withValues(alpha: 0.3), blurRadius: 12, spreadRadius: 1)
          ] : null,
        ),
        child: Icon(icon, color: color != null ? Colors.white : iconColor, size: 26),
      ),
    );
  }
}
