import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../config/app_colors.dart';
import '../config/app_typography.dart';
import '../providers/auth_provider.dart';
import '../providers/call_provider.dart';
import '../widgets/avatar_widget.dart';
import '../services/database_service.dart';
import '../models/user_model.dart';

class CallScreen extends StatefulWidget {
  const CallScreen({super.key});

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  Offset _localVideoOffset = const Offset(20, 20);

  /// Shows the partner profile as a draggable, swipe-to-dismiss bottom sheet.
  Future<void> _showPartnerProfile(
    BuildContext screenContext,
    String partnerUid,
    AuthProvider auth,
  ) async {
    final dbService = DatabaseService();
    final partner = await dbService.getUser(partnerUid);
    if (!mounted || !screenContext.mounted || partner == null) return;

    if (!screenContext.mounted) return;
    showModalBottomSheet(
      context: screenContext,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      enableDrag: true,
      builder: (ctx) => _PartnerProfileSheet(
        partner: partner,
        myUid: auth.firebaseUser!.uid,
        myModel: auth.userModel!,
        screenContext: screenContext,
        onRefreshAuth: auth.refreshUser,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final call = context.watch<CallProvider>();
    final auth = context.read<AuthProvider>();

    final isConnected = call.state == CallState.connected;
    final isSearchingOrConnecting =
        call.state == CallState.searching || call.state == CallState.connecting;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // ── 1. Remote Video (always mounted, shows when stream is ready) ──
          Positioned.fill(
            child: RTCVideoView(
              call.remoteRenderer,
              objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
              placeholderBuilder: (ctx) => Container(color: Colors.black),
            ),
          ),

          // ── 2. Local Video PiP (draggable, top-right corner) ──
          if (isConnected || call.state == CallState.connecting)
            Positioned(
              top: _localVideoOffset.dy,
              right: _localVideoOffset.dx,
              child: GestureDetector(
                onPanUpdate: (details) {
                  setState(() {
                    _localVideoOffset +=
                        Offset(-details.delta.dx, details.delta.dy);
                    final size = MediaQuery.of(context).size;
                    final clampedX = _localVideoOffset.dx.clamp(4.0, size.width - 124.0);
                    final clampedY = _localVideoOffset.dy.clamp(
                      MediaQuery.of(context).padding.top + 4.0,
                      size.height - 204.0,
                    );
                    _localVideoOffset = Offset(clampedX, clampedY);
                  });
                },
                child: Container(
                  width: 110,
                  height: 160,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.white24, width: 1.5),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.5),
                        blurRadius: 12,
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(13),
                    child: RTCVideoView(
                      call.localRenderer,
                      mirror: true,
                      objectFit:
                          RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                      placeholderBuilder: (ctx) => Container(
                        color: const Color(0xFF1A1A2E),
                        child: const Center(
                          child: Icon(Icons.videocam_off_rounded,
                              color: Colors.white38, size: 28),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),

          // ── 3. Searching / Connecting overlay ──
          if (isSearchingOrConnecting)
            Positioned.fill(
              child: _SearchingOverlay(
                isConnecting: call.state == CallState.connecting,
              ),
            ),

          // ── 4. Connected: Call Header (partner info + dots menu) ──
          if (isConnected)
            Positioned(
              top: MediaQuery.of(context).padding.top + 10,
              left: 16,
              right: 16,
              child: _buildCallHeader(context, call, auth),
            ),

          // ── 5. Connected: Bottom Controls ──
          if (isConnected)
            Positioned(
              bottom: MediaQuery.of(context).padding.bottom + 32,
              left: 0,
              right: 0,
              child: _buildCallControls(context, call, auth),
            ),

          // ── 6. Cancel button (during search) ──
          if (isSearchingOrConnecting)
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
                  icon: const Icon(Icons.close,
                      color: Colors.white60, size: 18),
                  label: const Text(
                    'Cancel Search',
                    style: TextStyle(color: Colors.white60, fontSize: 15),
                  ),
                ),
              ),
            ),

          // ── 7. "Partner ended" / Error overlay ──
          if (call.state == CallState.ended)
            Positioned.fill(
              child: Container(
                color: Colors.black87,
                child: const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.call_end_rounded, color: Colors.red, size: 60),
                      SizedBox(height: 16),
                      Text(
                        'Call Ended',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCallHeader(
    BuildContext context,
    CallProvider call,
    AuthProvider auth,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: Colors.white12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 16,
          ),
        ],
      ),
      child: Row(
        children: [
          AvatarWidget(
            name: call.partnerName ?? 'Partner',
            avatarCode: '',
            radius: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  "${call.partnerFlagEmoji} ${call.partnerName ?? 'Partner'}",
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                if ((call.partnerCountry ?? '').isNotEmpty)
                  Text(
                    'Country Code: ${call.partnerCountry}',
                    style: const TextStyle(color: Colors.white70, fontSize: 11),
                  ),
                Row(
                  children: [
                    const Icon(Icons.circle,
                        color: AppColors.success, size: 8),
                    const SizedBox(width: 4),
                    Text(
                      call.callDurationFormatted,
                      style: const TextStyle(
                        color: AppColors.success,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          _buildCallActionMenu(context, call, auth),
        ],
      ),
    );
  }

  Widget _buildCallControls(
    BuildContext context,
    CallProvider call,
    AuthProvider auth,
  ) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        // Mic
        _buildControlButton(
          icon: call.isMicMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
          color: call.isMicMuted
              ? Colors.red.withValues(alpha: 0.85)
              : Colors.white24,
          onTap: call.toggleMic,
          tooltip: call.isMicMuted ? 'Unmute' : 'Mute',
        ),
        // End Call
        _buildControlButton(
          icon: Icons.call_end_rounded,
          color: Colors.red,
          size: 68,
          onTap: () async {
            await call.stopCompletely(auth.firebaseUser!.uid);
            if (context.mounted) context.go('/home');
          },
          tooltip: 'End Call',
        ),
        // Camera on/off
        _buildControlButton(
          icon: call.isCameraOff
              ? Icons.videocam_off_rounded
              : Icons.videocam_rounded,
          color: call.isCameraOff
              ? Colors.red.withValues(alpha: 0.85)
              : Colors.white24,
          onTap: call.toggleCamera,
          tooltip: call.isCameraOff ? 'Camera On' : 'Camera Off',
        ),
        // Flip camera
        _buildControlButton(
          icon: Icons.flip_camera_ios_rounded,
          color: Colors.white24,
          onTap: call.switchCamera,
          tooltip: 'Flip Camera',
        ),
        // Next
        _buildControlButton(
          icon: Icons.skip_next_rounded,
          color: AppColors.primary,
          onTap: () async {
            if (auth.userModel != null) {
              await call.nextPartner(auth.userModel!);
            }
          },
          tooltip: 'Next Person',
        ),
      ],
    );
  }

  Widget _buildCallActionMenu(
    BuildContext context,
    CallProvider call,
    AuthProvider auth,
  ) {
    if (call.currentMatch == null) return const SizedBox.shrink();

    final partnerUid = call.currentMatch!.user1 == auth.firebaseUser!.uid
        ? call.currentMatch!.user2
        : call.currentMatch!.user1;
    final hasIBlocked =
        auth.userModel?.blockedUsers.contains(partnerUid) ?? false;

    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert_rounded, color: Colors.white),
      color: const Color(0xFF1C1C2E),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      onSelected: (value) async {
        if (value == 'profile') {
          await _showPartnerProfile(context, partnerUid, auth);
        } else if (value == 'request') {
          try {
            await DatabaseService()
                .sendFriendRequest(auth.firebaseUser!.uid, partnerUid);
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('✅ Friend request sent!'),
                  backgroundColor: AppColors.success,
                ),
              );
            }
          } catch (e) {
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(e.toString().replaceFirst('Bad state: ', '')),
                  backgroundColor: AppColors.error,
                ),
              );
            }
          }
        } else if (value == 'block') {
          await DatabaseService()
              .blockUser(auth.firebaseUser!.uid, partnerUid);
          await auth.refreshUser();
          await call.stopCompletely(auth.firebaseUser!.uid);
          if (context.mounted) context.go('/home');
        } else if (value == 'unblock') {
          await DatabaseService()
              .unblockUser(auth.firebaseUser!.uid, partnerUid);
          await auth.refreshUser();
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('✅ User unblocked'),
                backgroundColor: AppColors.success,
              ),
            );
          }
        }
      },
      itemBuilder: (_) {
        final isFriend =
            auth.userModel?.friends.contains(partnerUid) ?? false;
        return [
          const PopupMenuItem(
            value: 'profile',
            child: Row(
              children: [
                Icon(Icons.person_rounded, color: Colors.white70, size: 20),
                SizedBox(width: 12),
                Text('View Profile',
                    style: TextStyle(color: Colors.white)),
              ],
            ),
          ),
          if (!isFriend)
            const PopupMenuItem(
              value: 'request',
              child: Row(
                children: [
                  Icon(Icons.person_add_rounded,
                      color: Colors.white70, size: 20),
                  SizedBox(width: 12),
                  Text('Add Friend',
                      style: TextStyle(color: Colors.white)),
                ],
              ),
            ),
          PopupMenuItem(
            value: hasIBlocked ? 'unblock' : 'block',
            child: Row(
              children: [
                Icon(
                  hasIBlocked
                      ? Icons.lock_open_rounded
                      : Icons.block_rounded,
                  color: AppColors.error,
                  size: 20,
                ),
                const SizedBox(width: 12),
                Text(
                  hasIBlocked ? 'Unblock User' : 'Block User',
                  style: const TextStyle(color: AppColors.error),
                ),
              ],
            ),
          ),
        ];
      },
    );
  }

  Widget _buildControlButton({
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
    double size = 56,
    String tooltip = '',
  }) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.35),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Icon(icon, color: Colors.white, size: size * 0.45),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Partner Profile Bottom Sheet (stateful, slide-to-dismiss)
