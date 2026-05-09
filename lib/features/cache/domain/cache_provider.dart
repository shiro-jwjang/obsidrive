import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:drift/drift.dart' as drift;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:googleapis/drive/v3.dart' as drive;

import '../../../core/authenticated_http_client.dart';
import '../../../core/database.dart';
import '../../../core/storage.dart';
import '../../../core/storage_io.dart';
import '../../../core/storage_web.dart';
import '../../auth/domain/auth_state.dart';
import '../../reader/data/note_content_repository.dart';
import '../../vault/domain/vault_provider.dart';
import '../data/cache_service.dart';

final connectivityProvider = StreamProvider<List<ConnectivityResult>>((
  ref,
) async* {
  final connectivity = Connectivity();
  yield await connectivity.checkConnectivity();
  yield* connectivity.onConnectivityChanged;
});

final isOnlineProvider = Provider<bool>((ref) {
  final connectivity = ref.watch(connectivityProvider);
  final results = connectivity.valueOrNull;
  if (results == null || results.isEmpty) {
    return true;
  }

  return results.any((result) => result != ConnectivityResult.none);
});

final fileStorageProvider = Provider<FileStorage>((ref) {
  if (kIsWeb) {
    return WebFileStorage();
  }
  return IoFileStorage();
});

final cacheMetadataStoreProvider = Provider<CacheMetadataStore>((ref) {
  return DriftCacheMetadataStore(ref.watch(appDatabaseProvider));
});

final cacheDriveClientProvider = Provider<CacheDriveClient>((ref) {
  final authState = ref.watch(authControllerProvider);
  final user = authState.user;
  if (user == null) {
    throw StateError('Google Drive requires an authenticated user.');
  }

  final client = AuthenticatedHttpClient(
    headers: user.authHeaders,
    onAuthError: () async {
      final repo = ref.read(authRepositoryProvider);
      try {
        final refreshedUser = await repo.refreshToken();
        return refreshedUser.authHeaders;
      } catch (_) {
        ref.read(authControllerProvider.notifier).forceSignOut();
        return null;
      }
    },
  );
  ref.onDispose(client.close);
  return _CacheDriveClient(
    GoogleDriveFileContentClient(drive.DriveApi(client)),
  );
});

final cacheServiceProvider = Provider<CacheService>((ref) {
  return CacheService(
    store: ref.watch(cacheMetadataStoreProvider),
    driveClient: ref.watch(cacheDriveClientProvider),
    fileStorage: ref.watch(fileStorageProvider),
  );
});

final syncStatusProvider = StateProvider<CacheSyncStatus>((ref) {
  return const CacheSyncStatus();
});

final cacheSummaryProvider = FutureProvider<CacheSummary>((ref) {
  return ref.watch(cacheServiceProvider).getSummary();
});

final cacheSyncControllerProvider = Provider<CacheSyncController>((ref) {
  return CacheSyncController(
    cacheService: ref.watch(cacheServiceProvider),
    updateStatus: (status) {
      ref.read(syncStatusProvider.notifier).state = status;
    },
    invalidateSummary: () {
      ref.invalidate(cacheSummaryProvider);
    },
  );
});

/// Drift-backed implementation of [CacheMetadataStore].
///
/// Bridges between the domain [CacheFileMetadata] type and the
/// drift-generated [CacheFile] / [CacheFiles] table.
class DriftCacheMetadataStore implements CacheMetadataStore {
  DriftCacheMetadataStore(this._db);

  final AppDatabase _db;

  @override
  Future<CacheFileMetadata?> getCacheFile(String fileId) async {
    final row = await (_db.select(
      _db.cacheFiles,
    )..where((t) => t.fileId.equals(fileId))).getSingleOrNull();
    if (row == null) return null;
    return CacheFileMetadata(
      fileId: row.fileId,
      localPath: row.localPath,
      cachedAt: DateTime.parse(row.cachedAt),
      fileSize: row.fileSize,
    );
  }

  @override
  Future<CacheSummary> getCacheSummary() async {
    final rows = await _db
        .customSelect(
          'SELECT COUNT(*) AS file_count, COALESCE(SUM(file_size), 0) AS total_size FROM cache_files',
        )
        .get();
    final row = rows.single;
    return CacheSummary(
      fileCount: row.read<int>('file_count'),
      totalSizeBytes: row.read<int>('total_size'),
    );
  }

  @override
  Future<void> upsertCacheFile(CacheFileMetadata metadata) async {
    await _db
        .into(_db.cacheFiles)
        .insertOnConflictUpdate(
          CacheFilesCompanion(
            fileId: drift.Value(metadata.fileId),
            localPath: drift.Value(metadata.localPath),
            cachedAt: drift.Value(metadata.cachedAt.toIso8601String()),
            fileSize: drift.Value(metadata.fileSize),
          ),
        );
  }
}

class CacheSyncController {
  const CacheSyncController({
    required CacheService cacheService,
    required void Function(CacheSyncStatus status) updateStatus,
    required void Function() invalidateSummary,
  }) : _cacheService = cacheService,
       _updateStatus = updateStatus,
       _invalidateSummary = invalidateSummary;

  final CacheService _cacheService;
  final void Function(CacheSyncStatus status) _updateStatus;
  final void Function() _invalidateSummary;

  Future<void> syncVault(List<Note> notes) async {
    try {
      await _cacheService.syncVault(notes, onProgress: _updateStatus);
      _invalidateSummary();
    } catch (error) {
      _updateStatus(
        CacheSyncStatus(
          status: CacheSyncPhase.error,
          errorMessage: error.toString(),
        ),
      );
      rethrow;
    }
  }

  Future<void> checkForUpdates(List<Note> notes) async {
    try {
      await _cacheService.checkForUpdates(notes, onProgress: _updateStatus);
      _invalidateSummary();
    } catch (error) {
      _updateStatus(
        CacheSyncStatus(
          status: CacheSyncPhase.error,
          errorMessage: error.toString(),
        ),
      );
      rethrow;
    }
  }
}

class _CacheDriveClient implements CacheDriveClient {
  const _CacheDriveClient(this._inner);

  final DriveFileContentClient _inner;

  @override
  Future<String> downloadMarkdown(String fileId) {
    return _inner.downloadMarkdown(fileId);
  }
}
