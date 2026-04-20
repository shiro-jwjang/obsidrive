import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:obsidrive/core/database.dart';
import 'package:obsidrive/features/vault/data/drive_folder_service.dart';
import 'package:obsidrive/features/vault/domain/vault_models.dart';
import 'package:obsidrive/features/vault/domain/vault_provider.dart';

void main() {
  late AppDatabase db;
  late ProviderContainer container;
  late FakeDriveFolderService driveService;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    driveService = FakeDriveFolderService();
    container = ProviderContainer(
      overrides: <Override>[
        appDatabaseProvider.overrideWithValue(db),
        driveFolderServiceProvider.overrideWithValue(driveService),
      ],
    );
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  test('vaultRepositoryProvider uses the overridden database', () async {
    final repository = container.read(vaultRepositoryProvider);

    await repository.upsertVault(vault(name: 'Main', driveId: 'main'));

    expect(
      (await container.read(vaultListProvider.future)).single.name,
      'Main',
    );
  });

  test(
    'selectedVaultNotesProvider returns empty without a selected vault',
    () async {
      expect(await container.read(selectedVaultNotesProvider.future), isEmpty);
    },
  );

  test(
    'selectedVaultProvider and selectedVaultNotesProvider use selected vault',
    () async {
      final repository = container.read(vaultRepositoryProvider);
      final selected = await repository.upsertVault(
        vault(name: 'Selected', driveId: 'selected'),
      );
      await repository.setSelectedVaultId(selected.id);
      await repository.upsertNote(
        note(
          title: 'Selected Note',
          path: 'Selected.md',
          driveFileId: 'note-1',
        ),
      );

      expect(
        (await container.read(selectedVaultProvider.future))?.id,
        selected.id,
      );
      expect(
        (await container.read(selectedVaultNotesProvider.future)).single.title,
        'Selected Note',
      );
    },
  );

  test(
    'favoriteNotesProvider sorts favorites and toggleFavoriteProvider flips state',
    () async {
      final repository = container.read(vaultRepositoryProvider);
      final first = await repository.upsertNote(
        note(title: 'B Favorite', path: 'B.md', driveFileId: 'b'),
      );
      final second = await repository.upsertNote(
        note(title: 'A Favorite', path: 'A.md', driveFileId: 'a'),
      );

      await container.read(toggleFavoriteProvider)(first);
      await container.read(toggleFavoriteProvider)(second);

      final favorites = await container.read(favoriteNotesProvider(1).future);
      expect(favorites.map((note) => note.title), <String>[
        'A Favorite',
        'B Favorite',
      ]);

      final updated = await container.read(toggleFavoriteProvider)(
        favorites.first,
      );
      expect(updated.isFavorite, isFalse);
    },
  );

  test(
    'noteSearchProvider debounces, trims, and searches selected vault',
    () async {
      final repository = container.read(vaultRepositoryProvider);
      final selected = await repository.upsertVault(
        vault(name: 'Selected', driveId: 'selected'),
      );
      await repository.setSelectedVaultId(selected.id);
      await repository.upsertNote(
        note(title: 'Project Plan', path: 'Project.md', driveFileId: 'project'),
      );

      final results = await container.read(
        noteSearchProvider(' project ').future,
      );

      expect(results.single.title, 'Project Plan');
      expect(await container.read(noteSearchProvider('   ').future), isEmpty);
    },
  );

  test(
    'folderTreeProvider returns cached folders before calling Drive',
    () async {
      final repository = container.read(vaultRepositoryProvider);
      final selected = await repository.upsertVault(
        vault(name: 'Selected', driveId: 'selected'),
      );
      await repository.setSelectedVaultId(selected.id);
      await repository.cacheFolders(selected.id, const <DriveFolder>[
        DriveFolder(id: 'cached', name: 'Cached'),
      ]);

      final folders = await container.read(folderTreeProvider.future);

      expect(folders, const <DriveFolder>[
        DriveFolder(id: 'cached', name: 'Cached'),
      ]);
      expect(driveService.listAllFoldersRecursiveCalls, isEmpty);
    },
  );

  test(
    'folderTreeProvider fetches and caches folders when cache is empty',
    () async {
      final repository = container.read(vaultRepositoryProvider);
      final selected = await repository.upsertVault(
        vault(name: 'Selected', driveId: 'root'),
      );
      await repository.setSelectedVaultId(selected.id);
      driveService.recursiveFolders = const <DriveFolder>[
        DriveFolder(id: 'child', name: 'Child', parentId: 'root'),
      ];

      final folders = await container.read(folderTreeProvider.future);

      expect(folders, driveService.recursiveFolders);
      expect(driveService.listAllFoldersRecursiveCalls, <String>['root']);
      expect(
        await repository.listFolders(selected.id),
        driveService.recursiveFolders,
      );
    },
  );

  test(
    'folderNotesProvider returns existing DB notes and marks folder loaded',
    () async {
      final repository = container.read(vaultRepositoryProvider);
      await repository.upsertNote(
        note(
          title: 'Existing',
          path: 'Docs/Existing.md',
          driveFileId: 'existing',
        ),
      );

      final request = const FolderLoadRequest(
        vaultId: 1,
        driveFolderId: 'docs-folder',
        folderPath: 'Docs',
      );
      final notes = await container.read(folderNotesProvider(request).future);

      expect(notes.single.title, 'Existing');
      expect(container.read(loadedFolderIdsProvider), <String>{'docs-folder'});
      expect(driveService.listFilesInFolderCalls, isEmpty);
    },
  );

  test(
    'folderNotesProvider fetches Drive files when folder has no DB notes',
    () async {
      driveService.folderFiles = <NotesCompanion>[
        noteCompanion(
          title: 'Fetched',
          path: 'Docs/Fetched.md',
          driveFileId: 'fetched',
        ),
      ];

      final request = const FolderLoadRequest(
        vaultId: 1,
        driveFolderId: 'docs-folder',
        folderPath: 'Docs',
      );
      final notes = await container.read(folderNotesProvider(request).future);

      expect(notes.single.title, 'Fetched');
      expect(
        driveService.listFilesInFolderCalls.single.folderId,
        'docs-folder',
      );
      expect(container.read(loadedFolderIdsProvider), <String>{'docs-folder'});
    },
  );

  test('FolderLoadRequest equality includes vault, folder id, and path', () {
    const first = FolderLoadRequest(
      vaultId: 1,
      driveFolderId: 'folder',
      folderPath: 'Docs',
    );
    const same = FolderLoadRequest(
      vaultId: 1,
      driveFolderId: 'folder',
      folderPath: 'Docs',
    );
    const different = FolderLoadRequest(
      vaultId: 1,
      driveFolderId: 'other',
      folderPath: 'Docs',
    );

    expect(first, same);
    expect(first.hashCode, same.hashCode);
    expect(first, isNot(different));
  });

  test(
    'VaultScanner quickSync upserts vault, root notes, selection, and progress',
    () async {
      final progress = <ScanProgress>[];
      var invalidations = 0;
      driveService.folderFiles = <NotesCompanion>[
        noteCompanion(title: 'Root', path: 'Root.md', driveFileId: 'root-note'),
      ];
      final scanner = VaultScanner(
        repository: container.read(vaultRepositoryProvider),
        driveFolderService: driveService,
        onProgress: progress.add,
        invalidateVaults: () => invalidations += 1,
        invalidateFolderNotes: (_) {},
      );

      final vault = await scanner.quickSync(
        const DriveFolder(id: 'root', name: 'Vault'),
      );

      expect(vault.name, 'Vault');
      expect(
        (await container.read(vaultRepositoryProvider).getSelectedVault())?.id,
        vault.id,
      );
      expect(
        (await container.read(vaultRepositoryProvider).listNotes(vault.id))
            .single
            .title,
        'Root',
      );
      expect(progress.first.phase, ScanPhase.quickSync);
      expect(progress.last.status, ScanStatus.complete);
      expect(invalidations, 1);
    },
  );

  test(
    'VaultScanner backgroundFullScan bulk inserts notes for first scan',
    () async {
      final repository = container.read(vaultRepositoryProvider);
      final vaultRow = await repository.upsertVault(
        vault(name: 'Vault', driveId: 'root'),
      );
      final progress = <ScanProgress>[];
      var invalidations = 0;
      final invalidatedFolders = <String>[];
      driveService.scannedNotes = <NotesCompanion>[
        noteCompanion(
          title: 'Scanned',
          path: 'Scanned.md',
          driveFileId: 'scanned',
        ),
      ];
      final scanner = VaultScanner(
        repository: repository,
        driveFolderService: driveService,
        onProgress: progress.add,
        invalidateVaults: () => invalidations += 1,
        invalidateFolderNotes: invalidatedFolders.add,
      );

      await scanner.backgroundFullScan(
        vaultId: vaultRow.id,
        rootFolderId: 'root',
        vaultName: 'Vault',
      );

      expect((await repository.listNotes(vaultRow.id)).single.title, 'Scanned');
      expect((await repository.getVault(vaultRow.id))?.lastSyncedAt, isNotNull);
      expect(invalidatedFolders, <String>['root']);
      expect(progress.last.status, ScanStatus.complete);
      expect(invalidations, 1);
    },
  );

  test(
    'VaultScanner backgroundFullScan incrementally updates and deletes notes',
    () async {
      final repository = container.read(vaultRepositoryProvider);
      final vaultRow = await repository.upsertVault(
        vault(
          name: 'Vault',
          driveId: 'root',
          lastSyncedAt: '2026-04-19T00:00:00.000Z',
        ),
      );
      await repository.upsertNote(
        note(
          title: 'Old Title',
          path: 'Old.md',
          driveFileId: 'changed',
          updatedAt: '2026-04-18T00:00:00.000Z',
        ),
      );
      await repository.upsertNote(
        note(title: 'Deleted', path: 'Deleted.md', driveFileId: 'deleted'),
      );
      driveService.recursiveFolders = const <DriveFolder>[
        DriveFolder(id: 'docs', name: 'Docs', parentId: 'root'),
      ];
      driveService.allFiles = const <DriveFileInfo>[
        DriveFileInfo(
          id: 'changed',
          name: 'New Title.md',
          path: 'Docs/New Title.md',
          modifiedTime: '2026-04-20T00:00:00.000Z',
        ),
        DriveFileInfo(
          id: 'new',
          name: 'New.md',
          path: 'New.md',
          modifiedTime: '2026-04-20T00:00:00.000Z',
        ),
      ];
      final scanner = VaultScanner(
        repository: repository,
        driveFolderService: driveService,
        onProgress: (_) {},
        invalidateVaults: () {},
        invalidateFolderNotes: (_) {},
      );

      await scanner.backgroundFullScan(
        vaultId: vaultRow.id,
        rootFolderId: 'root',
        vaultName: 'Vault',
      );

      final notes = await repository.listNotes(vaultRow.id);
      expect(notes.map((note) => note.driveFileId), <String>['changed', 'new']);
      expect(notes.first.title, 'New Title');
      expect(notes.first.filePath, 'Docs/New Title.md');
    },
  );

  test('VaultScanner reports quickSync errors and rethrows', () async {
    driveService.error = StateError('drive failed');
    final progress = <ScanProgress>[];
    final scanner = VaultScanner(
      repository: container.read(vaultRepositoryProvider),
      driveFolderService: driveService,
      onProgress: progress.add,
      invalidateVaults: () {},
      invalidateFolderNotes: (_) {},
    );

    await expectLater(
      scanner.quickSync(const DriveFolder(id: 'root', name: 'Vault')),
      throwsA(isA<StateError>()),
    );
    expect(progress.last.status, ScanStatus.error);
    expect(progress.last.lastError, contains('drive failed'));
  });

  test('folderTreeProvider returns empty without selected vault', () async {
    expect(await container.read(folderTreeProvider.future), isEmpty);
    expect(driveService.listAllFoldersRecursiveCalls, isEmpty);
  });

  test('noteSearchProvider returns empty without selected vault', () async {
    expect(await container.read(noteSearchProvider('daily').future), isEmpty);
  });

  test(
    'VaultScanner backgroundFullScan catches Drive errors without rethrowing',
    () async {
      final repository = container.read(vaultRepositoryProvider);
      final vaultRow = await repository.upsertVault(
        vault(
          name: 'Vault',
          driveId: 'root',
          lastSyncedAt: '2026-04-19T00:00:00.000Z',
        ),
      );
      driveService.error = StateError('parallel failed');
      final progress = <ScanProgress>[];
      final scanner = VaultScanner(
        repository: repository,
        driveFolderService: driveService,
        onProgress: progress.add,
        invalidateVaults: () {},
        invalidateFolderNotes: (_) {},
      );

      await scanner.backgroundFullScan(
        vaultId: vaultRow.id,
        rootFolderId: 'root',
        vaultName: 'Vault',
      );

      expect(progress.last.status, ScanStatus.error);
      expect(progress.last.phase, ScanPhase.fullScan);
      expect(progress.last.lastError, contains('parallel failed'));
    },
  );

  test(
    'VaultScanner manualRefresh delegates to background scan and invalidates again',
    () async {
      final repository = container.read(vaultRepositoryProvider);
      final vaultRow = await repository.upsertVault(
        vault(name: 'Vault', driveId: 'root'),
      );
      driveService.scannedNotes = <NotesCompanion>[
        noteCompanion(
          title: 'Manual',
          path: 'Manual.md',
          driveFileId: 'manual',
        ),
      ];
      var invalidations = 0;
      final scanner = VaultScanner(
        repository: repository,
        driveFolderService: driveService,
        onProgress: (_) {},
        invalidateVaults: () => invalidations += 1,
        invalidateFolderNotes: (_) {},
      );

      await scanner.manualRefresh(
        vaultId: vaultRow.id,
        rootFolderId: 'root',
        vaultName: 'Vault',
      );

      expect((await repository.listNotes(vaultRow.id)).single.title, 'Manual');
      expect(invalidations, 2);
    },
  );

  test(
    'VaultScanner incremental scan builds folder paths and skips .obsidian descendants',
    () async {
      final repository = container.read(vaultRepositoryProvider);
      final vaultRow = await repository.upsertVault(
        vault(
          name: 'Vault',
          driveId: 'root',
          lastSyncedAt: '2026-04-19T00:00:00.000Z',
        ),
      );
      driveService.recursiveFolders = const <DriveFolder>[
        DriveFolder(id: 'docs', name: 'Docs', parentId: 'root'),
        DriveFolder(id: 'deep', name: 'Deep', parentId: 'docs'),
        DriveFolder(id: 'obsidian', name: '.obsidian', parentId: 'root'),
        DriveFolder(id: 'plugin', name: 'plugins', parentId: 'obsidian'),
      ];
      driveService.allFiles = const <DriveFileInfo>[
        DriveFileInfo(
          id: 'deep-note',
          name: 'Deep.md',
          path: 'Docs/Deep/Deep.md',
        ),
      ];
      final scanner = VaultScanner(
        repository: repository,
        driveFolderService: driveService,
        onProgress: (_) {},
        invalidateVaults: () {},
        invalidateFolderNotes: (_) {},
      );

      await scanner.backgroundFullScan(
        vaultId: vaultRow.id,
        rootFolderId: 'root',
        vaultName: 'Vault',
      );

      expect(driveService.fetchAllFilesParallelCalls.single.folderPathMap, {
        'docs': 'Docs',
        'deep': 'Docs/Deep',
      });
      expect(
        (await repository.listNotes(vaultRow.id)).single.filePath,
        'Docs/Deep/Deep.md',
      );
    },
  );
}

