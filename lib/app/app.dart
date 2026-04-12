import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/auth/domain/auth_state.dart';
import '../features/auth/presentation/login_screen.dart';
import '../features/cache/data/cache_service.dart';
import '../features/cache/domain/cache_provider.dart';
import '../features/reader/presentation/reader_screen.dart';
import '../features/settings/data/settings_repository.dart';
import '../features/settings/presentation/settings_screen.dart';
import '../features/vault/domain/vault_models.dart';
import '../features/vault/domain/vault_provider.dart';
import '../features/vault/presentation/folder_tree_widget.dart';
import '../features/vault/presentation/vault_picker_screen.dart';
import 'theme.dart';

class MyApp extends ConsumerStatefulWidget {
  const MyApp({super.key});

  @override
  ConsumerState<MyApp> createState() => _MyAppState();
}

class _MyAppState extends ConsumerState<MyApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangePlatformBrightness() {
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(themeModeControllerProvider);
    return MaterialApp(
      title: 'Obsidrive',
      theme: buildLightTheme(),
      darkTheme: buildDarkTheme(),
      themeMode: themeMode,
      routes: <String, WidgetBuilder>{
        '/reader': (context) => const ReaderScreen(),
        '/settings': (context) => const SettingsScreen(),
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
        return notes.when(
          data: (items) => _HomeScreen(vault: vault, notes: items),
          loading: () => Scaffold(
            appBar: AppBar(title: Text(vault.name)),
            body: const Center(child: CircularProgressIndicator()),
          ),
          error: (error, stackTrace) => Scaffold(
            appBar: AppBar(title: Text(vault.name)),
            body: Center(
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

class _HomeScreen extends ConsumerWidget {
  const _HomeScreen({required this.vault, required this.notes});

  final Vault vault;
  final List<Note> notes;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen<bool>(isOnlineProvider, (previous, next) {
      if (previous == false && next) {
        ref.read(cacheSyncControllerProvider).checkForUpdates(notes);
      }
    });

    final syncStatus = ref.watch(syncStatusProvider);
    final isOnline = ref.watch(isOnlineProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(vault.name),
        actions: <Widget>[
          IconButton(
            tooltip: '오프라인 동기화',
            onPressed: isOnline && syncStatus.status != CacheSyncPhase.syncing
                ? () => ref.read(cacheSyncControllerProvider).syncVault(notes)
                : null,
            icon: const Icon(Icons.sync),
          ),
          IconButton(
            tooltip: '설정',
            onPressed: () => Navigator.of(context).pushNamed('/settings'),
            icon: const Icon(Icons.settings_outlined),
          ),
        ],
      ),
      body: Column(
        children: <Widget>[
          if (!isOnline) const _OfflineBanner(),
          _CacheProgress(status: syncStatus),
          Expanded(child: FolderTreeWidget(notes: notes)),
        ],
      ),
    );
  }
}

class _OfflineBanner extends StatelessWidget {
  const _OfflineBanner();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      color: theme.colorScheme.errorContainer,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Text(
        '오프라인입니다. 동기화된 노트만 열 수 있습니다.',
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onErrorContainer,
        ),
      ),
    );
  }
}

class _CacheProgress extends StatelessWidget {
  const _CacheProgress({required this.status});

  final CacheSyncStatus status;

  @override
  Widget build(BuildContext context) {
    final text = switch (status.status) {
      CacheSyncPhase.syncing =>
        '오프라인 동기화 ${status.syncedFiles}/${status.totalFiles}',
      CacheSyncPhase.complete => '오프라인 동기화 완료 ${status.syncedFiles}개',
      CacheSyncPhase.error => status.errorMessage ?? '오프라인 동기화 실패',
      CacheSyncPhase.idle => null,
    };
    if (text == null) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: <Widget>[
          if (status.status == CacheSyncPhase.syncing) ...<Widget>[
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 12),
          ],
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}
