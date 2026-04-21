// coverage:ignore-file
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
class HomeScreen extends ConsumerStatefulWidget {
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
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode();
  var _isSearching = false;
  var _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<bool>(isOnlineProvider, (previous, next) {
      if (previous == false && next) {
        ref.read(cacheSyncControllerProvider).checkForUpdates(widget.notes);
      }
    });

    final syncStatus = ref.watch(syncStatusProvider);
    final isOnline = ref.watch(isOnlineProvider);
    final scanProgress = ref.watch(scanProgressProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.vault.name),
        actions: <Widget>[
          if (_isSearching)
            IconButton(
              tooltip: '검색 닫기',
              onPressed: _closeSearch,
              icon: const Icon(Icons.close),
            )
          else ...<Widget>[
            IconButton(
              tooltip: '노트 검색',
              onPressed: _openSearch,
              icon: const Icon(Icons.search),
            ),
            IconButton(
              tooltip: 'Drive에서 새로고침',
              onPressed: isOnline && scanProgress.status != ScanStatus.syncing
                  ? () async {
                      final vault = await ref.read(
                        selectedVaultProvider.future,
                      );
                      if (vault == null) return;
                      await ref
                          .read(vaultScannerProvider)
                          .manualRefresh(
                            vaultId: vault.id,
                            rootFolderId: vault.driveFolderId,
                            vaultName: vault.name,
                          );
                    }
                  : null,
              icon: const Icon(Icons.refresh),
            ),
            IconButton(
              tooltip: '오프라인 동기화',
              onPressed: isOnline && syncStatus.status != CacheSyncPhase.syncing
                  ? () => ref
                        .read(cacheSyncControllerProvider)
                        .checkForUpdates(widget.notes)
                  : null,
              icon: const Icon(Icons.sync),
            ),
            IconButton(
              tooltip: '설정',
              onPressed: () => context.go('/settings'),
              icon: const Icon(Icons.settings_outlined),
            ),
          ],
        ],
      ),
      body: Column(
        children: <Widget>[
          if (_isSearching)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: TextField(
                controller: _searchController,
                focusNode: _searchFocusNode,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: '노트 검색...',
                  prefixIcon: const Icon(Icons.search),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  contentPadding: const EdgeInsets.symmetric(vertical: 10),
                ),
                textInputAction: TextInputAction.search,
                onChanged: (value) {
                  setState(() {
                    _searchQuery = value;
                  });
                },
              ),
            ),
          if (!isOnline) const OfflineBanner(),
          if (!_isSearching) CacheProgress(status: syncStatus),
          if (!_isSearching &&
              scanProgress.status == ScanStatus.syncing &&
              scanProgress.phase == ScanPhase.fullScan)
            _FullScanProgress(progress: scanProgress),
          if (!_isSearching) _FavoriteNotesSection(vaultId: widget.vault.id),
          Expanded(
            child: _isSearching
                ? _NoteSearchResults(query: _searchQuery)
                : FolderTreeWidget(
                    vault: widget.vault,
                    folders: widget.folders,
                    notes: widget.notes,
                  ),
          ),
        ],
      ),
    );
  }

  void _openSearch() {
    setState(() {
      _isSearching = true;
    });
  }

  void _closeSearch() {
    _searchController.clear();
    setState(() {
      _isSearching = false;
      _searchQuery = '';
    });
  }
}

class _FavoriteNotesSection extends ConsumerWidget {
  const _FavoriteNotesSection({required this.vaultId});

  final int vaultId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final favorites = ref.watch(favoriteNotesProvider(vaultId));

    return favorites.when(
      data: (notes) {
        if (notes.isEmpty) {
          return const SizedBox.shrink();
        }

        final theme = Theme.of(context);
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Icon(Icons.star, size: 16, color: theme.colorScheme.primary),
                  const SizedBox(width: 6),
                  Text('즐겨찾기', style: theme.textTheme.titleSmall),
                ],
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 44,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: notes.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(width: 8),
                  itemBuilder: (context, index) {
                    final note = notes[index];
                    return OutlinedButton.icon(
                      onPressed: () => context.push('/reader', extra: note),
                      icon: const Icon(Icons.star, size: 16),
                      label: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 180),
                        child: Text(
                          note.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (error, stackTrace) => const SizedBox.shrink(),
    );
  }
}

class _NoteSearchResults extends ConsumerWidget {
  const _NoteSearchResults({required this.query});

  final String query;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final results = ref.watch(noteSearchProvider(query));

    return results.when(
      data: (notes) {
        if (notes.isEmpty) {
          return const Center(child: Text('검색 결과가 없습니다'));
        }

        return ListView.builder(
          itemCount: notes.length,
          itemBuilder: (context, index) {
            final note = notes[index];
            return ListTile(
              leading: const Icon(Icons.description_outlined),
              title: Text(
                note.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: _HighlightedPreview(note: note, query: query),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              onTap: () {
                context.push('/reader', extra: note);
              },
            );
          },
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stackTrace) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text('검색 중 오류가 발생했습니다.\n$error'),
        ),
      ),
    );
  }
}

class _HighlightedPreview extends StatelessWidget {
  const _HighlightedPreview({required this.note, required this.query});

  final Note note;
  final String query;

  @override
  Widget build(BuildContext context) {
    final preview = _buildPreview(note.content ?? '', query);
    if (preview.text.isEmpty) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    return RichText(
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      text: TextSpan(
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
        children: <TextSpan>[
          TextSpan(text: preview.before),
          if (preview.match.isNotEmpty)
            TextSpan(
              text: preview.match,
              style: TextStyle(
                backgroundColor: theme.colorScheme.secondaryContainer,
                color: theme.colorScheme.onSecondaryContainer,
                fontWeight: FontWeight.w700,
              ),
            ),
          TextSpan(text: preview.after),
        ],
      ),
    );
  }

  _PreviewText _buildPreview(String content, String query) {
    final normalized = content.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normalized.isEmpty) {
      return const _PreviewText('', '', '');
    }

    final trimmedQuery = query.trim();
    final matchIndex = trimmedQuery.isEmpty
        ? -1
        : normalized.toLowerCase().indexOf(trimmedQuery.toLowerCase());

    if (matchIndex == -1) {
      return _PreviewText(_truncate(normalized, 80), '', '');
    }

    final start = (matchIndex - 30).clamp(0, normalized.length).toInt();
    final matchEnd = (matchIndex + trimmedQuery.length)
        .clamp(0, normalized.length)
        .toInt();
    final end = (matchEnd + 50).clamp(0, normalized.length).toInt();
    final prefix = start > 0 ? '...' : '';
    final suffix = end < normalized.length ? '...' : '';

    return _PreviewText(
      '$prefix${normalized.substring(start, matchIndex)}',
      normalized.substring(matchIndex, matchEnd),
      '${normalized.substring(matchEnd, end)}$suffix',
    );
  }

  String _truncate(String text, int maxLength) {
    if (text.length <= maxLength) {
      return text;
    }
    return '${text.substring(0, maxLength)}...';
  }
}

class _PreviewText {
  const _PreviewText(this.before, this.match, this.after);

  final String before;
  final String match;
  final String after;

  String get text => '$before$match$after';
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
