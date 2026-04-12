import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:obsidrive/features/auth/data/auth_repository.dart';
import 'package:obsidrive/features/auth/domain/auth_state.dart';
import 'package:obsidrive/features/auth/presentation/login_screen.dart';

void main() {
  testWidgets('shows Google Sign-In button and authenticates on tap', (
    tester,
  ) async {
    final repository = FakeAuthRepository(
      signInUser: AuthUser(
        id: 'user-1',
        email: 'reader@example.com',
        accessToken: 'token',
        expiresAt: DateTime.utc(2026, 4, 13, 1),
      ),
      signInDelay: const Duration(milliseconds: 1),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          authRepositoryProvider.overrideWithValue(repository),
        ],
        child: const MaterialApp(home: LoginScreen()),
      ),
    );

    await tester.tap(find.text('구글 계정으로 시작'));
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await tester.pumpAndSettle();

    expect(repository.signInCount, 1);
    expect(find.text('reader@example.com'), findsOneWidget);
  });

  testWidgets('shows error state with retry', (tester) async {
    final repository = FakeAuthRepository(
      error: const AuthException('네트워크 오류가 발생했습니다.'),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          authRepositoryProvider.overrideWithValue(repository),
        ],
        child: const MaterialApp(home: LoginScreen()),
      ),
    );

    await tester.tap(find.text('구글 계정으로 시작'));
    await tester.pumpAndSettle();

    expect(find.text('네트워크 오류가 발생했습니다.'), findsOneWidget);
    expect(find.text('재시도'), findsOneWidget);

    repository
      ..error = null
      ..signInUser = AuthUser(
        id: 'user-2',
        email: 'retry@example.com',
        accessToken: 'retry-token',
        expiresAt: DateTime.utc(2026, 4, 13, 1),
      );

    await tester.tap(find.text('재시도'));
    await tester.pumpAndSettle();

    expect(repository.signInCount, 2);
    expect(find.text('retry@example.com'), findsOneWidget);
  });
}

class FakeAuthRepository implements AuthRepository {
  FakeAuthRepository({
    this.signInUser,
    this.error,
    this.signInDelay = Duration.zero,
  });

  AuthUser? signInUser;
  AuthException? error;
  Duration signInDelay;
  var signInCount = 0;

  @override
  Future<AuthUser> signIn() async {
    signInCount += 1;
    if (signInDelay > Duration.zero) {
      await Future<void>.delayed(signInDelay);
    }
    final error = this.error;
    if (error != null) {
      throw error;
    }

    return signInUser!;
  }

  @override
  Future<AuthUser?> restoreSession() async => null;

  @override
  Future<AuthUser> refreshToken() async => signIn();

  @override
  Future<void> signOut() async {}

  @override
  Future<void> clearSession() async {}
}
