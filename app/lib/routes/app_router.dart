import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../screens/splash_screen.dart';
import '../screens/auth_screen.dart';
import '../screens/home_screen.dart';
import '../screens/call_screen.dart';
import '../screens/history_screen.dart';
import '../screens/settings_screen.dart';
import '../screens/chat_screen.dart';
import '../screens/audio_call_screen.dart';
import '../screens/direct_video_call_screen.dart';
import '../screens/friends_screen.dart';
import '../screens/blocked_users_screen.dart';

/// App-wide route configuration using GoRouter.
class AppRouter {
  static GoRouter router(AuthProvider authProvider) {
    return GoRouter(
      initialLocation: '/splash',
      refreshListenable: authProvider,
      routes: [
        GoRoute(
          path: '/splash',
          name: 'splash',
          builder: (context, state) => const SplashScreen(),
        ),
        GoRoute(
          path: '/auth',
          name: 'auth',
          builder: (context, state) => const AuthScreen(),
        ),

        GoRoute(
          path: '/home',
          name: 'home',
          builder: (context, state) => const HomeScreen(),
        ),
        GoRoute(
          path: '/call',
          name: 'call',
          builder: (context, state) => const CallScreen(),
        ),
        GoRoute(
          path: '/history',
          name: 'history',
          builder: (context, state) => const HistoryScreen(),
        ),
        GoRoute(
          path: '/settings',
          name: 'settings',
          builder: (context, state) => const SettingsScreen(),
        ),
        GoRoute(
          path: '/blocked-users',
          name: 'blocked-users',
          builder: (context, state) => const BlockedUsersScreen(),
        ),
        GoRoute(
          path: '/chat/:chatId',
          name: 'chat',
          builder: (context, state) {
            final chatId = state.pathParameters['chatId']!;
            return ChatScreen(chatId: chatId);
          },
        ),

        GoRoute(
          path: '/audio-call',
          name: 'audio-call',
          builder: (context, state) {
            final extra = state.extra as Map<String, dynamic>;
            return AudioCallScreen(
              partnerUid: extra['partnerUid'] as String,
              partnerName: extra['partnerName'] as String,
              roomId: extra['roomId'] as String?,
              isOutgoing: extra['isOutgoing'] as bool? ?? true,
            );
          },
        ),
        GoRoute(
          path: '/video-call',
          name: 'video-call',
          builder: (context, state) {
            final extra = state.extra as Map<String, dynamic>;
            return DirectVideoCallScreen(
              partnerUid: extra['partnerUid'] as String,
              partnerName: extra['partnerName'] as String,
              roomId: extra['roomId'] as String?,
              isOutgoing: extra['isOutgoing'] as bool? ?? true,
            );
          },
        ),
        GoRoute(
          path: '/friends',
          name: 'friends',
          builder: (context, state) => const Scaffold(body: FriendsScreen()),
        ),
      ],
      redirect: (context, state) {
        final auth = context.read<AuthProvider>();
        final isLoggedIn = auth.isLoggedIn;
        final currentPath = state.matchedLocation;

        // Allow splash to load
        if (currentPath == '/splash') return null;

        // Not logged in → go to auth
        if (!isLoggedIn) {
          if (currentPath != '/auth') return '/auth';
          return null;
        }

        // Logged in but still on auth → go home
        if (isLoggedIn && currentPath == '/auth') {
          return '/home';
        }

        return null;
      },
    );
  }
}
