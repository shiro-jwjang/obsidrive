import 'dart:async';

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
  static const _refreshLeadTime = Duration(minutes: 10);
  static const _refreshRetryDelay = Duration(minutes: 15);

  Timer? _refreshTimer;
  var _isDisposed = false;

  @override
  AuthState build() {
    ref.onDispose(() {
      _isDisposed = true;
      _cancelRefreshTimer();
    });
    return const AuthState.initial();
  }

  AuthRepository get _repository => ref.read(authRepositoryProvider);

  Future<void> restoreSession() async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final user = await _repository.restoreSession();
      if (user == null) {
        _cancelRefreshTimer();
        state = const AuthState.unauthenticated();
        return;
      }

      // If token is already expired, try silent refresh immediately
      // instead of setting authenticated with a dead token.
      if (user.isExpired(DateTime.now())) {
        try {
          final refreshedUser = await _repository.refreshToken();
          state = AuthState.authenticated(refreshedUser);
          _scheduleRefreshFor(refreshedUser);
        } catch (_) {
          // Silent refresh failed (common in PWA where GIS session is lost)
          _cancelRefreshTimer();
          state = const AuthState.unauthenticated();
        }
      } else {
        state = AuthState.authenticated(user);
        _scheduleRefreshFor(user, restored: true);
      }
    } catch (_) {
      _cancelRefreshTimer();
      // Stale/expired session — just show login button, no error message
      state = const AuthState.unauthenticated();
    }
  }

  Future<void> signIn() async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final user = await _repository.signIn();
      state = AuthState.authenticated(user);
      _scheduleRefreshFor(user);
    } catch (error) {
      state = AuthState.error(_messageFor(error));
    }
  }

  Future<void> retry() => signIn();

  Future<void> signOut() async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      _cancelRefreshTimer();
      await _repository.signOut();
      state = const AuthState.unauthenticated();
    } catch (error) {
      state = AuthState.error(_messageFor(error));
    }
  }

  /// Clears auth state without calling gateway signOut.
  /// Use when the gateway session is already lost (e.g. PWA GIS expiry).
  Future<void> forceSignOut() async {
    _cancelRefreshTimer();
    await _repository.clearSession();
    state = const AuthState.unauthenticated();
  }

  void _scheduleRefreshFor(AuthUser user, {bool restored = false}) {
    final now = DateTime.now();
    final delay = user.isExpired(now)
        ? _refreshRetryDelay
        : user.expiresAt.subtract(_refreshLeadTime).difference(now);
    _scheduleRefresh(delay.isNegative ? Duration.zero : delay);
  }

  void _scheduleRefresh(Duration delay) {
    _cancelRefreshTimer();
    _refreshTimer = Timer(delay, _handleScheduledRefresh);
  }

  Future<void> _handleScheduledRefresh() async {
    if (_isDisposed || state.status != AuthStatus.authenticated) {
      return;
    }

    try {
      final user = await _repository.refreshToken();
      if (_isDisposed) {
        return;
      }

      state = AuthState.authenticated(user);
      _scheduleRefreshFor(user);
    } catch (_) {
      if (_isDisposed || state.status != AuthStatus.authenticated) {
        return;
      }

      _scheduleRefresh(_refreshRetryDelay);
    }
  }

  void _cancelRefreshTimer() {
    _refreshTimer?.cancel();
    _refreshTimer = null;
  }

  String _messageFor(Object error) {
    if (error is AuthException) {
      return error.message;
    }

    return '로그인 중 오류가 발생했습니다.';
  }
}
