import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/markdown_parser.dart';
import '../../vault/domain/vault_models.dart';
import '../domain/reader_provider.dart';
import 'markdown_editor.dart';
import 'markdown_view.dart';

class ReaderScreen extends ConsumerStatefulWidget {
  const ReaderScreen({super.key});

  @override
  ConsumerState<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends ConsumerState<ReaderScreen> {
  bool _isEditing = false;
  bool _isSaving = false;
  late final TextEditingController _titleController;
  late final FocusNode _titleFocusNode;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController();
    _titleFocusNode = FocusNode();
  }

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

  Future<void> _saveContent(Note note, String content) async {
    setState(() => _isSaving = true);
    try {
      final repository = ref.read(noteContentRepositoryProvider);
      var savedNote = note;
      final newTitle = _titleController.text.trim();
      if (newTitle != note.title) {
        savedNote = await repository.renameNote(note, newTitle);
        ref.read(currentNoteProvider.notifier).state = savedNote;
      }

      await repository.saveContent(savedNote, content);
      ref.invalidate(noteContentProvider(note));
      ref.invalidate(noteContentProvider(savedNote));
      ref.invalidate(vaultWikilinksProvider(savedNote.vaultId));
      setState(() {
        _isEditing = false;
        _isSaving = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('저장했습니다')));
      }
    } catch (e) {
      setState(() => _isSaving = false);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('저장 실패: $e')));
      }
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _titleFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final routeNote = ModalRoute.of(context)?.settings.arguments;
    final currentNote = ref.watch(currentNoteProvider);
    final note = routeNote is Note && currentNote?.id != routeNote.id
        ? routeNote
        : currentNote ?? (routeNote is Note ? routeNote : null);

    if (note == null) {
      return const Scaffold(body: Center(child: Text('열 노트를 선택해 주세요.')));
    }

    final content = ref.watch(noteContentProvider(note));
    final vaultNotes = ref.watch(vaultWikilinksProvider(note.vaultId));

    return Scaffold(
      appBar: AppBar(
        title: _isEditing ? _buildTitleField(context) : Text(note.title),
        actions: [
          if (_isEditing) ...[
            if (_isSaving)
              const Padding(
                padding: EdgeInsets.only(right: 16),
                child: Center(
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              ),
          ] else ...[
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              tooltip: '편집',
              onPressed: content.hasValue && content.value != null
                  ? () => _startEditing(note)
                  : null,
            ),
          ],
        ],
      ),
      body: _isEditing
          ? content.when(
              data: (markdown) => buildMarkdownEditor(
                initialContent: markdown,
                onSaved: (newContent) => _saveContent(note, newContent),
                onCancelled: () {
                  setState(() => _isEditing = false);
                },
              ),
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('오류: $e')),
            )
          : content.when(
              data: (markdown) {
                final notes = vaultNotes.value ?? const <Note>[];
                final rendered = parseFrontmatter(markdown);
                if (rendered.trim().isEmpty) {
                  return const Center(child: Text('빈 노트'));
                }

                return buildMarkdownView(
                  markdown: rendered,
                  notes: notes,
                  onWikilinkTap: (target) =>
                      _openWikilink(context, ref, note, target),
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

  void _startEditing(Note note) {
    _titleController.text = note.title;
    _titleController.selection = TextSelection(
      baseOffset: 0,
      extentOffset: note.title.length,
    );
    setState(() => _isEditing = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _titleFocusNode.requestFocus();
      _titleController.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _titleController.text.length,
      );
    });
  }

  Widget _buildTitleField(BuildContext context) {
    final theme = Theme.of(context);
    final titleStyle =
        theme.appBarTheme.titleTextStyle ?? theme.textTheme.titleLarge;

    return TextField(
      controller: _titleController,
      focusNode: _titleFocusNode,
      maxLength: 255,
      style: titleStyle,
      decoration: const InputDecoration(
        border: UnderlineInputBorder(),
        enabledBorder: UnderlineInputBorder(),
        focusedBorder: UnderlineInputBorder(),
        counterText: '',
        isDense: true,
      ),
      textInputAction: TextInputAction.done,
      enabled: !_isSaving,
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

    // Just update state — no route push, so DOM div is reused
    ref.read(currentNoteProvider.notifier).state = target;
  }
}
