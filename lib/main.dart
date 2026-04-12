import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'features/auth/domain/auth_state.dart';
import 'features/auth/presentation/login_screen.dart';
import 'features/vault/domain/vault_provider.dart';
import 'features/vault/presentation/folder_tree_widget.dart';
import 'features/vault/presentation/vault_picker_screen.dart';

void main() {
  runApp(const ProviderScope(child: MyApp()));
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Obsidrive',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
        useMaterial3: true,
      ),
      routes: <String, WidgetBuilder>{
        '/reader': (context) => const _ReaderPlaceholderScreen(),
      },
      home: const _AppRoot(),
    );
  }
}

class _AppRoot extends ConsumerWidget {
  const _AppRoot();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authControllerProvider);
    if (authState.status != AuthStatus.authenticated) {
      return const LoginScreen();
    }

    final selectedVault = ref.watch(selectedVaultProvider);
    return selectedVault.when(
      data: (vault) {
        if (vault == null) {
          return const VaultPickerScreen();
        }

        final notes = ref.watch(selectedVaultNotesProvider);
        return Scaffold(
          appBar: AppBar(title: Text(vault.name)),
          body: notes.when(
            data: (items) => FolderTreeWidget(notes: items),
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, stackTrace) => Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text('노트를 불러오지 못했습니다.\n$error'),
              ),
            ),
          ),
        );
      },
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (error, stackTrace) => Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('볼트 정보를 불러오지 못했습니다.\n$error'),
          ),
        ),
      ),
    );
  }
}

class _ReaderPlaceholderScreen extends StatelessWidget {
  const _ReaderPlaceholderScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: Text('리더 준비 중')));
  }
}
