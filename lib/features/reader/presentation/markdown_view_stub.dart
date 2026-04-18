import 'package:flutter/widgets.dart';
import '../../vault/domain/vault_models.dart';

typedef WikilinkTapCallback = void Function(String target);

/// Builds a markdown content view appropriate for the current platform.
/// On web: uses HtmlElementView (native DOM scroll/select/copy).
/// On native: uses flutter_markdown MarkdownBody.
Widget buildMarkdownView({
  required String markdown,
  required List<Note> notes,
  required WikilinkTapCallback onWikilinkTap,
}) => throw UnsupportedError('Platform not supported');
