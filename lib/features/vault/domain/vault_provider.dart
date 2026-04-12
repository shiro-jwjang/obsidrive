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

final selectedVaultNotesProvider = FutureProvider<List<Note>>((ref) async {
  final vault = await ref.watch(selectedVaultProvider.future);
  if (vault?.id == null) {
    return const <Note>[];
  }

  return ref.watch(vaultRepositoryProvider).listNotes(vault!.id!);
});

final scanProgressProvider = StateProvider<ScanProgress>((ref) {
  return const ScanProgress();
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
    },
  );
});

class VaultScanner {
  const VaultScanner({
    required VaultRepository repository,
    required DriveFolderService driveFolderService,
    required void Function(ScanProgress progress) onProgress,
    required void Function() invalidateVaults,
  }) : _repository = repository,
       _driveFolderService = driveFolderService,
       _onProgress = onProgress,
       _invalidateVaults = invalidateVaults;

  final VaultRepository _repository;
  final DriveFolderService _driveFolderService;
  final void Function(ScanProgress progress) _onProgress;
  final void Function() _invalidateVaults;

  Future<Vault> scanAndSyncVault(DriveFolder folder) async {
    _onProgress(const ScanProgress(status: ScanStatus.syncing));

    try {
      var vault = await _repository.upsertVault(
        Vault(name: folder.name, driveFolderId: folder.id),
      );
      final notes = await _driveFolderService.scanVault(
        vaultId: vault.id!,
        rootFolderId: folder.id,
      );
      _onProgress(
        ScanProgress(
          status: ScanStatus.syncing,
          totalFiles: notes.length,
          syncedFiles: 0,
        ),
      );

      await _repository.bulkInsertNotes(vault.id!, notes);
      vault = await _repository.upsertVault(
        vault.copyWith(lastSyncedAt: DateTime.now()),
      );
      await _repository.setSelectedVaultId(vault.id!);

      _onProgress(
        ScanProgress(
          status: ScanStatus.complete,
          totalFiles: notes.length,
          syncedFiles: notes.length,
        ),
      );
      _invalidateVaults();
      return vault;
    } catch (error) {
      _onProgress(
        ScanProgress(status: ScanStatus.error, lastError: error.toString()),
      );
      rethrow;
    }
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
