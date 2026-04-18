import 'dart:js_interop';

import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

import 'markdown_editor_stub.dart';

export 'markdown_editor_stub.dart';

const _editorId = '__obsidrive_editor__';

@override
Widget buildMarkdownEditor({
  required String initialContent,
  required SavedCallback onSaved,
  required VoidCallback onCancelled,
}) {
  return _HtmlMarkdownEditor(
    initialContent: initialContent,
    onSaved: onSaved,
    onCancelled: onCancelled,
  );
}

class _HtmlMarkdownEditor extends StatefulWidget {
  const _HtmlMarkdownEditor({
    required this.initialContent,
    required this.onSaved,
    required this.onCancelled,
  });

  final String initialContent;
  final SavedCallback onSaved;
  final VoidCallback onCancelled;

  @override
  State<_HtmlMarkdownEditor> createState() => _HtmlMarkdownEditorState();
}

class _HtmlMarkdownEditorState extends State<_HtmlMarkdownEditor> {
  web.HTMLDivElement? _wrapper;
  web.HTMLTextAreaElement? _textarea;
  web.HTMLButtonElement? _saveBtn;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _createElement();
  }

  @override
  Widget build(BuildContext context) {
    return const SizedBox.shrink();
  }

  void _createElement() {
    final wrapper = web.document.createElement('div') as web.HTMLDivElement;
    wrapper.id = _editorId;
    final ws = wrapper.style;
    ws.position = 'fixed';
    ws.top = '0';
    ws.left = '0';
    ws.width = '100%';
    ws.height = '100%';
    ws.zIndex = '200';
    ws.backgroundColor = '#ffffff';
    ws.display = 'flex';
    ws.flexDirection = 'column';

    // --- Top bar ---
    final topBar = web.document.createElement('div') as web.HTMLDivElement;
    final tbs = topBar.style;
    tbs.height = '56px';
    tbs.minHeight = '56px';
    tbs.display = 'flex';
    tbs.alignItems = 'center';
    tbs.justifyContent = 'space-between';
    tbs.padding = '0 8px 0 16px';
    tbs.borderBottom = '1px solid #e5e7eb';
    tbs.boxSizing = 'border-box';
    tbs.backgroundColor = '#ffffff';

    // Title
    final title = web.document.createElement('span') as web.HTMLSpanElement;
    title.textContent = '편집';
    final ts = title.style;
    ts.fontSize = '18px';
    ts.fontWeight = '600';

    // Button group
    final btnGroup = web.document.createElement('div') as web.HTMLDivElement;
    btnGroup.style.display = 'flex';
    btnGroup.style.gap = '8px';

    // Close button
    final closeBtn = _createButton('닫기', () {
      if (!_isSaving) widget.onCancelled();
    });

    // Save button
    final saveBtn = _createButton('저장', _handleSave, primary: true);
    _saveBtn = saveBtn;

    btnGroup.append(closeBtn);
    btnGroup.append(saveBtn);
    topBar.append(title);
    topBar.append(btnGroup);

    // --- Textarea ---
    final textarea =
        web.document.createElement('textarea') as web.HTMLTextAreaElement;
    textarea.value = widget.initialContent;
    final tas = textarea.style;
    tas.flex = '1';
    tas.width = '100%';
    tas.border = 'none';
    tas.padding = '16px';
    tas.fontFamily = "'SF Mono', 'Fira Code', 'Consolas', monospace";
    tas.fontSize = '14px';
    tas.lineHeight = '1.6';
    tas.resize = 'none';
    tas.outline = 'none';
    tas.boxSizing = 'border-box';
    tas.setProperty('-webkit-user-select', 'text');
    tas.setProperty('user-select', 'text');

    wrapper.append(topBar);
    wrapper.append(textarea);
    web.document.body!.appendChild(wrapper);

    _textarea = textarea;
    _wrapper = wrapper;
  }

  void _setSaving(bool saving) {
    _isSaving = saving;
    final btn = _saveBtn;
    if (btn == null) return;

    if (saving) {
      btn.textContent = '저장 중...';
      btn.disabled = true;
      btn.style.opacity = '0.7';
      btn.style.cursor = 'not-allowed';
    } else {
      btn.textContent = '저장';
      btn.disabled = false;
      btn.style.opacity = '1';
      btn.style.cursor = 'pointer';
    }
  }

  void _handleSave() async {
    if (_isSaving) return;
    _setSaving(true);

    try {
      await widget.onSaved(_textarea?.value ?? widget.initialContent);
    } catch (_) {
      // onSaved handles the error (shows snackbar) and closes editor on success
      _setSaving(false);
    }
  }

  web.HTMLButtonElement _createButton(
    String label,
    VoidCallback onTap, {
    bool primary = false,
  }) {
    final btn = web.document.createElement('button') as web.HTMLButtonElement;
    btn.textContent = label;
    final s = btn.style;
    s.padding = '8px 16px';
    s.borderRadius = '8px';
    s.border = 'none';
    s.cursor = 'pointer';
    s.fontSize = '14px';
    s.fontWeight = '600';
    s.transition = 'opacity 0.2s';

    if (primary) {
      s.backgroundColor = '#1a73e8';
      s.color = '#ffffff';
    } else {
      s.backgroundColor = '#f3f4f6';
      s.color = '#374151';
    }

    btn.addEventListener(
      'click',
      ((web.Event _) {
        onTap();
      }).toJS,
    );
    return btn;
  }

  @override
  void dispose() {
    _wrapper?.remove();
    _wrapper = null;
    _textarea = null;
    _saveBtn = null;
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant _HtmlMarkdownEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialContent != oldWidget.initialContent &&
        _textarea != null) {
      _textarea!.value = widget.initialContent;
    }
  }
}