// ─────────────────────────────────────────────────────────────────────────────

class _PartnerProfileSheet extends StatefulWidget {
  final UserModel partner;
  final String myUid;
  final UserModel myModel;
  final BuildContext screenContext;
  final Future<void> Function() onRefreshAuth;

  const _PartnerProfileSheet({
    required this.partner,
    required this.myUid,
    required this.myModel,
    required this.screenContext,
    required this.onRefreshAuth,
  });

  @override
  State<_PartnerProfileSheet> createState() => _PartnerProfileSheetState();
}

class _PartnerProfileSheetState extends State<_PartnerProfileSheet> {
  late bool _isFriend;
  late bool _hasIBlocked;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _isFriend = widget.myModel.friends.contains(widget.partner.uid);
    _hasIBlocked = widget.myModel.blockedUsers.contains(widget.partner.uid);
  }

  Future<void> _sendRequest() async {
    setState(() => _isLoading = true);
    try {
      await DatabaseService()
          .sendFriendRequest(widget.myUid, widget.partner.uid);
      if (mounted) {
        Navigator.pop(context);
        if (widget.screenContext.mounted) {
          ScaffoldMessenger.of(widget.screenContext).showSnackBar(
            const SnackBar(
              content: Text('✅ Friend request sent!'),
              backgroundColor: AppColors.success,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString().replaceFirst('Bad state: ', '')),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _toggleBlock() async {
    setState(() => _isLoading = true);
    try {
      if (_hasIBlocked) {
        await DatabaseService().unblockUser(widget.myUid, widget.partner.uid);
        setState(() => _hasIBlocked = false);
      } else {
        await DatabaseService().blockUser(widget.myUid, widget.partner.uid);
        setState(() => _hasIBlocked = true);
      }
      await widget.onRefreshAuth();
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _goToChat() async {
    final chatId =
        ([widget.myUid, widget.partner.uid]..sort()).join('_');
    if (mounted) Navigator.pop(context);
    if (widget.screenContext.mounted) {
      widget.screenContext.push('/chat/$chatId');
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return DraggableScrollableSheet(
      initialChildSize: 0.55,
      minChildSize: 0.3,
      maxChildSize: 0.85,
      snap: true,
      snapSizes: const [0.3, 0.55, 0.85],
      builder: (ctx, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1A1A2E) : Colors.white,
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Drag handle
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  width: 48,
                  height: 4,
                  margin: const EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white24 : Colors.black12,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),

              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(24, 4, 24, 32),
                  children: [
                    // Avatar
                    Center(
                      child: AvatarWidget(
                        name: widget.partner.name,
                        avatarCode: widget.partner.avatarUrl,
                        radius: 48,
                        showFrame: true,
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Name + ID
                    Center(
                      child: Column(
                        children: [
                          Text(
                            widget.partner.name,
                            style: AppTypography.headlineMedium,
                          ),
                          const SizedBox(height: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 4),
                            decoration: BoxDecoration(
                              color: AppColors.primary
                                  .withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              widget.partner.displayId,
                              style: const TextStyle(
                                color: AppColors.primary,
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Info pills
                    Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 10,
                      runSpacing: 8,
                      children: [
                        if (widget.partner.country.isNotEmpty)
                          _infoPill(
                            '${widget.partner.flagEmoji} ${widget.partner.country}',
                            isDark,
                          ),
                        if (widget.partner.age.isNotEmpty)
                          _infoPill(
                              '🎂 Age ${widget.partner.age}', isDark),
                        if (widget.partner.gender.isNotEmpty)
                          _infoPill(
                              widget.partner.gender == 'Male'
                                  ? '♂ Male'
                                  : '♀ Female',
                              isDark),
                      ],
                    ),
                    const SizedBox(height: 28),

                    // Action Buttons
                    if (_isLoading)
                      const Center(child: CircularProgressIndicator()),

                    if (!_isLoading) ...[
                      // If friend: Chat button
                      if (_isFriend)
                        _actionButton(
                          icon: Icons.chat_bubble_rounded,
                          label: 'Open Chat',
                          color: AppColors.primary,
                          onTap: _goToChat,
                        ),

                      if (!_isFriend)
                        _actionButton(
                          icon: Icons.person_add_rounded,
                          label: 'Send Friend Request',
                          color: AppColors.primary,
                          onTap: _sendRequest,
                        ),

                      const SizedBox(height: 10),

                      // Block / Unblock
                      _actionButton(
                        icon: _hasIBlocked
                            ? Icons.lock_open_rounded
                            : Icons.block_rounded,
                        label: _hasIBlocked ? 'Unblock User' : 'Block User',
                        color: AppColors.error,
                        onTap: _toggleBlock,
                        outlined: true,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _infoPill(String text, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF2A2A3E) : const Color(0xFFF4F4F8),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 13,
          color: isDark ? Colors.white70 : Colors.black87,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Widget _actionButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
    bool outlined = false,
  }) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: outlined
          ? OutlinedButton.icon(
              onPressed: onTap,
              icon: Icon(icon, color: color, size: 20),
              label: Text(label,
                  style: TextStyle(
                      color: color, fontWeight: FontWeight.w600)),
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: color, width: 1.5),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
            )
          : ElevatedButton.icon(
              onPressed: onTap,
              icon: Icon(icon, color: Colors.white, size: 20),
              label: Text(label,
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w600)),
              style: ElevatedButton.styleFrom(
                backgroundColor: color,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
                elevation: 0,
              ),
            ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Searching / Connecting Animated Overlay
// ─────────────────────────────────────────────────────────────────────────────

class _SearchingOverlay extends StatefulWidget {
  final bool isConnecting;
  const _SearchingOverlay({required this.isConnecting});

  @override
  State<_SearchingOverlay> createState() => _SearchingOverlayState();
}

class _SearchingOverlayState extends State<_SearchingOverlay>
    with SingleTickerProviderStateMixin {
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
    return Container(
      color: Colors.black,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Stack(
              alignment: Alignment.center,
              children: [
                AnimatedBuilder(
                  animation: _controller,
                  builder: (_, __) => Container(
                    width: 100 + (120 * _controller.value),
                    height: 100 + (120 * _controller.value),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.primary
                          .withValues(alpha: (1.0 - _controller.value) * 0.4),
                    ),
                  ),
                ),
                Container(
                  width: 100,
                  height: 100,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [AppColors.primary, Color(0xFF6C47FF)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: Icon(
                    widget.isConnecting
                        ? Icons.wifi_tethering_rounded
                        : Icons.person_search_rounded,
                    color: Colors.white,
                    size: 44,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 40),
            Text(
              widget.isConnecting
                  ? 'Connecting…'
                  : 'Searching for Partner…',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              widget.isConnecting
                  ? 'Setting up your video call'
                  : 'Finding someone amazing for you',
              style: const TextStyle(color: Colors.white54, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }
}
