import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/auth_repository.dart';

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository();
});

final authControllerProvider = NotifierProvider<AuthController, AuthState>(
  AuthController.new,
);

enum AuthStatus { initial, authenticated, unauthenticated, error }

class AuthState {
  const AuthState({
    required this.status,
    this.user,
    this.errorMessage,
    this.isLoading = false,
  });

  const AuthState.initial()
    : status = AuthStatus.initial,
      user = null,
      errorMessage = null,
      isLoading = false;

  const AuthState.authenticated(AuthUser this.user)
    : status = AuthStatus.authenticated,
      errorMessage = null,
      isLoading = false;

  const AuthState.unauthenticated()
    : status = AuthStatus.unauthenticated,
      user = null,
      errorMessage = null,
      isLoading = false;

  const AuthState.error(String this.errorMessage)
    : status = AuthStatus.error,
      user = null,
      isLoading = false;

  final AuthStatus status;
  final AuthUser? user;
  final String? errorMessage;
  final bool isLoading;

  AuthState copyWith({
    AuthStatus? status,
    AuthUser? user,
    String? errorMessage,
    bool? isLoading,
    bool clearUser = false,
    bool clearError = false,
  }) {
    return AuthState(
      status: status ?? this.status,
      user: clearUser ? null : user ?? this.user,
      errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
      isLoading: isLoading ?? this.isLoading,
    );
  }
}

class AuthController extends Notifier<AuthState> {
  @override
  AuthState build() => const AuthState.initial();

  AuthRepository get _repository => ref.read(authRepositoryProvider);

  Future<void> restoreSession() async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final user = await _repository.restoreSession();
      state = user == null
          ? const AuthState.unauthenticated()
          : AuthState.authenticated(user);
    } catch (_) {
      // Stale/expired session — just show login button, no error message
      state = const AuthState.unauthenticated();
    }
  }

  Future<void> signIn() async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final user = await _repository.signIn();
      state = AuthState.authenticated(user);
    } catch (error) {
      state = AuthState.error(_messageFor(error));
    }
  }

  Future<void> retry() => signIn();

  Future<void> signOut() async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      await _repository.signOut();
      state = const AuthState.unauthenticated();
    } catch (error) {
      state = AuthState.error(_messageFor(error));
    }
  }

  String _messageFor(Object error) {
    if (error is AuthException) {
      return error.message;
    }

    return '로그인 중 오류가 발생했습니다.';
  }
}
