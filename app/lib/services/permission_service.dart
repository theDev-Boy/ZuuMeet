import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import '../utils/logger.dart';

/// Centralized permission handling for camera, microphone and location.
class PermissionService {
  /// Request camera and microphone permissions. Returns true if both granted.
  Future<bool> requestCameraAndMic() async {
    final statuses = await [
      Permission.camera,
      Permission.microphone,
    ].request();

    final cameraGranted = statuses[Permission.camera]?.isGranted ?? false;
    final micGranted = statuses[Permission.microphone]?.isGranted ?? false;

    if (!cameraGranted || !micGranted) {
      logger.w('Camera/Mic permissions not fully granted: '
          'camera=$cameraGranted, mic=$micGranted');
    }

    return cameraGranted && micGranted;
  }

  /// Request location permission. Returns true if granted.
  Future<bool> requestLocation() async {
    final status = await Permission.location.request();
    return status.isGranted;
  }

  /// Check if camera and mic are granted.
  Future<bool> hasCameraAndMic() async {
    final camera = await Permission.camera.isGranted;
    final mic = await Permission.microphone.isGranted;
    return camera && mic;
  }

  /// Show a rationale dialog then request permission.
  Future<bool> requestWithRationale(
    BuildContext context, {
    required String title,
    required String message,
    required Future<bool> Function() requestFn,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Allow'),
          ),
        ],
      ),
    );

    if (result == true) {
      return await requestFn();
    }
    return false;
  }

  /// Open app settings (for permanently denied permissions).
  Future<void> openSettings() async {
    await openAppSettings();
  }
}
