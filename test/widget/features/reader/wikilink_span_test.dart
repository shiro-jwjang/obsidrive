import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:obsidrive/features/reader/presentation/wikilink_span.dart';

void main() {
  testWidgets('WikilinkSpan styles existing links and handles taps', (
    tester,
  ) async {
    var tapped = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WikilinkSpan(
            text: 'Existing',
            exists: true,
            onTap: () => tapped = true,
          ),
        ),
      ),
    );

    final text = tester.widget<Text>(find.text('Existing'));
    expect(text.style?.decoration, TextDecoration.underline);

    await tester.tap(find.text('Existing'));

    expect(tapped, isTrue);
  });

  testWidgets('WikilinkSpan styles missing links without underline', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WikilinkSpan(text: 'Missing', exists: false, onTap: () {}),
        ),
      ),
    );

    final text = tester.widget<Text>(find.text('Missing'));
    expect(text.style?.decoration, TextDecoration.none);
  });
}
