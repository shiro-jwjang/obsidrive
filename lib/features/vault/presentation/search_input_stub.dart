import 'package:flutter/material.dart';

typedef SearchInputBuilder =
    Widget Function({
      required bool isVisible,
      required ValueChanged<String> onChanged,
      required VoidCallback onClosed,
      VoidCallback? onOpen,
      TextEditingController? controller,
      FocusNode? focusNode,
    });

Widget buildSearchInput({
  required bool isVisible,
  required ValueChanged<String> onChanged,
  required VoidCallback onClosed,
  VoidCallback? onOpen,
  TextEditingController? controller,
  FocusNode? focusNode,
}) {
  if (!isVisible) return const SizedBox.shrink();

  return Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    child: TextField(
      controller: controller,
      focusNode: focusNode,
      autofocus: true,
      onChanged: onChanged,
      onSubmitted: (_) => onClosed(),
      decoration: InputDecoration(
        hintText: '노트 검색...',
        prefixIcon: const Icon(Icons.search),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        contentPadding: const EdgeInsets.symmetric(vertical: 10),
      ),
      textInputAction: TextInputAction.search,
    ),
  );
}
