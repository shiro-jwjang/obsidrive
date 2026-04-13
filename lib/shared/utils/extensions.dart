import 'package:flutter/material.dart';

/// Convenience extensions on [BuildContext].
extension ContextExtensions on BuildContext {
  /// Short-hand for `Theme.of(this)`.
  ThemeData get theme => Theme.of(this);

  /// Short-hand for `MediaQuery.sizeOf(this)`.
  Size get screenSize => MediaQuery.sizeOf(this);

  /// Short-hand for `ScaffoldMessenger.of(this)`.
  ScaffoldMessengerState get scaffoldMessenger => ScaffoldMessenger.of(this);
}

/// Convenience extensions on [String].
extension StringExtensions on String {
  /// Whether this string is a valid-looking markdown file path.
  bool get isMarkdownPath => toLowerCase().endsWith('.md');

  /// Capitalize the first letter.
  String get capitalized {
    if (isEmpty) return this;
    return '${this[0].toUpperCase()}${substring(1)}';
  }
}
