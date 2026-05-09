// coverage:ignore-file
import 'package:flutter/widgets.dart';
import '../../vault/data/vault_repository.dart' show BacklinkEntry;
import '../../vault/domain/vault_models.dart';

typedef WikilinkTapCallback = void Function(String target);
typedef BacklinkTapCallback = void Function(BacklinkEntry backlink);

/// Builds a markdown content view appropriate for the current platform.
/// On web: uses HtmlElementView (native DOM scroll/select/copy).
/// On native: uses flutter_markdown MarkdownBody.
Widget buildMarkdownView({
  required String markdown,
  required List<Note> notes,
  required WikilinkTapCallback onWikilinkTap,
  List<BacklinkEntry> backlinks = const [],
  BacklinkTapCallback? onBacklinkTap,
  Future<void> Function()? onRefresh,
}) => throw UnsupportedError('Platform not supported');
