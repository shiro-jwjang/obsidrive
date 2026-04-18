import 'package:flutter/material.dart';

import 'markdown_editor_stub.dart';

export 'markdown_editor_stub.dart';

@override
Widget buildMarkdownEditor({
  required String initialContent,
  required SavedCallback onSaved,
  required VoidCallback onCancelled,
}) {
  return _NativeMarkdownEditor(
    initialContent: initialContent,
    onSaved: onSaved,
    onCancelled: onCancelled,
  );
}

class _NativeMarkdownEditor extends StatefulWidget {
  const _NativeMarkdownEditor({
    required this.initialContent,
    required this.onSaved,
    required this.onCancelled,
  });

  final String initialContent;
  final SavedCallback onSaved;
  final VoidCallback onCancelled;

  @override
  State<_NativeMarkdownEditor> createState() => _NativeMarkdownEditorState();
}

class _NativeMarkdownEditorState extends State<_NativeMarkdownEditor> {
  late final TextEditingController _controller;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialContent);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant _NativeMarkdownEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialContent != oldWidget.initialContent) {
      _controller.text = widget.initialContent;
    }
  }

  Future<void> _save() async {
    setState(() => _isSaving = true);
    try {
      await widget.onSaved(_controller.text);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            if (_isSaving)
              const Padding(
                padding: EdgeInsets.only(right: 16),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            else
              TextButton(
                onPressed: _save,
                child: const Text(
                  '저장',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            TextButton(
              onPressed: () => widget.onCancelled(),
              child: const Text('닫기'),
            ),
          ],
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _controller,
              maxLines: null,
              expands: true,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 14),
              decoration: const InputDecoration(
                border: InputBorder.none,
                hintText: '마크다운을 입력하세요',
              ),
            ),
          ),
        ),
      ],
    );
  }
}
