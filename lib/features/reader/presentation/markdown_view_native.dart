import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
// ignore: depend_on_referenced_packages
import 'package:markdown/markdown.dart' as md;

import '../../../core/markdown_parser.dart';
import '../../vault/domain/vault_models.dart';
import 'markdown_view_stub.dart';
import 'wikilink_span.dart';

export 'markdown_view_stub.dart';

@override
Widget buildMarkdownView({
  required String markdown,
  required List<Note> notes,
  required WikilinkTapCallback onWikilinkTap,
}) {
  return SingleChildScrollView(
    physics: const BouncingScrollPhysics(),
    child: MarkdownBody(
      data: markdown,
      selectable: true,
      extensionSet: md.ExtensionSet.gitHubFlavored,
      inlineSyntaxes: <md.InlineSyntax>[WikilinkInlineSyntax()],
      builders: <String, MarkdownElementBuilder>{
        'wikilink': WikilinkElementBuilder(notes: notes, onOpen: onWikilinkTap),
        'pre': _CodeBlockBuilder(),
      },
      paddingBuilders: const <String, MarkdownPaddingBuilder>{},
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
