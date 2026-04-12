import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:obsidrive/main.dart';

void main() {
  testWidgets('app starts on login screen', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: MyApp()));

    expect(find.text('Obsidrive'), findsOneWidget);
    expect(find.text('구글 계정으로 시작'), findsOneWidget);
  });
}
