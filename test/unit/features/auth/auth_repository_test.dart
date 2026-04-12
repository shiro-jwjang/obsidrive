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
    googleSignIn.interactiveUser = const GoogleSignInUser(
      id: 'user-1',
      email: 'reader@example.com',
      displayName: 'Vault Reader',
      photoUrl: 'https://example.com/avatar.png',
      accessToken: 'access-token',
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
    googleSignIn.silentUser = const GoogleSignInUser(
      id: 'saved-user',
      email: 'saved@example.com',
      displayName: 'Saved User',
      accessToken: 'fresh-token',
      idToken: 'fresh-id-token',
    );

    final user = await createRepository().refreshToken();

    expect(user.authHeaders['Authorization'], 'Bearer fresh-token');
    expect(user.expiresAt, now.add(AuthRepository.tokenLifetime));

    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getString('auth.accessToken'), 'fresh-token');
  });
}

class FakeGoogleSignInClient implements GoogleSignInClient {
  GoogleSignInUser? interactiveUser;
  GoogleSignInUser? silentUser;
  var interactiveSignInCount = 0;

  @override
  final requestedScopes = <String>[AuthRepository.driveScope];

  @override
  Future<GoogleSignInUser?> signIn() async {
    interactiveSignInCount += 1;
    return interactiveUser;
  }

  @override
  Future<GoogleSignInUser?> signInSilently() async => silentUser;

  @override
  Future<void> signOut() async {}
}
