import '../features/vault/domain/vault_models.dart';

String parseFrontmatter(String markdown) {
  final normalized = markdown.replaceFirst('\uFEFF', '');
  if (!normalized.startsWith('---\n') && !normalized.startsWith('---\r\n')) {
    return markdown;
  }

  final match = RegExp(
    r'^---\r?\n([\s\S]*?)\r?\n---[ \t]*\r?\n?',
  ).firstMatch(normalized);
  if (match == null) {
    return markdown;
  }

  return normalized.substring(match.end);
}

List<Wikilink> parseWikilinks(String markdown) {
  final matches = RegExp(r'\[\[([^\]\r\n]+)\]\]').allMatches(markdown);
  return <Wikilink>[
    for (final match in matches) _parseWikilink(match.group(1)!.trim()),
  ].where((link) => link.target.isNotEmpty).toList(growable: false);
}

Note? resolveInVault(Wikilink link, List<Note> notes) {
  final targetPath = _normalizedMarkdownPath(link.target);
  if (link.path != null) {
    for (final note in notes) {
      if (_normalizePath(note.filePath) == targetPath) {
        return note;
      }
    }
    return null;
  }

  for (final note in notes) {
    if (_normalizeTitle(note.title) == _normalizeTitle(link.title)) {
      return note;
    }
  }

  for (final note in notes) {
    if (_normalizeTitle(_titleFromPath(note.filePath)) ==
        _normalizeTitle(link.title)) {
      return note;
    }
  }

  return null;
}

Wikilink _parseWikilink(String raw) {
  final parts = raw.split('|');
  final target = parts.first.trim();
  final alias = parts.length > 1 ? parts.sublist(1).join('|').trim() : null;
  final pathSeparator = target.lastIndexOf('/');
  final path = pathSeparator == -1 ? null : target.substring(0, pathSeparator);
  final title = pathSeparator == -1
      ? _stripMarkdownExtension(target)
      : _stripMarkdownExtension(target.substring(pathSeparator + 1));

  return Wikilink(
    target: target,
    title: title,
    path: path,
    alias: alias == null || alias.isEmpty ? null : alias,
  );
}

String _normalizedMarkdownPath(String target) {
  final normalized = _normalizePath(target);
  if (normalized.toLowerCase().endsWith('.md')) {
    return normalized;
  }

  return '$normalized.md';
}

String _normalizePath(String value) {
  return value.trim().replaceAll(RegExp(r'/+'), '/').toLowerCase();
}

String _normalizeTitle(String value) {
  return _stripMarkdownExtension(value).trim().toLowerCase();
}

String _titleFromPath(String path) {
  final normalized = path.replaceAll('\\', '/');
  final separator = normalized.lastIndexOf('/');
  return separator == -1 ? normalized : normalized.substring(separator + 1);
}

String _stripMarkdownExtension(String value) {
  if (value.toLowerCase().endsWith('.md')) {
    return value.substring(0, value.length - 3);
  }

  return value;
}

class Wikilink {
  const Wikilink({
    required this.target,
    required this.title,
    this.path,
    this.alias,
  });

  final String target;
  final String title;
  final String? path;
  final String? alias;

  String get displayText => alias ?? title;

  @override
  bool operator ==(Object other) {
    return other is Wikilink &&
        other.target == target &&
        other.title == title &&
        other.path == path &&
        other.alias == alias;
  }

  @override
  int get hashCode => Object.hash(target, title, path, alias);

  @override
  String toString() {
    return 'Wikilink(target: $target, title: $title, path: $path, alias: $alias)';
  }
}
