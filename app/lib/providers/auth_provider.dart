import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../models/user_model.dart';
import '../services/auth_service.dart';
import '../services/call_notification_service.dart';
import '../services/connectivity_service.dart';
import '../services/database_service.dart';
import '../services/location_service.dart';
import '../utils/logger.dart';

/// Manages authentication state across the app.
class AuthProvider extends ChangeNotifier {
  final AuthService _authService = AuthService();
  final DatabaseService _databaseService = DatabaseService();
  final ConnectivityService _connectivity = ConnectivityService();

  User? _firebaseUser;
  UserModel? _userModel;
  bool _isLoading = false;
  String? _error;
  bool _isNewUser = false;

  User? get firebaseUser => _firebaseUser;
  UserModel? get userModel => _userModel;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get isLoggedIn => _firebaseUser != null;
  bool get isNewUser => _isNewUser;
  bool get hasCompletedProfile =>
      _userModel != null && 
      _userModel!.gender.isNotEmpty && 
      _userModel!.name.isNotEmpty && 
      _userModel!.age.isNotEmpty && 
      _userModel!.displayId.isNotEmpty;
  bool get isOffline => _connectivity.isOffline;

  AuthProvider() {
    _init();
  }

  void _init() {
    _authService.authStateChanges.listen((user) async {
      _firebaseUser = user;
      if (user != null) {
        if (!_isLoading) {
          await _loadUserModel(user);
        }
        _databaseService.setupPresence(user.uid);
        await _databaseService.setOnlineStatus(user.uid, true);
        await CallNotificationService().registerCurrentUser(user.uid);
      } else {
        _userModel = null;
      }
      notifyListeners();
    });
  }

  Future<void> _loadUserModel(User user) async {
    final uid = user.uid;
    _userModel = await _databaseService.getUser(uid);
    
    // If the profile is still missing, it might be a race condition with signup.
    // Wait a moment and check again.
    if (_userModel == null) {
      await Future.delayed(const Duration(seconds: 1));
      _userModel = await _databaseService.getUser(uid);
      
      // If it's still missing, auto-create a minimal profile.
      if (_userModel == null) {
        try {
          final now = DateTime.now().millisecondsSinceEpoch;
          final displayId = await _databaseService.generateUniqueDisplayId();
          final model = UserModel(
            uid: uid,
            name: (user.displayName ?? '').isNotEmpty ? user.displayName! : 'User',
            email: user.email ?? '',
            photoUrl: user.photoURL,
            createdAt: now,
            lastActive: now,
            displayId: displayId,
          );
          await _databaseService.saveUser(model);
          _userModel = model;
          logger.i('Auto-created missing profile for $uid');
        } catch (e) {
          logger.e('Failed to auto-create user profile', error: e);
        }
      }
    }
    
    // Legacy support: if user has no displayId, generate and save it now
    if (_userModel != null && _userModel!.displayId.isEmpty) {
      final newDisplayId = await _databaseService.generateUniqueDisplayId();
      await _databaseService.updateUser(uid, {'displayId': newDisplayId});
      _userModel = _userModel!.copyWith(displayId: newDisplayId);
      logger.i('Generated legacy UID for user $uid: $newDisplayId');
    }

    // Auto-detect and sync country/flag if missing or empty
    if (_userModel != null && (_userModel!.countryCode.isEmpty || _userModel!.country.isEmpty)) {
      Future.microtask(() async {
        try {
          final loc = await LocationService().getCountry();
          if (loc['countryCode'] != null && loc['countryCode']!.isNotEmpty) {
            await _databaseService.updateUser(uid, {
              'country': loc['country'] ?? 'Unknown Location',
              'countryCode': loc['countryCode'] ?? '',
            });
            _userModel = _userModel!.copyWith(
              country: loc['country'] ?? 'Unknown Location',
              countryCode: loc['countryCode'] ?? '',
            );
            notifyListeners();
            logger.i('Successfully auto-detected and synced country/flag for $uid: ${loc['countryCode']}');
          }
        } catch (e) {
          logger.w('Failed to auto-detect country on load', error: e);
        }
      });
    }
  }

  /// Reload the user model from Firebase.
  Future<void> refreshUser() async {
    if (_firebaseUser != null) {
      await _loadUserModel(_firebaseUser!);
      notifyListeners();
    }
  }

