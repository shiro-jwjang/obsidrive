import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AuthRepository {
  AuthRepository({
    GoogleSignInClient? googleSignInClient,
    SharedPreferences? preferences,
    DateTime Function()? now,
  }) : _googleSignInClient =
           googleSignInClient ?? GoogleSignInClient.googleSignIn(),
       _preferences = preferences,
       _now = now ?? DateTime.now;

  static const driveScope = 'https://www.googleapis.com/auth/drive.readonly';
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
    final googleUser = await _googleSignInClient.signIn();
    if (googleUser == null) {
      throw const AuthException('로그인이 취소되었습니다.');
    }

    final user = _toAuthUser(googleUser);
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
    final googleUser = await _googleSignInClient.signInSilently();
    if (googleUser == null) {
      await clearSession();
      throw const AuthException('다시 로그인해 주세요.');
    }

    final user = _toAuthUser(googleUser);
    await _saveUser(user);
    return user;
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

  AuthUser _toAuthUser(GoogleSignInUser googleUser) {
    return AuthUser(
      id: googleUser.id,
      email: googleUser.email,
      displayName: googleUser.displayName,
      photoUrl: googleUser.photoUrl,
      accessToken: googleUser.accessToken,
      idToken: googleUser.idToken,
      expiresAt: _now().add(tokenLifetime),
    );
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

class GoogleSignInUser {
  const GoogleSignInUser({
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
    : _googleSignIn = GoogleSignIn(
        scopes: const <String>[AuthRepository.driveScope],
      ),
      _signIn = null,
      _signInSilently = null,
      _signOut = null,
      requestedScopes = const <String>[AuthRepository.driveScope];

  GoogleSignInClient.test({
    required Future<GoogleSignInUser?> Function() signIn,
    required Future<GoogleSignInUser?> Function() signInSilently,
    required Future<void> Function() signOut,
    required this.requestedScopes,
  }) : _googleSignIn = null,
       _signIn = signIn,
       _signInSilently = signInSilently,
       _signOut = signOut;

  final GoogleSignIn? _googleSignIn;
  final Future<GoogleSignInUser?> Function()? _signIn;
  final Future<GoogleSignInUser?> Function()? _signInSilently;
  final Future<void> Function()? _signOut;
  final List<String> requestedScopes;

  Future<GoogleSignInUser?> signIn() async {
    final signIn = _signIn;
    if (signIn != null) {
      return signIn();
    }

    final account = await _googleSignIn!.signIn();
    return _fromAccount(account);
  }

  Future<GoogleSignInUser?> signInSilently() async {
    final signInSilently = _signInSilently;
    if (signInSilently != null) {
      return signInSilently();
    }

    final account = await _googleSignIn!.signInSilently();
    return _fromAccount(account);
  }

  Future<void> signOut() async {
    final signOut = _signOut;
    if (signOut != null) {
      return signOut();
    }

    await _googleSignIn!.signOut();
  }

  Future<GoogleSignInUser?> _fromAccount(GoogleSignInAccount? account) async {
    if (account == null) {
      return null;
    }

    final authentication = await account.authentication;
    final accessToken = authentication.accessToken;
    if (accessToken == null) {
      throw const AuthException('구글 인증 토큰을 가져오지 못했습니다.');
    }

    return GoogleSignInUser(
      id: account.id,
      email: account.email,
      displayName: account.displayName,
      photoUrl: account.photoUrl,
      accessToken: accessToken,
      idToken: authentication.idToken,
    );
  }
}

class AuthException implements Exception {
  const AuthException(this.message);

  final String message;

  @override
  String toString() => message;
}
