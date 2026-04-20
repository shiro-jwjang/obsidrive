import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:obsidrive/features/auth/data/auth_repository.dart';
import 'package:obsidrive/features/auth/domain/auth_state.dart';
import 'package:obsidrive/features/cache/data/cache_service.dart';
import 'package:obsidrive/features/cache/domain/cache_provider.dart';
import 'package:obsidrive/features/settings/data/settings_repository.dart';
import 'package:obsidrive/features/settings/presentation/settings_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('renders theme options, cache summary, and logout button', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          cacheSummaryProvider.overrideWith(
            (ref) async =>
                const CacheSummary(fileCount: 2, totalSizeBytes: 1536),
          ),
          authControllerProvider.overrideWith(
            () => FakeAuthController(AuthState.authenticated(authUser())),
          ),
        ],
        child: app(),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('설정'), findsOneWidget);
    expect(find.text('테마'), findsOneWidget);
    expect(find.text('시스템'), findsOneWidget);
    expect(find.text('라이트'), findsOneWidget);
    expect(find.text('다크'), findsOneWidget);
    expect(find.text('2개 파일'), findsOneWidget);
    expect(find.text('1.5 KB'), findsOneWidget);
    expect(find.text('로그아웃'), findsOneWidget);
  });

  testWidgets('theme radio updates ThemeModeController', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          cacheSummaryProvider.overrideWith(
            (ref) async => const CacheSummary(fileCount: 0, totalSizeBytes: 0),
          ),
        ],
        child: app(),
      ),
    );
    await tester.pump();
    await tester.pump();
    await tester.tap(find.text('다크'));
    await tester.pump();
    await tester.pump();

    final context = tester.element(find.byType(SettingsScreen));
    final container = ProviderScope.containerOf(context);
    expect(container.read(themeModeControllerProvider), ThemeMode.dark);
  });

  testWidgets('renders cache loading and error states', (tester) async {
    final completer = Completer<CacheSummary>();
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          cacheSummaryProvider.overrideWith((ref) => completer.future),
        ],
        child: app(),
      ),
    );
    await tester.pump();

    expect(find.text('캐시 정보를 불러오는 중'), findsOneWidget);

    completer.completeError(StateError('cache failed'));
    await tester.pump();
    await tester.pump();

    expect(find.text('캐시 정보를 불러오지 못했습니다.'), findsOneWidget);
    expect(find.textContaining('cache failed'), findsOneWidget);
  });
}

Widget app() {
  final router = GoRouter(
    routes: <RouteBase>[
      GoRoute(path: '/', builder: (context, state) => const SettingsScreen()),
      GoRoute(path: '/home', builder: (context, state) => const Text('Home')),
    ],
  );
  return MaterialApp.router(routerConfig: router);
}

class FakeAuthController extends AuthController {
  FakeAuthController(this.initialState);

  final AuthState initialState;

  @override
  AuthState build() => initialState;
}

AuthUser authUser() {
  return AuthUser(
    id: 'user',
    email: 'user@example.com',
    accessToken: 'token',
    expiresAt: DateTime.utc(2026, 4, 21),
  );
}
