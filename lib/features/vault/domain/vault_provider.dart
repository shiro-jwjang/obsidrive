import 'dart:async';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:googleapis/drive/v3.dart' as drive;
// ignore: depend_on_referenced_packages
import 'package:http/http.dart' as http;

import '../../../core/database.dart';
import '../../auth/domain/auth_state.dart';
import '../data/drive_folder_service.dart';
import '../data/vault_repository.dart';
import 'vault_models.dart';

final appDatabaseProvider = Provider<AppDatabase>((ref) {
  return AppDatabase();
});

final vaultRepositoryProvider = Provider<VaultRepository>((ref) {
  return VaultRepository(ref.watch(appDatabaseProvider));
});

final driveFolderServiceProvider = Provider<DriveFolderService>((ref) {
  final authState = ref.watch(authControllerProvider);
  final user = authState.user;
  if (user == null) {
    throw StateError('Google Drive requires an authenticated user.');
  }

  final client = _AuthenticatedHttpClient(user.authHeaders);
  ref.onDispose(client.close);
  return DriveFolderService(GoogleDriveFilesClient(drive.DriveApi(client)));
});

final vaultListProvider = FutureProvider<List<Vault>>((ref) {
  return ref.watch(vaultRepositoryProvider).listVaults();
});

final selectedVaultProvider = FutureProvider<Vault?>((ref) {
  return ref.watch(vaultRepositoryProvider).getSelectedVault();
});

/// All notes for the selected vault (for backward compat / full scan results).
final selectedVaultNotesProvider = FutureProvider<List<Note>>((ref) async {
  final vault = await ref.watch(selectedVaultProvider.future);
  if (vault == null) {
    return const <Note>[];
  }

  return ref.watch(vaultRepositoryProvider).listNotes(vault.id);
});

final favoriteNotesProvider = FutureProvider.family<List<Note>, int>((
  ref,
  vaultId,
) {
  final db = ref.watch(appDatabaseProvider);
  return (db.select(db.notes)
        ..where((t) => t.vaultId.equals(vaultId) & t.isFavorite.equals(true))
        ..orderBy([(t) => OrderingTerm.asc(t.title)]))
      .get();
});

final toggleFavoriteProvider = Provider<Future<Note> Function(Note)>((ref) {
  return (note) async {
    final db = ref.read(appDatabaseProvider);
    final updated = note.copyWith(isFavorite: !note.isFavorite);
    await (db.update(db.notes)..where((t) => t.id.equals(note.id))).write(
      NotesCompanion(isFavorite: Value(updated.isFavorite)),
    );
    ref.invalidate(favoriteNotesProvider(note.vaultId));
    ref.invalidate(selectedVaultNotesProvider);
    return updated;
  };
});

final noteSearchProvider = FutureProvider.family<List<Note>, String>((
  ref,
  query,
) async {
  final trimmed = query.trim();
  if (trimmed.isEmpty) {
    return const <Note>[];
  }

  var cancelled = false;
  final completer = Completer<void>();
  final timer = Timer(const Duration(milliseconds: 300), completer.complete);
  ref.onDispose(() {
    cancelled = true;
    timer.cancel();
    if (!completer.isCompleted) {
      completer.complete();
    }
  });
  await completer.future;
  if (cancelled) {
    return const <Note>[];
  }

  final vault = await ref.watch(selectedVaultProvider.future);
  if (vault == null) {
    return const <Note>[];
  }

  return ref.watch(vaultRepositoryProvider).searchNotes(vault.id, trimmed);
});

/// Tracks overall scan progress (quickSync + fullScan phases).
final scanProgressProvider = StateProvider<ScanProgress>((ref) {
  return const ScanProgress();
});

/// Tracks which folder IDs have had their notes lazy-loaded.
final loadedFolderIdsProvider = StateProvider<Set<String>>((ref) {
  return const <String>{};
});

/// Folder tree loaded during quickSync: a flat list of DriveFolder objects
/// representing all folders in the vault.
final folderTreeProvider = FutureProvider<List<DriveFolder>>((ref) async {
  final vault = await ref.watch(selectedVaultProvider.future);
  if (vault == null) {
    return const <DriveFolder>[];
  }

  final repo = ref.watch(vaultRepositoryProvider);
  final cachedFolders = await repo.listFolders(vault.id);
  if (cachedFolders.isNotEmpty) {
    return cachedFolders;
  }

  final service = ref.watch(driveFolderServiceProvider);
  final folders = await service.listAllFoldersRecursive(vault.driveFolderId);
  if (folders.isNotEmpty) {
    await repo.cacheFolders(vault.id, folders);
  }
  return folders;
});

