import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/domain/auth_state.dart';
import '../../features/auth/presentation/login_screen.dart';
import '../../features/cache/data/cache_service.dart';
import '../../features/cache/domain/cache_provider.dart';
import '../../features/reader/domain/reader_provider.dart';
import '../../features/reader/presentation/reader_screen.dart';
import '../../features/settings/presentation/settings_screen.dart';
import '../../features/vault/domain/vault_models.dart';
import '../../features/vault/domain/vault_provider.dart';
import '../../features/vault/presentation/folder_tree_widget.dart';
import '../../features/vault/presentation/vault_picker_screen.dart';

class _AuthNotifier extends ChangeNotifier {
  _AuthNotifier(Ref ref) {
    ref.listen(authControllerProvider, (previous, next) {
      notifyListeners();
    });
  }
}

final appRouterProvider = Provider<GoRouter>((ref) {
  final notifier = _AuthNotifier(ref);

  return GoRouter(
    initialLocation: '/',
    refreshListenable: notifier,
    redirect: (context, state) {
      final authState = ref.read(authControllerProvider);
      final isAuthenticating = state.matchedLocation == '/login';

      // Not authenticated → login
      if (authState.status != AuthStatus.authenticated) {
        return isAuthenticating ? null : '/login';
      }

      // Authenticated but on login → home
      if (isAuthenticating) return '/home';

      return null;
    },
    routes: [
      GoRoute(
        path: '/login',
        pageBuilder: (context, state) =>
            NoTransitionPage(key: state.pageKey, child: const LoginScreen()),
      ),
      GoRoute(
        path: '/vault-picker',
        pageBuilder: (context, state) => NoTransitionPage(
          key: state.pageKey,
          child: const VaultPickerScreen(),
        ),
      ),
      GoRoute(
        path: '/',
        pageBuilder: (context, state) =>
            NoTransitionPage(key: state.pageKey, child: const _AuthGate()),
      ),
      GoRoute(
        path: '/home',
        pageBuilder: (context, state) =>
            NoTransitionPage(key: state.pageKey, child: const _AuthGate()),
      ),
      GoRoute(
        path: '/reader',
        pageBuilder: (context, state) {
          final note = state.extra as Note?;
          return NoTransitionPage(
            key: state.pageKey,
            child: ReaderScreenWithNote(note: note),
          );
        },
      ),
      GoRoute(
        path: '/settings',
        pageBuilder: (context, state) =>
            NoTransitionPage(key: state.pageKey, child: const SettingsScreen()),
      ),
    ],
  );
});

/// Gate that checks vault selection after authentication.
class _AuthGate extends ConsumerWidget {
  const _AuthGate();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedVault = ref.watch(selectedVaultProvider);
    return selectedVault.when(
      data: (vault) {
        if (vault == null) {
          return const VaultPickerScreen();
        }

        final notes = ref.watch(selectedVaultNotesProvider);
        final folders = ref.watch(folderTreeProvider);
        final scanProgress = ref.watch(scanProgressProvider);

        return notes.when(
          data: (items) {
            final folderList = folders.valueOrNull ?? const <DriveFolder>[];
            return HomeScreen(
              vault: vault,
              notes: items,
              folders: folderList,
              scanProgress: scanProgress,
            );
          },
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

/// Main home screen showing the vault tree and cache controls.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({
    required this.vault,
    required this.notes,
    required this.folders,
    required this.scanProgress,
    super.key,
  });

  final Vault vault;
  final List<Note> notes;
  final List<DriveFolder> folders;
  final ScanProgress scanProgress;

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
            onPressed: () => context.go('/settings'),
            icon: const Icon(Icons.settings_outlined),
          ),
        ],
      ),
      body: Column(
        children: <Widget>[
          if (!isOnline) const OfflineBanner(),
          CacheProgress(status: syncStatus),
          if (scanProgress.status == ScanStatus.syncing &&
              scanProgress.phase == ScanPhase.fullScan)
            _FullScanProgress(progress: scanProgress),
          Expanded(
            child: FolderTreeWidget(
              vault: vault,
              folders: folders,
              notes: notes,
            ),
          ),
        ],
      ),
    );
  }
}

/// Shows full scan progress in the HomeScreen.
class _FullScanProgress extends StatelessWidget {
  const _FullScanProgress({required this.progress});

  final ScanProgress progress;

  @override
  Widget build(BuildContext context) {
    final text =
        '전체 스캔 중 ${progress.syncedFiles}개${progress.currentFolder != null ? ' · ${progress.currentFolder}' : ''}';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: <Widget>[
          const SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.outline,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Wraps [ReaderScreen] to optionally inject a note via GoRouter extra.
class ReaderScreenWithNote extends ConsumerStatefulWidget {
  const ReaderScreenWithNote({this.note, super.key});

  final Note? note;

  @override
  ConsumerState<ReaderScreenWithNote> createState() =>
      _ReaderScreenWithNoteState();
}

class _ReaderScreenWithNoteState extends ConsumerState<ReaderScreenWithNote> {
  @override
  void initState() {
    super.initState();
    if (widget.note != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ref.read(currentNoteProvider.notifier).state = widget.note;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return const ReaderScreen();
  }
}

class OfflineBanner extends StatelessWidget {
  const OfflineBanner({super.key});

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

class CacheProgress extends StatelessWidget {
  const CacheProgress({required this.status, super.key});

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
