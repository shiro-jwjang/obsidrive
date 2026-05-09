// coverage:ignore-file
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
// ignore: depend_on_referenced_packages
import 'package:markdown/markdown.dart' as md;

import '../../../core/markdown_parser.dart';
import '../../vault/data/vault_repository.dart' show BacklinkEntry;
import '../../vault/domain/vault_models.dart';
import 'markdown_view_stub.dart';
import 'wikilink_span.dart';

export 'markdown_view_stub.dart';

@override
Widget buildMarkdownView({
  required String markdown,
  required List<Note> notes,
  required WikilinkTapCallback onWikilinkTap,
  List<BacklinkEntry> backlinks = const [],
  BacklinkTapCallback? onBacklinkTap,
  Future<void> Function()? onRefresh,
}) {
  return SingleChildScrollView(
    physics: const BouncingScrollPhysics(),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        MarkdownBody(
          data: markdown,
          selectable: true,
          extensionSet: md.ExtensionSet.gitHubFlavored,
          inlineSyntaxes: <md.InlineSyntax>[WikilinkInlineSyntax()],
          builders: <String, MarkdownElementBuilder>{
            'wikilink': WikilinkElementBuilder(
              notes: notes,
              onOpen: onWikilinkTap,
            ),
            'pre': _CodeBlockBuilder(),
          },
          paddingBuilders: const <String, MarkdownPaddingBuilder>{},
        ),
        if (backlinks.isNotEmpty) ...[
          const Divider(height: 32, thickness: 1),
          _BacklinksSection(backlinks: backlinks, onBacklinkTap: onBacklinkTap),
        ],
      ],
    ),
  );
}

class WikilinkInlineSyntax extends md.InlineSyntax {
  WikilinkInlineSyntax() : super(r'\[\[[^\]\r\n]+\]\]', startCharacter: 91);

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    final link = parseWikilinks(match.group(0)!).single;
    final element = md.Element.text('wikilink', link.displayText)
      ..attributes['target'] = link.target
      ..attributes['display'] = link.displayText;
    parser.addNode(element);
    return true;
  }
}

class WikilinkElementBuilder extends MarkdownElementBuilder {
  WikilinkElementBuilder({required this.notes, required this.onOpen});

  final List<Note> notes;
  final void Function(String target) onOpen;

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    final target = element.attributes['target'] ?? element.textContent;
    final display = element.attributes['display'] ?? element.textContent;
    final link = parseWikilinks('[[$target]]').single;
    final exists = resolveInVault(link, notes) != null;

    return WikilinkSpan(
      text: display,
      exists: exists,
      onTap: () => onOpen(target),
    );
  }
}

class _CodeBlockBuilder extends MarkdownElementBuilder {
  @override
  bool isBlockElement() => true;

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: SelectableText(
        element.textContent,
        style: theme.textTheme.bodyMedium?.copyWith(
          fontFamily: 'monospace',
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _BacklinksSection extends StatelessWidget {
  const _BacklinksSection({required this.backlinks, this.onBacklinkTap});

  final List<BacklinkEntry> backlinks;
  final BacklinkTapCallback? onBacklinkTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              '백링크 (${backlinks.length})',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          ...backlinks.map(
            (entry) => ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                Icons.link,
                size: 18,
                color: theme.colorScheme.primary,
              ),
              title: Text(
                entry.sourceTitle,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.primary,
                ),
              ),
              subtitle: Text(
                entry.sourceFilePath,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              onTap: onBacklinkTap != null ? () => onBacklinkTap!(entry) : null,
            ),
          ),
        ],
      ),
    );
  }
}
