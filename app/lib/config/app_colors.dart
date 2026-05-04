import 'package:flutter/material.dart';

/// Zuumeet solid-color-only design system.
/// NO gradients anywhere. All colors are flat / solid.
class AppColors {
  AppColors._();

  // Primary Brand
  static const primary = Color(0xFF1A73E8);
  static const primaryDark = Color(0xFF1557B0);

  // Secondary
  static const secondary = Color(0xFF34A853);
  static const accent = Color(0xFF00BFA5);

  // Backgrounds
  static const background = Color(0xFFFFFFFF);
  static const backgroundSecondary = Color(0xFFF8F9FA);
  static const surface = Color(0xFFFFFFFF);

  // Text
  static const textPrimary = Color(0xFF202124);
  static const textSecondary = Color(0xFF5F6368);
  static const textLight = Color(0xFF9AA0A6);

  // Status
  static const error = Color(0xFFEA4335);
  static const warning = Color(0xFFFBBC04);
  static const success = Color(0xFF34A853);

  // Borders & Dividers
  static const border = Color(0xFFE8EAED);
  static const divider = Color(0xFFDADCE0);

  // Video Call
  static const callBackground = Color(0xFF1A1A1A);
  static const overlayDark = Color(0x80000000);
}
