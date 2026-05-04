import 'package:flutter/material.dart';

extension ContextExtensions on BuildContext {
  /// Easy access to MediaQuery size
  Size get screenSize => MediaQuery.sizeOf(this);

  /// Easy access to ScaffoldMessenger
  void showSnackBar(String message) {
    ScaffoldMessenger.of(this).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  /// Theme access
  ThemeData get theme => Theme.of(this);
  TextTheme get textTheme => theme.textTheme;
}

extension StringExtensions on String {
  /// Simple email validation
  bool get isValidEmail => RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(this);
  
  /// Capitalize first letter
  String get capitalize => isNotEmpty ? "${this[0].toUpperCase()}${substring(1)}" : "";
}
