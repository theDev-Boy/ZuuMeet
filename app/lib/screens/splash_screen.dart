import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../utils/constants.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animCtrl;
  late final Animation<double> _fadeAnim;
  late final Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _fadeAnim = CurvedAnimation(parent: _animCtrl, curve: Curves.easeIn);
    _scaleAnim = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(parent: _animCtrl, curve: Curves.easeOutBack),
    );
    _animCtrl.forward();
    _navigateToNext();
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    super.dispose();
  }

  Future<void> _navigateToNext() async {
    await Future.delayed(const Duration(milliseconds: AppConstants.splashDurationMs));
    if (!mounted) return;

    final auth = context.read<AuthProvider>();
    
    // If user is logged in to Firebase Auth but userModel hasn't finished loading yet,
    // wait for it (up to a reasonable timeout of 5 seconds to avoid infinite loops).
    if (auth.firebaseUser != null && auth.userModel == null) {
      final startTime = DateTime.now();
      while (mounted && 
             auth.firebaseUser != null && 
             auth.userModel == null && 
             DateTime.now().difference(startTime).inSeconds < 5) {
        await Future.delayed(const Duration(milliseconds: 100));
      }
    }
    if (!mounted) return;

    if (auth.isLoggedIn) {
      context.go('/home');
    } else {
      context.go('/auth');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: FadeTransition(
          opacity: _fadeAnim,
          child: ScaleTransition(
            scale: _scaleAnim,
            child: Image.asset(
              'new_logo.png',
              width: 240,
              height: 240,
              fit: BoxFit.contain,
            ),
          ),
        ),
      ),
    );
  }
}
