// Web implementation: google_sign_in package (uses GIS directly)
//
// google_sign_in_web uses GIS initTokenClient → requestAccessToken internally,
// which reliably returns the OAuth access token. This is more reliable than
// Firebase Auth's signInWithPopup, which often returns null accessToken.
import 'package:google_sign_in/google_sign_in.dart';

import 'auth_gateway_stub.dart';
import 'auth_repository.dart';

AuthGateway createAuthGateway() => WebAuthGateway();

class WebAuthGateway implements AuthGateway {
  static const _driveScope = 'https://www.googleapis.com/auth/drive';

  final GoogleSignIn _googleSignIn = GoogleSignIn(
    clientId:
        '487606084766-o8ocai47la9ne3b6he388shb5v4c234q.apps.googleusercontent.com',
    scopes: const <String>[_driveScope],
  );

  @override
  Future<GatewayUser> signIn() async {
    final account = await _googleSignIn.signIn();
    if (account == null) {
      throw const AuthException('로그인이 취소되었습니다.');
    }
    return _fromAccount(account);
  }

  @override
  Future<GatewayUser> signInSilently() async {
    final account = await _googleSignIn.signInSilently();
    if (account == null) {
      throw const AuthException('다시 로그인해 주세요.');
    }
    return _fromAccount(account);
  }

  @override
  Future<void> signOut() async {
    await _googleSignIn.signOut();
  }

  Future<GatewayUser> _fromAccount(GoogleSignInAccount account) async {
    final auth = await account.authentication;
    final accessToken = auth.accessToken;
    if (accessToken == null) {
      throw const AuthException('구글 인증 토큰을 가져오지 못했습니다.');
    }
    return GatewayUser(
      id: account.id,
      email: account.email,
      displayName: account.displayName,
      photoUrl: account.photoUrl,
      accessToken: accessToken,
      idToken: auth.idToken,
    );
  }
}
