import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_ringtone_player/flutter_ringtone_player.dart';
import 'package:vibration/vibration.dart';
import '../providers/auth_provider.dart';
import '../config/app_colors.dart';
import '../config/app_typography.dart';
import '../services/database_service.dart';
import '../widgets/avatar_widget.dart';

class IncomingCallWrapper extends StatefulWidget {
  final Widget child;
  const IncomingCallWrapper({super.key, required this.child});

  @override
  State<IncomingCallWrapper> createState() => _IncomingCallWrapperState();
}

class _IncomingCallWrapperState extends State<IncomingCallWrapper>
    with TickerProviderStateMixin {
  StreamSubscription? _callSub;
  Map<dynamic, dynamic>? _incomingCall;
  String _status = 'Incoming call';

  late AnimationController _pulseController;
  late AnimationController _buttonController;
  Timer? _autoEndTimer;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();

    _buttonController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _listenForIncomingCalls();
    });
  }

  @override
  void dispose() {
    _callSub?.cancel();
    _pulseController.dispose();
    _buttonController.dispose();
    _autoEndTimer?.cancel();
    _stopRinging();
    super.dispose();
  }

  void _startRinging() {
    FlutterRingtonePlayer().playRingtone();
    Vibration.vibrate(pattern: [500, 1000, 500, 1000]);
  }

  void _stopRinging() {
    FlutterRingtonePlayer().stop();
    Vibration.cancel();
  }

  void _listenForIncomingCalls() {
    final auth = context.read<AuthProvider>();
    if (auth.firebaseUser != null) {
      _setupListener(auth.firebaseUser!.uid);
    }

    auth.addListener(() {
      if (mounted && auth.firebaseUser != null && _callSub == null) {
        _setupListener(auth.firebaseUser!.uid);
      } else if (mounted && auth.firebaseUser == null) {
        _callSub?.cancel();
        _callSub = null;
        if (_incomingCall != null) {
          _stopRinging();
          _autoEndTimer?.cancel();
          setState(() => _incomingCall = null);
        }
      }
    });
  }

  void _setupListener(String uid) {
    _callSub?.cancel();
    _callSub = FirebaseDatabase.instance
        .ref('direct_calls')
        .child(uid)
        .onValue
        .listen((event) {
          if (!mounted) return;
          if (event.snapshot.value != null) {
            final data = Map<dynamic, dynamic>.from(
              event.snapshot.value as Map,
            );

            // Safety: ensure we don't receive our own call
            final auth = context.read<AuthProvider>();
            if (data['callerId'] == auth.firebaseUser?.uid) return;

            if (_incomingCall == null) {
              _status = 'Incoming call';
              _startRinging();
              // Auto end after 1 minute
              _autoEndTimer?.cancel();
              _autoEndTimer = Timer(
                const Duration(minutes: 1),
                () => _rejectCall(),
              );
            }
            setState(() => _incomingCall = data);
          } else {
            if (_incomingCall != null) {
              _stopRinging();
              _autoEndTimer?.cancel();
            }
            setState(() => _incomingCall = null);
          }
        });
  }

  void _acceptCall() async {
    if (_incomingCall == null) return;
    _stopRinging();
    _autoEndTimer?.cancel();

    final callData = _incomingCall!;
    final callerId = callData['callerId'] as String;
    final callerName = callData['callerName'] as String;

    final auth = context.read<AuthProvider>();
    final myUid = auth.firebaseUser!.uid;

    try {
      final callType = callData['callType'] as String? ?? 'video';
      final matchId = callData['matchId'] as String? ?? '';
      final channelName = callData['channelName'] as String? ?? matchId;
      if (matchId.isNotEmpty) {
        await DatabaseService().acceptDirectCall(myUid: myUid, matchId: matchId);
      } else {
        await FirebaseDatabase.instance.ref('direct_calls').child(myUid).remove();
      }

      if (mounted) {
        if (callType == 'audio') {
          context.push(
            '/audio-call',
            extra: {
              'callId': callData['callId'] as String? ?? matchId,
              'matchId': matchId,
              'channelName': channelName,
              'partnerUid': callerId,
              'partnerName': callerName,
              'partnerAvatar': callData['callerAvatar'] as String? ?? '',
              'isOutgoing': false,
            },
          );
        } else {
          context.push(
            '/video-call',
            extra: {
              'callId': callData['callId'] as String? ?? matchId,
              'matchId': matchId,
              'channelName': channelName,
              'partnerUid': callerId,
              'partnerName': callerName,
              'partnerAvatar': callData['callerAvatar'] as String? ?? '',
              'isOutgoing': false,
            },
          );
        }
      }
    } catch (e) {
      _rejectCall();
    }
  }

  void _rejectCall() async {
    _stopRinging();
    _autoEndTimer?.cancel();
    final auth = context.read<AuthProvider>();
    if (auth.firebaseUser != null) {
      final matchId = _incomingCall?['matchId'] as String?;
      if (matchId != null && matchId.isNotEmpty) {
        await DatabaseService().rejectDirectCall(
          myUid: auth.firebaseUser!.uid,
          matchId: matchId,
          status: 'declined',
        );
      } else {
        await FirebaseDatabase.instance
            .ref('direct_calls')
            .child(auth.firebaseUser!.uid)
            .remove();
      }
    }
    setState(() => _incomingCall = null);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Stack(
      children: [
        widget.child,

        if (_incomingCall != null)
          Positioned.fill(
            child: Material(
              color: isDark ? const Color(0xFF121212) : Colors.white,
              child: SafeArea(
                child: Column(
                  children: [
                    const SizedBox(height: 20),
                    // App Logo & Name
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.asset(
                            'new_logo.png',
                            width: 24,
                            height: 24,
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Text(
                          'ZuuMeet',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),

                    const Spacer(),

                    // Caller Avatar
                    ScaleTransition(
                      scale: Tween<double>(begin: 1.0, end: 1.05).animate(
                        CurvedAnimation(
                          parent: _pulseController,
                          curve: Curves.easeInOut,
                        ),
                      ),
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: AppColors.primary.withValues(alpha: 0.3),
                            width: 2,
                          ),
                        ),
                        child: AvatarWidget(
                          name: _incomingCall!['callerName'] ?? '?',
                          radius: 70,
                        ),
                      ),
                    ),

                    const SizedBox(height: 32),

                    // Caller Name
                    Text(
                      _incomingCall!['callerName'] ?? 'Someone',
                      style: AppTypography.displayMedium.copyWith(
                        fontSize: 32,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _status,
                      style: AppTypography.bodyLarge.copyWith(
                        color: AppColors.textSecondary,
                        letterSpacing: 1.2,
                      ),
                    ),

                    const Spacer(flex: 2),

                    // Swipe Area / Buttons
                    _buildSwipeControls(),

                    const SizedBox(height: 60),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildSwipeControls() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          // Decline Column
          _buildCallButton(
            icon: Icons.call_end_rounded,
            label: 'Decline',
            color: AppColors.error,
            onTap: _rejectCall,
            isAccept: false,
          ),

          const SizedBox(width: 40),

          // Accept Column
          _buildCallButton(
            icon: Icons.call_rounded,
            label: 'Accept',
            color: AppColors.success,
            onTap: _acceptCall,
            isAccept: true,
          ),
        ],
      ),
    );
  }

  Widget _buildCallButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
    required bool isAccept,
  }) {
    return Column(
      children: [
        AnimatedBuilder(
          animation: _buttonController,
          builder: (context, child) {
            final offset = isAccept ? _buttonController.value * 10 : 0.0;
            final shake = !isAccept
                ? (math.sin(_buttonController.value * math.pi * 4) * 3)
                : 0.0;

            return Transform.translate(
              offset: Offset(shake, -offset),
              child: GestureDetector(
                onPanUpdate: (details) {
                  if (isAccept && details.delta.dy < -10) onTap();
                  if (!isAccept && details.delta.dy > 10) onTap();
                },
                child: Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: color.withValues(alpha: 0.4),
                        blurRadius: 15,
                        spreadRadius: 2,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Icon(icon, color: Colors.white, size: 32),
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 16),
        Text(
          label,
          style: TextStyle(
            color: color.withValues(alpha: 0.8),
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
        ),
      ],
    );
  }
}
