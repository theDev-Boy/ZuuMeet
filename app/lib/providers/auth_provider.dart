import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'dart:math';
import '../models/user_model.dart';
import '../services/auth_service.dart';
import '../services/call_notification_service.dart';
import '../services/database_service.dart';
import '../utils/logger.dart';

/// Manages authentication state across the app.
class AuthProvider extends ChangeNotifier {
  final AuthService _authService = AuthService();
  final DatabaseService _databaseService = DatabaseService();

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

  AuthProvider() {
    _init();
  }

  void _init() {
    _authService.authStateChanges.listen((user) async {
      _firebaseUser = user;
      if (user != null) {
        await _loadUserModel(user.uid);
        _databaseService.setupPresence(user.uid);
        await _databaseService.setOnlineStatus(user.uid, true);
        await CallNotificationService().registerCurrentUser(user.uid);
      } else {
        _userModel = null;
      }
      notifyListeners();
    });
  }

  Future<void> _loadUserModel(String uid) async {
    _userModel = await _databaseService.getUser(uid);
    
    // Legacy support: if user has no displayId, generate and save it now
    if (_userModel != null && _userModel!.displayId.isEmpty) {
      final newDisplayId = (Random().nextInt(900000) + 100000).toString();
      await _databaseService.updateUser(uid, {'displayId': newDisplayId});
      _userModel = _userModel!.copyWith(displayId: newDisplayId);
      logger.i('Generated legacy UID for user $uid: $newDisplayId');
    }
  }

  /// Reload the user model from Firebase.
  Future<void> refreshUser() async {
    if (_firebaseUser != null) {
      await _loadUserModel(_firebaseUser!.uid);
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
        final displayId = (Random().nextInt(900000) + 100000).toString(); // 100000 to 999999

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
    _setLoading(true);
    _error = null;
    try {
      final user = await _authService.signInWithEmail(
        email: email,
        password: password,
      );
      if (user != null) {
        await _loadUserModel(user.uid);
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
          final displayId = (Random().nextInt(900000) + 100000).toString();

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
    String? gender,
    String? age,
    String? country,
    String? countryCode,
    String? avatarUrl,
  }) async {
    if (_firebaseUser == null || _userModel == null) return;
    _setLoading(true);
    try {
      final Map<String, dynamic> updates = {};
      if (name != null) updates['name'] = name;
      if (gender != null) updates['gender'] = gender;
      if (age != null) updates['age'] = age;
      if (country != null) updates['country'] = country;
      if (countryCode != null) updates['countryCode'] = countryCode;
      if (avatarUrl != null) updates['avatarUrl'] = avatarUrl;

      await _databaseService.updateUser(_firebaseUser!.uid, updates);
      
      _userModel = _userModel!.copyWith(
        name: name,
        gender: gender,
        age: age,
        country: country,
        countryCode: countryCode,
        avatarUrl: avatarUrl,
      );
      _isNewUser = false;
    } catch (e) {
      logger.e('Failed to update profile', error: e);
    }
    _setLoading(false);
  }

  // ---------------------------------------------------------------------------
  // SIGN OUT
  // ---------------------------------------------------------------------------

  Future<void> signOut() async {
    if (_firebaseUser != null) {
      await _databaseService.setOnlineStatus(_firebaseUser!.uid, false);
      await _databaseService.leaveSearchQueue(_firebaseUser!.uid);
    }
    await _authService.signOut();
    _firebaseUser = null;
    _userModel = null;
    _isNewUser = false;
    notifyListeners();
  }
}
