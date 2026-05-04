import 'package:flutter/material.dart';
import '../models/user_model.dart';
import '../services/database_service.dart';

class UserProvider extends ChangeNotifier {
  final DatabaseService _db = DatabaseService();
  UserModel? _profile;
  bool _isLoading = false;

  UserModel? get profile => _profile;
  bool get isLoading => _isLoading;

  Future<void> loadProfile(String uid) async {
    _isLoading = true;
    notifyListeners();
    _profile = await _db.getUser(uid);
    _isLoading = false;
    notifyListeners();
  }

  void updateProfileLocal(UserModel user) {
    _profile = user;
    notifyListeners();
  }

  Future<void> updateAvatarAndFrame(String uid, String avatarUrl, String frameId) async {
    try {
      await _db.updateUser(uid, {
        'avatarUrl': avatarUrl,
        'frameId': frameId,
      });
      if (_profile != null) {
        _profile = _profile!.copyWith(
          avatarUrl: avatarUrl,
          frameId: frameId,
        );
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Failed to update avatar/frame: $e');
    }
  }
}