/// Family provider that lazy-loads .md files for a specific folder.
/// The parameter is a [FolderLoadRequest] with vaultId, folderId, and pathPrefix.
final folderNotesProvider =
    FutureProvider.family<List<Note>, FolderLoadRequest>((ref, request) async {
      final repo = ref.watch(vaultRepositoryProvider);
      final service = ref.watch(driveFolderServiceProvider);

      // First check DB for existing notes in this folder path
      final existing = await repo.listNotesInFolder(
        request.vaultId,
        request.folderPath,
      );
      if (existing.isNotEmpty) {
        // Mark as loaded
        ref
            .read(loadedFolderIdsProvider.notifier)
            .update((s) => {...s, request.driveFolderId});
        return existing;
      }

      // Fetch from Drive API
      final companions = await service.listFilesInFolder(
        vaultId: request.vaultId,
        folderId: request.driveFolderId,
        pathPrefix: request.folderPath,
      );

      if (companions.isNotEmpty) {
        await repo.upsertNotes(request.vaultId, companions);
      }

      // Mark as loaded
      ref
          .read(loadedFolderIdsProvider.notifier)
          .update((s) => {...s, request.driveFolderId});

      // Return the notes from DB
      return repo.listNotesInFolder(request.vaultId, request.folderPath);
    });

final vaultScannerProvider = Provider<VaultScanner>((ref) {
  return VaultScanner(
    repository: ref.watch(vaultRepositoryProvider),
    driveFolderService: ref.watch(driveFolderServiceProvider),
    onProgress: (progress) {
      ref.read(scanProgressProvider.notifier).state = progress;
    },
    invalidateVaults: () {
      ref.invalidate(vaultListProvider);
      ref.invalidate(selectedVaultProvider);
      ref.invalidate(selectedVaultNotesProvider);
      ref.invalidate(folderTreeProvider);
    },
    invalidateFolderNotes: (folderId) {
      // Invalidate specific folder notes if needed
      ref.invalidate(loadedFolderIdsProvider);
    },
  );
});

/// Request object for lazy-loading folder notes.
class FolderLoadRequest {
  const FolderLoadRequest({
    required this.vaultId,
    required this.driveFolderId,
    required this.folderPath,
  });

  final int vaultId;
  final String driveFolderId;
  final String folderPath;

  @override
  bool operator ==(Object other) {
    return other is FolderLoadRequest &&
        other.vaultId == vaultId &&
        other.driveFolderId == driveFolderId &&
        other.folderPath == folderPath;
  }

  @override
  int get hashCode => Object.hash(vaultId, driveFolderId, folderPath);
}

class VaultScanner {
  const VaultScanner({
    required VaultRepository repository,
    required DriveFolderService driveFolderService,
    required void Function(ScanProgress progress) onProgress,
    required void Function() invalidateVaults,
    required void Function(String folderId) invalidateFolderNotes,
  }) : _repository = repository,
       _driveFolderService = driveFolderService,
       _onProgress = onProgress,
       _invalidateVaults = invalidateVaults,
       _invalidateFolderNotes = invalidateFolderNotes;

  final VaultRepository _repository;
  final DriveFolderService _driveFolderService;
  final void Function(ScanProgress progress) _onProgress;
  final void Function() _invalidateVaults;
  final void Function(String folderId) _invalidateFolderNotes;

  /// Quick sync: loads folder tree + top-level .md files.
  /// Returns the vault record immediately so UI can render.
  Future<Vault> quickSync(DriveFolder folder) async {
    _onProgress(
      const ScanProgress(
        status: ScanStatus.syncing,
        phase: ScanPhase.quickSync,
        currentFolder: '폴더 구조 로딩 중...',
      ),
    );

    try {
      // 1. Upsert vault
      final vault = await _repository.upsertVault(
        const Vault(
          id: -1,
          name: '',
          driveFolderId: '',
        ).copyWith(name: folder.name, driveFolderId: folder.id),
      );

      // 2. Load root-level .md files only (folder tree loaded by folderTreeProvider in background)
      _onProgress(
        const ScanProgress(
          status: ScanStatus.syncing,
          phase: ScanPhase.quickSync,
          currentFolder: '루트 파일 로딩 중...',
        ),
      );

      final rootNotes = await _driveFolderService.listFilesInFolder(
        vaultId: vault.id,
        folderId: folder.id,
        pathPrefix: '',
      );

      if (rootNotes.isNotEmpty) {
        await _repository.upsertNotes(vault.id, rootNotes);
      }

      // 4. Mark as selected
      await _repository.setSelectedVaultId(vault.id);

      _onProgress(
        ScanProgress(
          status: ScanStatus.complete,
          phase: ScanPhase.quickSync,
          totalFiles: rootNotes.length,
          syncedFiles: rootNotes.length,
          currentFolder: '빠른 동기화 완료',
        ),
      );

      _invalidateVaults();
      return vault;
    } catch (error) {
      _onProgress(
        ScanProgress(
          status: ScanStatus.error,
          phase: ScanPhase.quickSync,
          lastError: error.toString(),
        ),
      );
      rethrow;
    }
  }