class FakeDriveFolderService extends DriveFolderService {
  FakeDriveFolderService() : super(_NoopDriveFilesClient());

  List<DriveFolder> recursiveFolders = const <DriveFolder>[];
  List<NotesCompanion> folderFiles = const <NotesCompanion>[];
  List<NotesCompanion> scannedNotes = const <NotesCompanion>[];
  List<DriveFileInfo> allFiles = const <DriveFileInfo>[];
  Object? error;
  final listAllFoldersRecursiveCalls = <String>[];
  final listFilesInFolderCalls = <FolderFileCall>[];
  final fetchAllFilesParallelCalls = <FetchAllFilesCall>[];

  @override
  Future<List<DriveFolder>> listAllFoldersRecursive(String rootFolderId) async {
    listAllFoldersRecursiveCalls.add(rootFolderId);
    return recursiveFolders;
  }

  @override
  Future<List<NotesCompanion>> listFilesInFolder({
    required int vaultId,
    required String folderId,
    required String pathPrefix,
  }) async {
    final currentError = error;
    if (currentError is Error) throw currentError;
    if (currentError is Exception) throw currentError;
    listFilesInFolderCalls.add(
      FolderFileCall(
        vaultId: vaultId,
        folderId: folderId,
        pathPrefix: pathPrefix,
      ),
    );
    return folderFiles;
  }

