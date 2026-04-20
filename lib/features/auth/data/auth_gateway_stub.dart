// coverage:ignore-file
// Shared interface for auth gateways
// Stub file — overridden by auth_gateway_web.dart or auth_gateway_io.dart
import 'auth_repository.dart';

AuthGateway createAuthGateway() =>
    throw UnsupportedError('Platform not supported');

abstract class AuthGateway {
  Future<GatewayUser> signIn();
  Future<GatewayUser> signInSilently();
  Future<void> signOut();
}