  /// Background full scan: recursively scans all folders for complete index.
  /// This should be called after quickSync completes.
  Future<void> backgroundFullScan({
    required int vaultId,
    required String rootFolderId,
    required String vaultName,
  }) async {
    _onProgress(
      const ScanProgress(
        status: ScanStatus.syncing,
        phase: ScanPhase.fullScan,
        currentFolder: '전체 스캔 시작...',
      ),
    );

    try {
      final vault = await _repository.getVault(vaultId);
      final lastSyncedAt = vault?.lastSyncedAtDateTime;

      if (lastSyncedAt != null) {
        _onProgress(
          const ScanProgress(
            status: ScanStatus.syncing,
            phase: ScanPhase.fullScan,
            currentFolder: '변경된 파일 확인 중...',
          ),
        );

        final changedNotes = await _driveFolderService.listChangedFiles(
          vaultId: vaultId,
          rootFolderId: rootFolderId,
          since: lastSyncedAt,
        );

        if (changedNotes.isNotEmpty) {
          await _repository.upsertNotes(vaultId, changedNotes);
        }

        _onProgress(
          ScanProgress(
            status: ScanStatus.syncing,
            phase: ScanPhase.fullScan,
            totalFiles: changedNotes.length,
            syncedFiles: changedNotes.length,
            currentFolder: '삭제된 파일 확인 중...',
          ),
        );

        final allDriveFiles = await _driveFolderService.getAllFiles(
          rootFolderId,
        );
        final driveFileMap = {for (final file in allDriveFiles) file.id: file};
        final localIds = await _repository.listDriveFileIds(vaultId);

        final missingIds = driveFileMap.keys
            .where((id) => !localIds.contains(id))
            .toList();
        if (missingIds.isNotEmpty) {
          final missingNotes = missingIds
              .map((id) => driveFileMap[id]!.toNoteCompanion(vaultId: vaultId))
              .toList();
          await _repository.upsertNotes(vaultId, missingNotes);
        }

        final deletedIds = localIds
            .where((id) => !driveFileMap.containsKey(id))
            .toList();
        if (deletedIds.isNotEmpty) {
          await _repository.deleteNotesByDriveIds(deletedIds);
        }

        await _markVaultSynced(vaultId);
        _invalidateFolderNotes(rootFolderId);

        _onProgress(
          ScanProgress(
            status: ScanStatus.complete,
            phase: ScanPhase.fullScan,
            totalFiles: changedNotes.length,
            syncedFiles: changedNotes.length,
          ),
        );

        _invalidateVaults();
        return;
      }

      final notes = await _driveFolderService.scanVault(
        vaultId: vaultId,
        rootFolderId: rootFolderId,
        onProgress: (notesFound, currentFolder) {
          _onProgress(
            ScanProgress(
              status: ScanStatus.syncing,
              phase: ScanPhase.fullScan,
              totalFiles: notesFound,
              syncedFiles: notesFound,
              currentFolder: currentFolder.isEmpty ? vaultName : currentFolder,
            ),
          );
        },
      );

      _onProgress(
        ScanProgress(
          status: ScanStatus.syncing,
          phase: ScanPhase.fullScan,
          totalFiles: notes.length,
          syncedFiles: 0,
          currentFolder: '데이터베이스 저장 중...',
        ),
      );

      await _repository.bulkInsertNotes(vaultId, notes);
      _invalidateFolderNotes(rootFolderId);
      await _markVaultSynced(vaultId);

      _onProgress(
        ScanProgress(
          status: ScanStatus.complete,
          phase: ScanPhase.fullScan,
          totalFiles: notes.length,
          syncedFiles: notes.length,
        ),
      );

      _invalidateVaults();
    } catch (error) {
      _onProgress(
        ScanProgress(
          status: ScanStatus.error,
          phase: ScanPhase.fullScan,
          lastError: error.toString(),
        ),
      );
      // Don't rethrow — this is a background task
    }
  }

  /// Manually trigger a full scan refresh (user-initiated).
  Future<void> manualRefresh({
    required int vaultId,
    required String rootFolderId,
    required String vaultName,
  }) async {
    await backgroundFullScan(
      vaultId: vaultId,
      rootFolderId: rootFolderId,
      vaultName: vaultName,
    );
    _invalidateVaults();
  }

  Future<void> _markVaultSynced(int vaultId) async {
    final vault = await _repository.getVault(vaultId);
    if (vault == null) return;
    await _repository.upsertVault(
      vault.copyWithDateTime(lastSyncedAt: DateTime.now()),
    );
  }

  /// Legacy method: full scan and sync (kept for backward compatibility).
  Future<Vault> scanAndSyncVault(DriveFolder folder) async {
    // Use quickSync first, then background scan
    final vault = await quickSync(folder);

    // Start background full scan
    await backgroundFullScan(
      vaultId: vault.id,
      rootFolderId: folder.id,
      vaultName: folder.name,
    );

    return vault;
  }
}

class _AuthenticatedHttpClient extends http.BaseClient {
  _AuthenticatedHttpClient(this._headers);

  final Map<String, String> _headers;
  final http.Client _inner = http.Client();

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.headers.addAll(_headers);
    return _inner.send(request);
  }

  @override
  void close() {
    _inner.close();
    super.close();
  }
}
