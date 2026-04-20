import 'package:flutter_test/flutter_test.dart';
import 'package:obsidrive/features/auth/data/auth_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late FakeGoogleSignInClient googleSignIn;
  late DateTime now;

  setUp(() {
    googleSignIn = FakeGoogleSignInClient();
    now = DateTime.utc(2026, 4, 13, 0, 0);
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  AuthRepository createRepository() {
    return AuthRepository(googleSignInClient: googleSignIn, now: () => now);
  }

  test('signIn returns user with auth headers', () async {
    googleSignIn.interactiveUser = const GatewayUser(
      id: 'user-1',
      email: 'reader@example.com',
      accessToken: 'access-token',
      displayName: 'Vault Reader',
      photoUrl: 'https://example.com/avatar.png',
      idToken: 'id-token',
    );

    final user = await createRepository().signIn();

    expect(user.id, 'user-1');
    expect(user.email, 'reader@example.com');
    expect(user.authHeaders, <String, String>{
      'Authorization': 'Bearer access-token',
      'X-Goog-AuthUser': '0',
    });
    expect(googleSignIn.requestedScopes, contains(AuthRepository.driveScope));
  });

  test('restoreSession returns saved user without UI', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'auth.user.id': 'saved-user',
      'auth.user.email': 'saved@example.com',
      'auth.user.displayName': 'Saved User',
      'auth.user.photoUrl': 'https://example.com/saved.png',
      'auth.accessToken': 'saved-token',
      'auth.idToken': 'saved-id-token',
      'auth.expiresAt': now.add(const Duration(minutes: 20)).toIso8601String(),
    });

    final user = await createRepository().restoreSession();

    expect(user, isNotNull);
    expect(user!.id, 'saved-user');
    expect(user.authHeaders['Authorization'], 'Bearer saved-token');
    expect(googleSignIn.interactiveSignInCount, 0);
  });

  test('refreshToken returns new valid token on expiry', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'auth.user.id': 'saved-user',
      'auth.user.email': 'saved@example.com',
      'auth.user.displayName': 'Saved User',
      'auth.accessToken': 'expired-token',
      'auth.idToken': 'expired-id-token',
      'auth.expiresAt': now
          .subtract(const Duration(minutes: 1))
          .toIso8601String(),
    });
    googleSignIn.silentUser = const GatewayUser(
      id: 'saved-user',
      email: 'saved@example.com',
      accessToken: 'fresh-token',
      displayName: 'Saved User',
      idToken: 'fresh-id-token',
    );

    final user = await createRepository().refreshToken();

    expect(user.authHeaders['Authorization'], 'Bearer fresh-token');
    expect(user.expiresAt, now.add(AuthRepository.tokenLifetime));

    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getString('auth.accessToken'), 'fresh-token');
  });

  test('signIn throws AuthException when user cancels', () async {
    await expectLater(
      createRepository().signIn(),
      throwsA(
        isA<AuthException>().having(
          (error) => error.message,
          'message',
          '로그인이 취소되었습니다.',
        ),
      ),
    );
  });

  test('signOut calls gateway and clears saved session', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'auth.user.id': 'saved-user',
      'auth.user.email': 'saved@example.com',
      'auth.accessToken': 'saved-token',
      'auth.expiresAt': now.add(const Duration(minutes: 20)).toIso8601String(),
    });

    await createRepository().signOut();

    final preferences = await SharedPreferences.getInstance();
    expect(googleSignIn.signOutCount, 1);
    expect(preferences.getString('auth.user.id'), isNull);
    expect(preferences.getString('auth.accessToken'), isNull);
  });

  test(
    'restoreSession returns null for incomplete or invalid saved user',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'auth.user.id': 'saved-user',
        'auth.user.email': 'saved@example.com',
        'auth.accessToken': 'saved-token',
        'auth.expiresAt': 'not-a-date',
      });

      expect(await createRepository().restoreSession(), isNull);

      SharedPreferences.setMockInitialValues(<String, Object>{
        'auth.user.id': 'saved-user',
        'auth.user.email': 'saved@example.com',
      });

      expect(await createRepository().restoreSession(), isNull);
    },
  );

  test('restoreSession refresh failure clears session and throws', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'auth.user.id': 'saved-user',
      'auth.user.email': 'saved@example.com',
      'auth.accessToken': 'expired-token',
      'auth.expiresAt': now
          .subtract(const Duration(minutes: 1))
          .toIso8601String(),
    });

    await expectLater(
      createRepository().restoreSession(),
      throwsA(
        isA<AuthException>().having(
          (error) => error.message,
          'message',
          '다시 로그인해 주세요.',
        ),
      ),
    );

    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getString('auth.user.id'), isNull);
    expect(preferences.getString('auth.accessToken'), isNull);
  });

  test('refreshToken clears session when silent sign-in throws', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'auth.user.id': 'saved-user',
      'auth.user.email': 'saved@example.com',
      'auth.accessToken': 'expired-token',
      'auth.expiresAt': now
          .subtract(const Duration(minutes: 1))
          .toIso8601String(),
    });
    googleSignIn.silentError = StateError('network');

    await expectLater(
      createRepository().refreshToken(),
      throwsA(isA<AuthException>()),
    );

    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getString('auth.user.id'), isNull);
  });
}

class FakeGoogleSignInClient implements GoogleSignInClient {
  GatewayUser? interactiveUser;
  GatewayUser? silentUser;
  Object? silentError;
  int interactiveSignInCount = 0;
  int signOutCount = 0;

  @override
  final requestedScopes = <String>[AuthRepository.driveScope];

  @override
  Future<GatewayUser?> signIn() async {
    interactiveSignInCount += 1;
    return interactiveUser;
  }

  @override
  Future<GatewayUser?> signInSilently() async {
    final currentError = silentError;
    if (currentError is Error) throw currentError;
    if (currentError is Exception) throw currentError;
    return silentUser;
  }

  @override
  Future<void> signOut() async {
    signOutCount += 1;
  }
}