  @override
  Future<List<NotesCompanion>> scanVault({
    required int vaultId,
    required String rootFolderId,
    void Function(int notesFound, String currentFolder)? onProgress,
  }) async {
    final currentError = error;
    if (currentError is Error) throw currentError;
    if (currentError is Exception) throw currentError;
    onProgress?.call(scannedNotes.length, '');
    return scannedNotes;
  }

  @override
  Future<List<DriveFileInfo>> fetchAllFilesParallel(
    Map<String, String> folderPathMap, {
    required String rootFolderId,
    int concurrency = 5,
  }) async {
    final currentError = error;
    if (currentError is Error) throw currentError;
    if (currentError is Exception) throw currentError;
    fetchAllFilesParallelCalls.add(
      FetchAllFilesCall(
        folderPathMap: Map<String, String>.of(folderPathMap),
        rootFolderId: rootFolderId,
        concurrency: concurrency,
      ),
    );
    return allFiles;
  }
}

class FolderFileCall {
  const FolderFileCall({
    required this.vaultId,
    required this.folderId,
    required this.pathPrefix,
  });

  final int vaultId;
  final String folderId;
  final String pathPrefix;
}

class FetchAllFilesCall {
  const FetchAllFilesCall({
    required this.folderPathMap,
    required this.rootFolderId,
    required this.concurrency,
  });

