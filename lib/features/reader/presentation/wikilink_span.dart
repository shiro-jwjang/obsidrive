// coverage:ignore-file
import 'package:flutter/material.dart';

class WikilinkSpan extends StatelessWidget {
  const WikilinkSpan({
    required this.text,
    required this.exists,
    required this.onTap,
    super.key,
  });

  final String text;
  final bool exists;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = exists ? theme.colorScheme.primary : theme.disabledColor;

    return SelectionContainer.disabled(
      child: GestureDetector(
        onTap: onTap,
        child: Text(
          text,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: color,
            decoration: exists ? TextDecoration.underline : TextDecoration.none,
            decorationColor: color,
          ),
        ),
      ),
    );
  }
}
