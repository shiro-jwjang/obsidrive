import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/auth_state.dart';

class LoginScreen extends ConsumerWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authControllerProvider);
    final authController = ref.read(authControllerProvider.notifier);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Text(
                  'Obsidrive',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 12),
                Text(_subtitleFor(authState), textAlign: TextAlign.center),
                const SizedBox(height: 32),
                if (authState.status == AuthStatus.authenticated)
                  _AuthenticatedUser(email: authState.user!.email)
                else ...<Widget>[
                  FilledButton(
                    onPressed: authState.isLoading
                        ? null
                        : authController.signIn,
                    child: const Text('구글 계정으로 시작'),
                  ),
                  if (authState.isLoading) ...<Widget>[
                    const SizedBox(height: 24),
                    const Center(child: CircularProgressIndicator()),
                  ],
                  if (authState.status == AuthStatus.error) ...<Widget>[
                    const SizedBox(height: 16),
                    Text(
                      authState.errorMessage ?? '로그인 중 오류가 발생했습니다.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton(
                      onPressed: authState.isLoading
                          ? null
                          : authController.retry,
                      child: const Text('재시도'),
                    ),
                  ],
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _subtitleFor(AuthState authState) {
    return switch (authState.status) {
      AuthStatus.authenticated => '로그인되었습니다.',
      AuthStatus.error => '구글 계정 연결에 실패했습니다.',
      _ => '구글드라이브의 옵시디언 노트를 읽어옵니다.',
    };
  }
}

class _AuthenticatedUser extends StatelessWidget {
  const _AuthenticatedUser({required this.email});

  final String email;

  @override
  Widget build(BuildContext context) {
    return Text(
      email,
      textAlign: TextAlign.center,
      style: Theme.of(context).textTheme.titleMedium,
    );
  }
}
