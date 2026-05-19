import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_callkit_incoming/entities/call_event.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'config/app_colors.dart';
import 'config/app_dimensions.dart';
import 'config/app_typography.dart';
import 'providers/auth_provider.dart';
import 'providers/theme_provider.dart';
import 'routes/app_router.dart';
import 'widgets/offline_wrapper.dart';
import 'widgets/incoming_call_wrapper.dart';
import 'services/call_notification_service.dart';
import 'services/database_service.dart';
import 'services/system_call_service.dart';

class ZuumeetApp extends StatelessWidget {
  const ZuumeetApp({super.key});

  @override
  Widget build(BuildContext context) {
    final authProvider = context.read<AuthProvider>();
    final router = AppRouter.router(authProvider);
    final themeProvider = context.watch<ThemeProvider>();

    return MaterialApp.router(
      title: 'Zuumeet',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        primaryColor: AppColors.primary,
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.primary,
          primary: AppColors.primary,
          secondary: AppColors.secondary,
          surface: AppColors.surface,
          error: AppColors.error,
        ),
        scaffoldBackgroundColor: AppColors.background,
        appBarTheme: AppBarTheme(
          backgroundColor: AppColors.background,
          elevation: 0,
          titleTextStyle: AppTypography.headlineMedium.copyWith(
            color: AppColors.textPrimary,
          ),
          centerTitle: true,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppDimensions.radiusL),
            ),
            elevation: 0,
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.primary,
            side: const BorderSide(color: AppColors.border),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppDimensions.radiusL),
            ),
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: AppColors.backgroundSecondary,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppDimensions.radiusL),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.all(16),
        ),
      ),
      darkTheme: ThemeData.dark(useMaterial3: true).copyWith(
        primaryColor: AppColors.primary,
        scaffoldBackgroundColor: const Color(0xFF121212),
        appBarTheme: AppBarTheme(
          backgroundColor: const Color(0xFF121212),
          elevation: 0,
          titleTextStyle: AppTypography.headlineMedium.copyWith(
            color: Colors.white,
          ),
          centerTitle: true,
          iconTheme: const IconThemeData(color: Colors.white70),
        ),
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.primary,
          brightness: Brightness.dark,
          primary: AppColors.primary,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFF1E1E1E),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppDimensions.radiusL),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.all(16),
        ),
      ),
      themeMode: themeProvider.themeMode,
      routerConfig: router,
      builder: (context, child) {
        return NotificationRouteWrapper(
          child: OfflineWrapper(child: IncomingCallWrapper(child: child!)),
        );
      },
    );
  }
}

class NotificationRouteWrapper extends StatefulWidget {
  const NotificationRouteWrapper({super.key, required this.child});
  final Widget child;

  @override
  State<NotificationRouteWrapper> createState() => _NotificationRouteWrapperState();
}

class _NotificationRouteWrapperState extends State<NotificationRouteWrapper> with SingleTickerProviderStateMixin {
  StreamSubscription<String>? _tapSub;
  StreamSubscription<CallEvent?>? _callEventSub;
  StreamSubscription<Map<String, dynamic>>? _inAppSub;
  final SystemCallService _systemCalls = SystemCallService();

  // In-app banner state
  Map<String, dynamic>? _currentBanner;
  late AnimationController _bannerCtrl;
  late Animation<Offset> _bannerAnim;
  Timer? _bannerTimer;

  @override
  void initState() {
    super.initState();
    _bannerCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _bannerAnim = Tween<Offset>(
      begin: const Offset(0, -1.5),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _bannerCtrl, curve: Curves.easeOutBack));

