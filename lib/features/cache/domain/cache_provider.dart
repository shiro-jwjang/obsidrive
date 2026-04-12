import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:googleapis/drive/v3.dart' as drive;
// ignore: depend_on_referenced_packages
import 'package:http/http.dart' as http;

import '../../auth/domain/auth_state.dart';
import '../../reader/data/note_content_repository.dart';
import '../../vault/domain/vault_models.dart';
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

final cacheMetadataStoreProvider = Provider<CacheMetadataStore>((ref) {
  return SqliteCacheMetadataStore(ref.watch(appDatabaseProvider));
});

final cacheDriveClientProvider = Provider<CacheDriveClient>((ref) {
  final authState = ref.watch(authControllerProvider);
  final user = authState.user;
  if (user == null) {
    throw StateError('Google Drive requires an authenticated user.');
  }

  final client = _AuthenticatedHttpClient(user.authHeaders);
  ref.onDispose(client.close);
  return _CacheDriveClient(
    GoogleDriveFileContentClient(drive.DriveApi(client)),
  );
});

final cacheServiceProvider = Provider<CacheService>((ref) {
  return CacheService(
    store: ref.watch(cacheMetadataStoreProvider),
    driveClient: ref.watch(cacheDriveClientProvider),
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
