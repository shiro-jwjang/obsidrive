import 'dart:js_interop';

import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

export 'search_input_stub.dart';

const _searchOverlayId = '__obsidrive_search_input__';
const _searchStyleId = '__obsidrive_search_input_style__';

Widget buildSearchInput({
  required bool isVisible,
  required ValueChanged<String> onChanged,
  required VoidCallback onClosed,
  TextEditingController? controller,
  FocusNode? focusNode,
}) {
  return _HtmlSearchInput(
    isVisible: isVisible,
    onChanged: onChanged,
    onClosed: onClosed,
    controller: controller,
  );
}

class _HtmlSearchInput extends StatefulWidget {
  const _HtmlSearchInput({
    required this.isVisible,
    required this.onChanged,
    required this.onClosed,
    this.controller,
  });

  final bool isVisible;
  final ValueChanged<String> onChanged;
  final VoidCallback onClosed;
  final TextEditingController? controller;

  @override
  State<_HtmlSearchInput> createState() => _HtmlSearchInputState();
}

class _HtmlSearchInputState extends State<_HtmlSearchInput> {
  web.HTMLDivElement? _wrapper;
  web.HTMLInputElement? _input;

  @override
  void initState() {
    super.initState();
    _syncOverlay();
  }

  @override
  void didUpdateWidget(covariant _HtmlSearchInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncOverlay();

    final input = _input;
    final controller = widget.controller;
    if (input != null && controller != null && input.value != controller.text) {
      input.value = controller.text;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isVisible) {
      return const SizedBox.shrink();
    }

    return const SizedBox(height: 64);
  }

  void _syncOverlay() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      if (widget.isVisible) {
        _ensureStyle();
        _ensureElement();
      } else {
        _removeElement();
      }
    });
  }

  void _ensureStyle() {
    if (web.document.getElementById(_searchStyleId) != null) return;

    final style = web.document.createElement('style') as web.HTMLStyleElement;
    style.id = _searchStyleId;
    style.textContent =
        '''
#$_searchOverlayId {
  position: fixed;
  top: 56px;
  left: 0;
  right: 0;
  z-index: 100;
  box-sizing: border-box;
  padding: 8px 16px;
  background: transparent;
}
#$_searchOverlayId .search-shell {
  display: flex;
  align-items: center;
  gap: 8px;
  width: 100%;
  box-sizing: border-box;
  border: 1px solid #d0d5dd;
  border-radius: 12px;
  background: #f5f5f5;
  padding: 10px 14px;
  box-shadow: 0 1px 2px rgba(16, 24, 40, 0.06);
}
#$_searchOverlayId .search-icon {
  font-size: 16px;
  line-height: 1;
  color: #667085;
  user-select: none;
}
#$_searchOverlayId input[type="search"] {
  -webkit-appearance: none;
  appearance: none;
  width: 100%;
  border: none;
  outline: none;
  background: transparent;
  color: #101828;
  font-size: 16px;
  line-height: 1.4;
  padding: 0;
  margin: 0;
}
#$_searchOverlayId input[type="search"]::placeholder {
  color: #667085;
}
''';
    web.document.head?.appendChild(style);
  }

  void _ensureElement() {
    final body = web.document.body;
    if (body == null) return;

    if (_wrapper == null) {
      final wrapper = web.document.createElement('div') as web.HTMLDivElement;
      wrapper.id = _searchOverlayId;

      final shell = web.document.createElement('div') as web.HTMLDivElement;
      shell.className = 'search-shell';

      final icon = web.document.createElement('span') as web.HTMLSpanElement;
      icon.className = 'search-icon';
      icon.textContent = '🔍';

      final input = web.document.createElement('input') as web.HTMLInputElement;
      input.type = 'search';
      input.placeholder = '노트 검색...';
      input.value = widget.controller?.text ?? '';
      input.autocomplete = 'off';
      input.spellcheck = false;
      input.setAttribute('enterkeyhint', 'search');

      input.addEventListener(
        'input',
        ((web.Event _) {
          final value = input.value;
          final controller = widget.controller;
          if (controller != null && controller.text != value) {
            controller.value = TextEditingValue(
              text: value,
              selection: TextSelection.collapsed(offset: value.length),
            );
          }
          widget.onChanged(value);
        }).toJS,
      );

      input.addEventListener(
        'keydown',
        ((web.Event event) {
          final keyboardEvent = event as web.KeyboardEvent;
          if (keyboardEvent.key == 'Escape') {
            widget.onClosed();
          }
        }).toJS,
      );

      shell.append(icon);
      shell.append(input);
      wrapper.append(shell);
      body.appendChild(wrapper);

      _wrapper = wrapper;
      _input = input;
    }

    _input?.focus();
  }

  void _removeElement() {
    _wrapper?.remove();
    _wrapper = null;
    _input = null;
  }

  @override
  void dispose() {
    _removeElement();
    super.dispose();
  }
}
