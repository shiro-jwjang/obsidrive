import 'package:flutter/widgets.dart';

typedef SavedCallback = Future<void> Function(String content);

/// Builds a markdown editor appropriate for the current platform.
/// On web: uses a native DOM <textarea>.
/// On native: uses Flutter TextField.
Widget buildMarkdownEditor({
  required String initialContent,
  required SavedCallback onSaved,
  required VoidCallback onCancelled,
}) => throw UnsupportedError('Platform not supported');
