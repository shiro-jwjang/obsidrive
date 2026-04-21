import 'dart:js_interop';

import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

export 'search_input_stub.dart';

const _searchButtonId = '__obsidrive_search_button__';
const _searchInputId = '__obsidrive_search_input__';
const _searchBlockerId = '__obsidrive_search_blocker__';
const _searchStyleId = '__obsidrive_search_style__';

Widget buildSearchInput({
  required bool isVisible,
  required ValueChanged<String> onChanged,
  required VoidCallback onClosed,
  VoidCallback? onOpen,
  TextEditingController? controller,
  FocusNode? focusNode,
}) {
  return _HtmlSearchInput(
    isVisible: isVisible,
    onChanged: onChanged,
    onClosed: onClosed,
    onOpen: onOpen,
    controller: controller,
  );
}

class _HtmlSearchInput extends StatefulWidget {
  const _HtmlSearchInput({
    required this.isVisible,
    required this.onChanged,
    required this.onClosed,
    this.onOpen,
    this.controller,
  });

  final bool isVisible;
  final ValueChanged<String> onChanged;
  final VoidCallback onClosed;
  final VoidCallback? onOpen;
  final TextEditingController? controller;

  @override
  State<_HtmlSearchInput> createState() => _HtmlSearchInputState();
}

class _HtmlSearchInputState extends State<_HtmlSearchInput> {
  web.HTMLButtonElement? _button;
  web.HTMLDivElement? _blocker;
  web.HTMLDivElement? _wrapper;
  web.HTMLInputElement? _input;

  @override
  void initState() {
    super.initState();
    _ensureStyle();
    _ensureButton();
    _syncDom();
  }

  @override
  void didUpdateWidget(covariant _HtmlSearchInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncDom();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(height: widget.isVisible ? 64 : 0);
  }

  void _syncDom() {
    _ensureStyle();
    _ensureButton();
    _syncButtonState();

    if (widget.isVisible) {
      _ensureBlocker();
      _ensureInput();
      _syncInputState();
      return;
    }

    _removeInput();
    _removeBlocker();
  }

  void _ensureStyle() {
    if (web.document.getElementById(_searchStyleId) != null) return;

    final style = web.document.createElement('style') as web.HTMLStyleElement;
    style.id = _searchStyleId;
    style.textContent =
        '''
#$_searchButtonId {
  position: fixed;
  top: 0;
  right: 0;
  width: 56px;
  height: 56px;
  z-index: 2147483647;
  border: none;
  margin: 0;
  padding: 0;
  background: transparent;
  color: transparent;
  font-size: 0;
  line-height: 1;
  display: flex;
  align-items: center;
  justify-content: center;
  cursor: pointer;
  -webkit-tap-highlight-color: transparent;
}
#$_searchButtonId:focus {
  outline: none;
}
#$_searchBlockerId {
  position: fixed;
  top: 0;
  left: 0;
  right: 0;
  height: 120px;
  z-index: 2147483645;
  background: transparent;
  pointer-events: auto;
}
#$_searchInputId {
  position: fixed;
  top: 56px;
  left: 0;
  right: 0;
  z-index: 2147483646;
  box-sizing: border-box;
  padding: 8px 16px;
  background: transparent;
  pointer-events: auto;
  -webkit-tap-highlight-color: transparent;
  -webkit-user-select: none;
  user-select: none;
}
#$_searchInputId .search-shell {
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
  -webkit-tap-highlight-color: transparent;
  -webkit-user-select: none;
  user-select: none;
}
#$_searchInputId .search-icon {
  color: #667085;
  font-size: 16px;
  line-height: 1;
  user-select: none;
  -webkit-user-select: none;
}
#$_searchInputId input[type="search"] {
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
  -webkit-user-select: text;
  user-select: text;
  -webkit-tap-highlight-color: transparent;
  caret-color: #101828;
}
#$_searchInputId input[type="search"]::-webkit-search-decoration {
  display: none;
}
#$_searchInputId input[type="search"]::-webkit-search-cancel-button {
  display: none;
}
#$_searchInputId input[type="search"]::placeholder {
  color: #667085;
}
''';
    web.document.head?.appendChild(style);
  }

  void _ensureButton() {
    final body = web.document.body;
    if (body == null || _button != null) return;

    final button =
        web.document.createElement('button') as web.HTMLButtonElement;
    button.id = _searchButtonId;
    button.type = 'button';
    button.setAttribute('aria-label', '노트 검색');

    button.addEventListener(
      'click',
      ((web.Event _) {
        if (widget.isVisible) {
          widget.onClosed();
          return;
        }

        _ensureBlocker();
        _ensureInput();
        _syncInputState();
        _input?.focus();
        widget.onOpen?.call();
      }).toJS,
    );

    body.appendChild(button);
    _button = button;
    _syncButtonState();
  }

  void _syncButtonState() {
    final button = _button;
    if (button == null) return;

    button.textContent = widget.isVisible ? '✕' : '🔍';
    button.title = widget.isVisible ? '검색 닫기' : '노트 검색';
    button.setAttribute('aria-label', widget.isVisible ? '검색 닫기' : '노트 검색');
  }

  void _ensureBlocker() {
    final body = web.document.body;
    if (body == null || _blocker != null) return;

    final blocker = web.document.createElement('div') as web.HTMLDivElement;
    blocker.id = _searchBlockerId;
    blocker.addEventListener('click', ((web.Event _) {}).toJS);
    blocker.addEventListener('touchstart', ((web.Event _) {}).toJS);
    blocker.addEventListener('touchmove', ((web.Event _) {}).toJS);

    body.appendChild(blocker);
    _blocker = blocker;
  }

  void _ensureInput() {
    final body = web.document.body;
    if (body == null || _wrapper != null) return;

    final wrapper = web.document.createElement('div') as web.HTMLDivElement;
    wrapper.id = _searchInputId;

    final shell = web.document.createElement('div') as web.HTMLDivElement;
    shell.className = 'search-shell';

    final icon = web.document.createElement('span') as web.HTMLSpanElement;
    icon.className = 'search-icon';
    icon.textContent = '🔍';

    final input = web.document.createElement('input') as web.HTMLInputElement;
    input.type = 'search';
    input.placeholder = '노트 검색...';
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

  void _syncInputState() {
    final input = _input;
    if (input == null) return;

    final value = widget.controller?.text ?? '';
    if (input.value != value) {
      input.value = value;
    }
  }

  void _removeInput() {
    _wrapper?.remove();
    _wrapper = null;
    _input = null;
  }

  void _removeBlocker() {
    _blocker?.remove();
    _blocker = null;
  }

  @override
  void dispose() {
    _removeInput();
    _removeBlocker();
    _button?.remove();
    _button = null;
    super.dispose();
  }
}