    CallNotificationService().onNotificationTap.listen((payload) {
      if (!mounted) return;
      if (payload.startsWith('call:')) {
        final query = payload.replaceFirst('call:', '');
        final data = <String, String>{};
        for (final part in query.split('&')) {
          if (part.isEmpty || !part.contains('=')) continue;
          final pieces = part.split('=');
          data[pieces.first] =
              Uri.decodeComponent(pieces.sublist(1).join('='));
        }
        _openCall(data, isOutgoing: false);
        return;
      }
      if (payload.startsWith('chat:')) {
        final chatId = payload.replaceFirst('chat:', '');
        if (chatId.isNotEmpty) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              GoRouter.of(context).go('/chat/$chatId');
            }
          });
        }
      }
    });

    _inAppSub = CallNotificationService().onInAppMessage.listen((data) {
      if (!mounted) return;
      // Don't show banner if already on that chat screen
      final currentRoute = GoRouterState.of(context).uri.toString();
      final targetChatId = data['chatId'];
      if (currentRoute == '/chat/$targetChatId') return;

      setState(() => _currentBanner = data);
      _bannerCtrl.forward();
      _bannerTimer?.cancel();
      _bannerTimer = Timer(const Duration(seconds: 3), () {
        if (mounted) _bannerCtrl.reverse();
      });
    });

    // Schedule the 24h engagement reminder
    unawaited(CallNotificationService().scheduleDailyReminder());

    _callEventSub = CallNotificationService().onSystemCallEvent.listen((event) {
      if (!mounted || event == null) return;
      final data = _systemCalls.eventBodyToCallData(event.body);
      switch (event.event) {
        case Event.actionCallAccept:
        case Event.actionCallStart:
        case Event.actionCallCallback:
          _openCall(data, isOutgoing: false);
          break;
        case Event.actionCallDecline:
        case Event.actionCallEnded:
        case Event.actionCallTimeout:
          final matchId = (data['matchId'] ?? data['callId'])?.toString();
          final myUid = context.read<AuthProvider>().firebaseUser?.uid;
          if (matchId != null && matchId.isNotEmpty && myUid != null) {
            unawaited(DatabaseService().rejectDirectCall(
              myUid: myUid,
              matchId: matchId,
              status: event.event == Event.actionCallTimeout ? 'missed' : 'declined',
            ));
          }
          break;
        default:
          break;
      }
    });
  }

  void _openCall(Map<String, dynamic> data, {required bool isOutgoing}) {
    final matchId = (data['matchId'] ?? data['callId'])?.toString() ?? '';
    final channelName = (data['channelName'] ?? matchId).toString();
    final callType = (data['callType'] ?? 'video').toString();
    final myUid = context.read<AuthProvider>().firebaseUser?.uid;
    final callerId = data['callerId']?.toString() ?? '';
    final calleeUid = data['calleeUid']?.toString() ?? '';
    final partnerUid = callerId.isNotEmpty && callerId != myUid ? callerId : calleeUid;
    final partnerName = partnerUid == callerId
        ? (data['callerName'] ?? 'Unknown').toString()
        : (data['calleeName'] ?? 'Unknown').toString();
    final partnerAvatar = partnerUid == callerId
        ? (data['callerAvatar'] ?? '').toString()
        : (data['calleeAvatar'] ?? '').toString();

    if (matchId.isEmpty || partnerUid.isEmpty) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final router = GoRouter.of(context);
      final extra = {
        'callId': (data['callId'] ?? matchId).toString(),
        'matchId': matchId,
        'roomId': (data['roomId'] ?? data['callId'] ?? matchId).toString(),
        'channelName': channelName,
        'partnerUid': partnerUid,
        'partnerName': partnerName,
        'partnerAvatar': partnerAvatar,
        'isOutgoing': isOutgoing,
      };
      if (callType == 'audio') {
        router.go('/audio-call', extra: extra);
      } else {
        router.go('/video-call', extra: extra);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        if (_currentBanner != null)
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            left: 16,
            right: 16,
            child: SlideTransition(
              position: _bannerAnim,
              child: Material(
                color: Colors.transparent,
                child: GestureDetector(
                  onTap: () {
                    _bannerCtrl.reverse();
                    final chatId = _currentBanner?['chatId'];
                    if (chatId != null && chatId.isNotEmpty) {
                      GoRouter.of(context).go('/chat/$chatId');
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Theme.of(context).brightness == Brightness.dark
                          ? const Color(0xFF1E1E2A)
                          : Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.15),
                          blurRadius: 20,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.15),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.chat_bubble_rounded,
                              color: AppColors.primary, size: 20),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _currentBanner!['title'] ?? 'New Message',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                _currentBanner!['body'] ?? 'Tap to view',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  @override
  void dispose() {
    _tapSub?.cancel();
    _callEventSub?.cancel();
    _inAppSub?.cancel();
    _bannerCtrl.dispose();
    _bannerTimer?.cancel();
    super.dispose();
  }
}
