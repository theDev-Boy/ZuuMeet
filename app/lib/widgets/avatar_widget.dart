import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../models/user_model.dart';

class AvatarWidget extends StatelessWidget {
  final String? name;
  final String? avatarCode;
  final UserModel? user;
  final double radius;
  final bool showFrame;

  const AvatarWidget({
    super.key,
    this.name,
    this.avatarCode,
    this.user,
    this.radius = 30,
    this.showFrame = true,
  });

  String get displayName => user?.name ?? name ?? '?';
  String? get currentAvatar => user?.avatarUrl ?? avatarCode;
  String? get frameId => user?.frameId;

  String get initials {
    final n = displayName;
    if (n.isEmpty || n == '?') return '?';
    return n.trim().isNotEmpty ? n.trim()[0].toUpperCase() : '?';
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: radius * 2.4, // Extra space for frame
      height: radius * 2.4,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // 1. THE ACTUAL AVATAR
          Container(
            width: radius * 2,
            height: radius * 2,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: _getGradient(),
            ),
            clipBehavior: Clip.antiAlias,
            child: currentAvatar != null && currentAvatar!.isNotEmpty
                ? _buildCodedAvatar()
                : Center(
                    child: Text(
                      initials,
                      style: TextStyle(
                        fontSize: radius * 0.8,
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
          ),
          
          // 2. FRAME OVERLAY
          if (showFrame && frameId != null && frameId != 'none' && frameId != 'free_border')
             _buildPremiumFrame(),

          // 3. DEFAULT BORDER (if no premium frame)
          if (!showFrame || frameId == null || frameId == 'none' || frameId == 'free_border')
            Container(
              width: radius * 2,
              height: radius * 2,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white.withValues(alpha: 0.2), width: 1.5),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPremiumFrame() {
    // Logic for premium frames
    Color frameColor = Colors.amber;
    if (frameId == 'vip_gold') frameColor = const Color(0xFFFFD700);
    if (frameId == 'diamond_blue') frameColor = const Color(0xFF00E5FF);
    if (frameId == 'neon_pink') frameColor = const Color(0xFFFF00E5);

    return Container(
      width: radius * 2.2,
      height: radius * 2.2,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: frameColor, width: 3),
        boxShadow: [
          BoxShadow(color: frameColor.withValues(alpha: 0.5), blurRadius: 8, spreadRadius: 1),
        ],
      ),
    );
  }

  Widget _buildCodedAvatar() {
    final code = currentAvatar!;
    if (code.startsWith('emoji:')) {
      return Center(
        child: Text(
          code.replaceFirst('emoji:', ''),
          style: TextStyle(fontSize: radius * 1.2),
        ),
      );
    }
    
    if (code.startsWith('dicebear:') || code.startsWith('https://api.dicebear.com')) {
      String url = code;
      if (code.startsWith('dicebear:')) {
        final parts = code.split(':');
        final type = parts[1];
        final seed = parts[2];
        url = 'https://api.dicebear.com/7.x/$type/svg?seed=$seed';
      }
      return SvgPicture.network(
        url,
        fit: BoxFit.cover,
        placeholderBuilder: (context) => Center(
          child: Text(initials, style: TextStyle(fontSize: radius * 0.8, color: Colors.white)),
        ),
      );
    }

    if (code.startsWith('http')) {
      // It might be a network image (legacy logic or external)
      return Image.network(
        code,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => Center(child: Text(initials)),
      );
    }
    
    // Default fallback
    return Center(
      child: Text(
        initials,
        style: TextStyle(fontSize: radius * 0.8, color: Colors.white, fontWeight: FontWeight.bold),
      ),
    );
  }

  LinearGradient _getGradient() {
    final h = displayName.hashCode;
    final colors = [
      HSLColor.fromAHSL(1, (h % 360).toDouble(), 0.7, 0.6).toColor(),
      HSLColor.fromAHSL(1, ((h + 40) % 360).toDouble(), 0.7, 0.4).toColor(),
    ];
    return LinearGradient(
      colors: colors,
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    );
  }
}
