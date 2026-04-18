import 'package:shared_preferences/shared_preferences.dart';

// Conditional imports for platform-specific sign-in
import 'auth_gateway_stub.dart'
    if (dart.library.html) 'auth_gateway_web.dart'
    if (dart.library.io) 'auth_gateway_io.dart';

class AuthRepository {
  AuthRepository({
    GoogleSignInClient? googleSignInClient,
    SharedPreferences? preferences,
    DateTime Function()? now,
  }) : _googleSignInClient =
           googleSignInClient ?? GoogleSignInClient.googleSignIn(),
       _preferences = preferences,
       _now = now ?? DateTime.now;

  static const driveScope = 'https://www.googleapis.com/auth/drive';
  static const tokenLifetime = Duration(hours: 1);

  static const _userIdKey = 'auth.user.id';
  static const _emailKey = 'auth.user.email';
  static const _displayNameKey = 'auth.user.displayName';
  static const _photoUrlKey = 'auth.user.photoUrl';
  static const _accessTokenKey = 'auth.accessToken';
  static const _idTokenKey = 'auth.idToken';
  static const _expiresAtKey = 'auth.expiresAt';

  final GoogleSignInClient _googleSignInClient;
  final SharedPreferences? _preferences;
  final DateTime Function() _now;

  Future<AuthUser> signIn() async {
    final gatewayUser = await _googleSignInClient.signIn();
    if (gatewayUser == null) {
      throw const AuthException('로그인이 취소되었습니다.');
    }

    final user = AuthUser(
      id: gatewayUser.id,
      email: gatewayUser.email,
      displayName: gatewayUser.displayName,
      photoUrl: gatewayUser.photoUrl,
      accessToken: gatewayUser.accessToken,
      idToken: gatewayUser.idToken,
      expiresAt: _now().add(tokenLifetime),
    );

    await _saveUser(user);
    return user;
  }

  Future<AuthUser?> restoreSession() async {
    final preferences = await _getPreferences();
    final user = _readUser(preferences);
    if (user == null) {
      return null;
    }

    if (user.isExpired(_now())) {
      return refreshToken();
    }

    return user;
  }

  Future<AuthUser> refreshToken() async {
    try {
      final gatewayUser = await _googleSignInClient.signInSilently();
      if (gatewayUser == null) {
        throw const AuthException('다시 로그인해 주세요.');
      }

      final user = AuthUser(
        id: gatewayUser.id,
        email: gatewayUser.email,
        displayName: gatewayUser.displayName,
        photoUrl: gatewayUser.photoUrl,
        accessToken: gatewayUser.accessToken,
        idToken: gatewayUser.idToken,
        expiresAt: _now().add(tokenLifetime),
      );

      await _saveUser(user);
      return user;
    } catch (_) {
      await clearSession();
      throw const AuthException('다시 로그인해 주세요.');
    }
  }

  Future<void> signOut() async {
    await _googleSignInClient.signOut();
    await clearSession();
  }

  Future<void> clearSession() async {
    final preferences = await _getPreferences();
    await preferences.remove(_userIdKey);
    await preferences.remove(_emailKey);
    await preferences.remove(_displayNameKey);
    await preferences.remove(_photoUrlKey);
    await preferences.remove(_accessTokenKey);
    await preferences.remove(_idTokenKey);
    await preferences.remove(_expiresAtKey);
  }

  AuthUser? _readUser(SharedPreferences preferences) {
    final id = preferences.getString(_userIdKey);
    final email = preferences.getString(_emailKey);
    final accessToken = preferences.getString(_accessTokenKey);
    final expiresAtValue = preferences.getString(_expiresAtKey);

    if (id == null ||
        email == null ||
        accessToken == null ||
        expiresAtValue == null) {
      return null;
    }

    final expiresAt = DateTime.tryParse(expiresAtValue);
    if (expiresAt == null) {
      return null;
    }

    return AuthUser(
      id: id,
      email: email,
      displayName: preferences.getString(_displayNameKey),
      photoUrl: preferences.getString(_photoUrlKey),
      accessToken: accessToken,
      idToken: preferences.getString(_idTokenKey),
      expiresAt: expiresAt,
    );
  }

  Future<void> _saveUser(AuthUser user) async {
    final preferences = await _getPreferences();
    await preferences.setString(_userIdKey, user.id);
    await preferences.setString(_emailKey, user.email);
    await _setNullableString(preferences, _displayNameKey, user.displayName);
    await _setNullableString(preferences, _photoUrlKey, user.photoUrl);
    await preferences.setString(_accessTokenKey, user.accessToken);
    await _setNullableString(preferences, _idTokenKey, user.idToken);
    await preferences.setString(
      _expiresAtKey,
      user.expiresAt.toIso8601String(),
    );
  }

  Future<void> _setNullableString(
    SharedPreferences preferences,
    String key,
    String? value,
  ) {
    if (value == null) {
      return preferences.remove(key);
    }

    return preferences.setString(key, value);
  }

  Future<SharedPreferences> _getPreferences() async {
    return _preferences ?? SharedPreferences.getInstance();
  }
}

class AuthUser {
  const AuthUser({
    required this.id,
    required this.email,
    required this.accessToken,
    required this.expiresAt,
    this.displayName,
    this.photoUrl,
    this.idToken,
  });

  final String id;
  final String email;
  final String? displayName;
  final String? photoUrl;
  final String accessToken;
  final String? idToken;
  final DateTime expiresAt;

  Map<String, String> get authHeaders {
    return <String, String>{
      'Authorization': 'Bearer $accessToken',
      'X-Goog-AuthUser': '0',
    };
  }

  bool isExpired(DateTime now) => !expiresAt.isAfter(now);
}

/// Gateway user returned by platform-specific auth
class GatewayUser {
  const GatewayUser({
    required this.id,
    required this.email,
    required this.accessToken,
    this.displayName,
    this.photoUrl,
    this.idToken,
  });

  final String id;
  final String email;
  final String? displayName;
  final String? photoUrl;
  final String accessToken;
  final String? idToken;
}

class GoogleSignInClient {
  GoogleSignInClient.googleSignIn()
    : _signIn = null,
      _signInSilently = null,
      _signOut = null,
      requestedScopes = const <String>[AuthRepository.driveScope];

  // Keep for backwards compat with tests
  GoogleSignInClient.test({
    required Future<GatewayUser?> Function() signIn,
    required Future<GatewayUser?> Function() signInSilently,
    required Future<void> Function() signOut,
    required this.requestedScopes,
  }) : _signIn = signIn,
       _signInSilently = signInSilently,
       _signOut = signOut;

  final Future<GatewayUser?> Function()? _signIn;
  final Future<GatewayUser?> Function()? _signInSilently;
  final Future<void> Function()? _signOut;
  final List<String> requestedScopes;

  Future<GatewayUser?> signIn() async {
    final signIn = _signIn;
    if (signIn != null) return signIn();
    return createAuthGateway().signIn();
  }

  Future<GatewayUser?> signInSilently() async {
    final signInSilently = _signInSilently;
    if (signInSilently != null) return signInSilently();
    return createAuthGateway().signInSilently();
  }

  Future<void> signOut() async {
    final signOut = _signOut;
    if (signOut != null) return signOut();
    return createAuthGateway().signOut();
  }
}

class AuthException implements Exception {
  const AuthException(this.message);

  final String message;

  @override
  String toString() => message;
}