  final Map<String, String> folderPathMap;
  final String rootFolderId;
  final int concurrency;
}

class _NoopDriveFilesClient implements DriveFilesClient {
  @override
  Future<drive.FileList> list({
    required String q,
    int? pageSize,
    String? pageToken,
    String? fields,
  }) {
    throw UnimplementedError();
  }
}

Vault vault({
  required String name,
  required String driveId,
  String? lastSyncedAt,
}) {
  return Vault(
    id: -1,
    name: name,
    driveFolderId: driveId,
    lastSyncedAt: lastSyncedAt,
  );
}

Note note({
  int id = -1,
  int vaultId = 1,
  required String title,
  required String path,
  required String driveFileId,
  String? content,
  String? updatedAt,
}) {
  return Note(
    id: id,
    vaultId: vaultId,
    title: title,
    filePath: path,
    driveFileId: driveFileId,
    content: content,
    updatedAt: updatedAt,
    isFavorite: false,
  );
}

NotesCompanion noteCompanion({
  required String title,
  required String path,
  required String driveFileId,
  String? updatedAt,
}) {
  return NotesCompanion.insert(
    vaultId: const Value(1),
    title: Value(title),
    filePath: Value(path),
    driveFileId: Value(driveFileId),
    updatedAt: Value(updatedAt),
  );
}
