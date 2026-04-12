import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// ignore: depend_on_referenced_packages
import 'package:markdown/markdown.dart' as md;

import '../../../core/markdown_parser.dart';
import '../../vault/domain/vault_models.dart';
import '../domain/reader_provider.dart';
import 'wikilink_span.dart';

class ReaderScreen extends ConsumerStatefulWidget {
  const ReaderScreen({super.key});

  @override
  ConsumerState<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends ConsumerState<ReaderScreen> {
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final routeNote = ModalRoute.of(context)?.settings.arguments;
    if (routeNote is Note) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ref.read(currentNoteProvider.notifier).state = routeNote;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final routeNote = ModalRoute.of(context)?.settings.arguments;
    final note = routeNote is Note ? routeNote : ref.watch(currentNoteProvider);

    if (note == null) {
      return const Scaffold(body: Center(child: Text('열 노트를 선택해 주세요.')));
    }

    final content = ref.watch(noteContentProvider(note));
    final vaultNotes = ref.watch(vaultWikilinksProvider(note.vaultId));

    return Scaffold(
      appBar: AppBar(title: Text(note.title)),
      body: content.when(
        data: (markdown) {
          final notes = vaultNotes.value ?? const <Note>[];
          final rendered = parseFrontmatter(markdown);
          if (rendered.trim().isEmpty) {
            return const Center(child: Text('빈 노트'));
          }

          return Markdown(
            data: rendered,
            selectable: true,
            extensionSet: md.ExtensionSet.gitHubFlavored,
            inlineSyntaxes: <md.InlineSyntax>[WikilinkInlineSyntax()],
            builders: <String, MarkdownElementBuilder>{
              'wikilink': WikilinkElementBuilder(
                notes: notes,
                onOpen: (target) => _openWikilink(context, ref, note, target),
              ),
              'pre': _CodeBlockBuilder(),
            },
            paddingBuilders: const <String, MarkdownPaddingBuilder>{},
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('노트를 불러오지 못했습니다.\n$error'),
          ),
        ),
      ),
    );
  }

  void _openWikilink(
    BuildContext context,
    WidgetRef ref,
    Note sourceNote,
    String rawTarget,
  ) {
    final link = parseWikilinks('[[$rawTarget]]').single;
    final notes =
        ref.read(vaultWikilinksProvider(sourceNote.vaultId)).value ??
        const <Note>[];
    final target = resolveInVault(link, notes);
    if (target == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('노트를 찾을 수 없습니다')));
      return;
    }

    ref.read(currentNoteProvider.notifier).state = target;
    Navigator.of(context).pushNamed('/reader', arguments: target);
  }
}

class WikilinkInlineSyntax extends md.InlineSyntax {
  WikilinkInlineSyntax() : super(r'\[\[([^\]\r\n]+)\]\]', startCharacter: 91);

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
