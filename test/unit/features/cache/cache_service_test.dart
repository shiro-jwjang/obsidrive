import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:obsidrive/features/cache/data/cache_service.dart';
import 'package:obsidrive/features/vault/domain/vault_models.dart';

void main() {
  late Directory directory;
  late FakeCacheStore store;
  late FakeDriveFileContentClient driveClient;
  late DateTime now;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('obsidrive_cache_test_');
    store = FakeCacheStore();
    driveClient = FakeDriveFileContentClient();
    now = DateTime.utc(2026, 4, 13, 10);
  });

  tearDown(() async {
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
  });

  CacheService createService() {
    return CacheService(
      store: store,
      driveClient: driveClient,
      storageDirectory: directory,
      now: () => now,
    );
  }

  test('syncVault downloads all .md files to local storage', () async {
    final notes = <Note>[
      note(id: 1, driveFileId: 'a', filePath: 'A.md'),
      note(id: 2, driveFileId: 'b', filePath: 'Folder/B.md'),
      note(id: 3, driveFileId: 'c', filePath: 'image.png'),
    ];
    driveClient.contents
      ..['a'] = '# A'
      ..['b'] = '# B'
      ..['c'] = 'ignored';
    final progresses = <CacheSyncStatus>[];

    await createService().syncVault(
      notes,
      onProgress: progresses.add,
    );

    expect(driveClient.downloadedFileIds, <String>['a', 'b']);
    expect(await File(store.files['a']!.localPath).readAsString(), '# A');
    expect(await File(store.files['b']!.localPath).readAsString(), '# B');
    expect(store.files.keys, unorderedEquals(<String>['a', 'b']));
    expect(progresses.last.status, CacheSyncPhase.complete);
    expect(progresses.last.syncedFiles, 2);
  });

  test('getCachedNote returns cached note content when offline', () async {
    final cached = note(driveFileId: 'offline-note', filePath: 'Offline.md');
    final path = '${directory.path}/offline-note.md';
    await File(path).writeAsString('# Offline');
    store.files[cached.driveFileId] = CacheFileMetadata(
      fileId: cached.driveFileId,
      localPath: path,
      cachedAt: now,
      fileSize: 9,
    );

    final content = await createService().getCachedNote(cached);

    expect(content, '# Offline');
  });

  test('getCachedNote returns null for uncached notes', () async {
    final content = await createService().getCachedNote(
      note(driveFileId: 'missing', filePath: 'Missing.md'),
    );

    expect(content, isNull);
  });

  test('checkForUpdates re-downloads only modified files', () async {
    final oldCachedAt = DateTime.utc(2026, 4, 13, 8);
    final unchanged = note(
      driveFileId: 'same',
      filePath: 'Same.md',
      updatedAt: DateTime.utc(2026, 4, 13, 7),
    );
    final modified = note(
      driveFileId: 'changed',
      filePath: 'Changed.md',
      updatedAt: DateTime.utc(2026, 4, 13, 9),
    );
    final samePath = '${directory.path}/same.md';
    final changedPath = '${directory.path}/changed.md';
    await File(samePath).writeAsString('# Same');
    await File(changedPath).writeAsString('# Old');
    store.files
      ..['same'] = CacheFileMetadata(
        fileId: 'same',
        localPath: samePath,
        cachedAt: oldCachedAt,
        fileSize: 6,
      )
      ..['changed'] = CacheFileMetadata(
        fileId: 'changed',
        localPath: changedPath,
        cachedAt: oldCachedAt,
        fileSize: 5,
      );
    driveClient.contents['changed'] = '# New';

    await createService().checkForUpdates(<Note>[unchanged, modified]);

    expect(driveClient.downloadedFileIds, <String>['changed']);
    expect(await File(changedPath).readAsString(), '# New');
    expect(await File(samePath).readAsString(), '# Same');
  });
}

Note note({
  int id = 1,
  String driveFileId = 'drive-note',
  String filePath = 'Note.md',
  DateTime? updatedAt,
}) {
  return Note(
    id: id,
    vaultId: 7,
    title: filePath.split('/').last.replaceAll('.md', ''),
    filePath: filePath,
    driveFileId: driveFileId,
    updatedAt: updatedAt ?? DateTime.utc(2026, 4, 13, 9),
  );
}

class FakeCacheStore implements CacheMetadataStore {
  final files = <String, CacheFileMetadata>{};

  @override
  Future<CacheFileMetadata?> getCacheFile(String fileId) async {
    return files[fileId];
  }

  @override
  Future<CacheSummary> getCacheSummary() async {
    final totalSize = files.values.fold<int>(
      0,
      (sum, file) => sum + file.fileSize,
    );
    return CacheSummary(fileCount: files.length, totalSizeBytes: totalSize);
  }

  @override
  Future<void> upsertCacheFile(CacheFileMetadata metadata) async {
    files[metadata.fileId] = metadata;
  }
}

class FakeDriveFileContentClient implements CacheDriveClient {
  final contents = <String, String>{};
  final downloadedFileIds = <String>[];

  @override
  Future<String> downloadMarkdown(String fileId) async {
    downloadedFileIds.add(fileId);
    return contents[fileId] ?? '';
  }
}