  void _setLoading(bool v) {
    _isLoading = v;
    notifyListeners();
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // SIGN UP
  // ---------------------------------------------------------------------------

  Future<bool> signUpWithEmail({
    required String name,
    required String email,
    required String password,
    required String age,
    required String gender,
  }) async {
    if (!await _connectivity.hasInternet()) {
      _error = 'You need internet to create an account.';
      notifyListeners();
      return false;
    }
    _setLoading(true);
    _error = null;
    try {
      final user = await _authService.signUpWithEmail(
        email: email,
        password: password,
      );
      if (user != null) {
        await _authService.updateDisplayName(name);

        final now = DateTime.now().millisecondsSinceEpoch;
        final displayId = await _databaseService.generateUniqueDisplayId();

        final newUser = UserModel(
          uid: user.uid,
          name: name,
          email: email,
          age: age,
          gender: gender,
          createdAt: now,
          lastActive: now,
          displayId: displayId,
        );
        await _databaseService.saveUser(newUser);
        _userModel = newUser;
        _firebaseUser = user;
        _isNewUser = true;
        _setLoading(false);
        return true;
      }
      _setLoading(false);
      return false;
    } on FirebaseAuthException catch (e) {
      _error = AuthService.getErrorMessage(e);
      _setLoading(false);
      return false;
    } catch (e) {
      _error = 'An unexpected error occurred.';
      logger.e('Sign up error', error: e);
      _setLoading(false);
      return false;
    }
  }

  // ---------------------------------------------------------------------------
  // SIGN IN
  // ---------------------------------------------------------------------------

  Future<bool> signInWithEmail({
    required String email,
    required String password,
  }) async {
    if (!await _connectivity.hasInternet()) {
      _error = 'You need internet to sign in.';
      notifyListeners();
      return false;
    }
    _setLoading(true);
    _error = null;
    try {
      final user = await _authService.signInWithEmail(
        email: email,
        password: password,
      );
      if (user != null) {
        await _loadUserModel(user);
        _firebaseUser = user;
        _isNewUser = false;
        _setLoading(false);
        return true;
      }
      _setLoading(false);
      return false;
    } on FirebaseAuthException catch (e) {
      _error = AuthService.getErrorMessage(e);
      _setLoading(false);
      return false;
    } catch (e) {
      _error = 'An unexpected error occurred.';
      logger.e('Sign in error', error: e);
      _setLoading(false);
      return false;
    }
  }

  // ---------------------------------------------------------------------------
  // GOOGLE SIGN IN
  // ---------------------------------------------------------------------------

  Future<bool> signInWithGoogle() async {
    if (!await _connectivity.hasInternet()) {
      _error = 'You need internet to sign in.';
      notifyListeners();
      return false;
    }
    _setLoading(true);
    _error = null;
    try {
      final user = await _authService.signInWithGoogle();
      if (user != null) {
        _firebaseUser = user;
        // Check if user exists in database
        final existing = await _databaseService.getUser(user.uid);
        if (existing == null) {
          // New Google user
          final now = DateTime.now().millisecondsSinceEpoch;
          final displayId = await _databaseService.generateUniqueDisplayId();

          final newUser = UserModel(
            uid: user.uid,
            name: user.displayName ?? 'User',
            email: user.email ?? '',
            photoUrl: user.photoURL,
            createdAt: now,
            lastActive: now,
            displayId: displayId,
          );
          await _databaseService.saveUser(newUser);
          _userModel = newUser;
          _isNewUser = true;
        } else {
          _userModel = existing;
          _isNewUser = false;
        }
        _setLoading(false);
        return true;
      }
      _setLoading(false);
      return false;
    } catch (e) {
      _error = 'Google sign-in failed. Please try again.';
      logger.e('Google sign-in error', error: e);
      _setLoading(false);
      return false;
    }
  }

  // ---------------------------------------------------------------------------
  // PASSWORD RESET
  // ---------------------------------------------------------------------------

  Future<bool> sendPasswordReset(String email) async {
    if (!await _connectivity.hasInternet()) {
      _error = 'You need internet to reset your password.';
      notifyListeners();
      return false;
    }
    _setLoading(true);
    _error = null;
    try {
      await _authService.sendPasswordResetEmail(email);
      _setLoading(false);
      return true;
    } on FirebaseAuthException catch (e) {
      _error = AuthService.getErrorMessage(e);
      _setLoading(false);
      return false;
    } catch (e) {
      _error = 'Failed to send reset email.';
      _setLoading(false);
      return false;
    }
  }

  // ---------------------------------------------------------------------------
  // PROFILE UPDATE
  // ---------------------------------------------------------------------------

  Future<void> updateProfile({
    String? name,
    String? age,
  }) async {
    if (_firebaseUser == null || _userModel == null) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    final recentEdits = _userModel!.profileEditTimestamps
        .where((value) => now - value < const Duration(days: 7).inMilliseconds)
        .toList();
    if (recentEdits.length >= 2) {
      _error = 'You can edit your profile only twice in 7 days.';
      notifyListeners();
      return;
    }
    _setLoading(true);
    try {
      final Map<String, dynamic> updates = {};
      if (name != null) updates['name'] = name;
      if (age != null) updates['age'] = age;
      updates['profileEditTimestamps'] = [...recentEdits, now];

      await _databaseService.updateUser(_firebaseUser!.uid, updates);
      
      _userModel = _userModel!.copyWith(
        name: name,
        age: age,
        profileEditTimestamps: [...recentEdits, now],
      );
      _isNewUser = false;
      _error = null;
    } catch (e) {
      logger.e('Failed to update profile', error: e);
    }
    _setLoading(false);
  }

  // ---------------------------------------------------------------------------
  // SIGN OUT
  // ---------------------------------------------------------------------------

  Future<bool> signOut() async {
    if (!await _connectivity.hasInternet()) {
      _error = 'You are not able to log out without internet.';
      notifyListeners();
      return false;
    }
    if (_firebaseUser != null) {
      await _databaseService.setOnlineStatus(_firebaseUser!.uid, false);
      await _databaseService.leaveSearchQueue(_firebaseUser!.uid);
    }
    await _authService.signOut();
    _firebaseUser = null;
    _userModel = null;
    _isNewUser = false;
    notifyListeners();
    return true;
  }
}
