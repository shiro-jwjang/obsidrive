import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:obsidrive/core/database.dart';
import 'package:obsidrive/core/storage.dart';
import 'package:obsidrive/features/cache/data/cache_service.dart';
import 'package:obsidrive/features/cache/domain/cache_provider.dart';
import 'package:obsidrive/features/vault/domain/vault_provider.dart';

void main() {
  late AppDatabase db;
  late ProviderContainer container;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    container = ProviderContainer(
      overrides: <Override>[appDatabaseProvider.overrideWithValue(db)],
    );
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  test('isOnlineProvider defaults to true while connectivity is loading', () {
    expect(container.read(isOnlineProvider), isTrue);
  });

  test(
    'isOnlineProvider reports false only when all results are none',
    () async {
      final offline = ProviderContainer(
        overrides: <Override>[
          connectivityProvider.overrideWith(
            (ref) => Stream<List<ConnectivityResult>>.value(
              const <ConnectivityResult>[ConnectivityResult.none],
            ),
          ),
        ],
      );
      final online = ProviderContainer(
        overrides: <Override>[
          connectivityProvider.overrideWith(
            (ref) => Stream<List<ConnectivityResult>>.value(
              const <ConnectivityResult>[ConnectivityResult.wifi],
            ),
          ),
        ],
      );
      addTearDown(offline.dispose);
      addTearDown(online.dispose);

      await offline.read(connectivityProvider.future);
      await online.read(connectivityProvider.future);

      expect(offline.read(isOnlineProvider), isFalse);
      expect(online.read(isOnlineProvider), isTrue);
    },
  );

  test(
    'isOnlineProvider treats an empty connectivity result as online',
    () async {
      final scoped = ProviderContainer(
        overrides: <Override>[
          connectivityProvider.overrideWith(
            (ref) => Stream<List<ConnectivityResult>>.value(
              const <ConnectivityResult>[],
            ),
          ),
        ],
      );
      addTearDown(scoped.dispose);

      await scoped.read(connectivityProvider.future);

      expect(scoped.read(isOnlineProvider), isTrue);
    },
  );

  test(
    'DriftCacheMetadataStore stores metadata and summarizes cache files',
    () async {
      final store = container.read(cacheMetadataStoreProvider);
      final cachedAt = DateTime.utc(2026, 4, 20, 1);

      await store.upsertCacheFile(
        CacheFileMetadata(
          fileId: 'a',
          localPath: '/cache/a.md',
          cachedAt: cachedAt,
          fileSize: 10,
        ),
      );
      await store.upsertCacheFile(
        CacheFileMetadata(
          fileId: 'b',
          localPath: '/cache/b.md',
          cachedAt: cachedAt,
          fileSize: 15,
        ),
      );

      final metadata = await store.getCacheFile('a');
      final summary = await store.getCacheSummary();

      expect(metadata?.localPath, '/cache/a.md');
      expect(metadata?.cachedAt, cachedAt);
      expect(summary.fileCount, 2);
      expect(summary.totalSizeBytes, 25);
      expect(await store.getCacheFile('missing'), isNull);
    },
  );

  test('cacheSummaryProvider reads from cacheServiceProvider', () async {
    final service = CacheService(
      store: FakeCacheStore(
        summary: const CacheSummary(fileCount: 3, totalSizeBytes: 4096),
      ),
      driveClient: FakeCacheDriveClient(),
      fileStorage: FakeFileStorage(),
    );
    final scoped = ProviderContainer(
      overrides: <Override>[cacheServiceProvider.overrideWithValue(service)],
    );
    addTearDown(scoped.dispose);

    final summary = await scoped.read(cacheSummaryProvider.future);

    expect(summary.fileCount, 3);
    expect(summary.totalSizeBytes, 4096);
  });

  test(
    'CacheSyncController updates status and invalidates summary after sync',
    () async {
      final store = FakeCacheStore();
      final driveClient = FakeCacheDriveClient(content: '# Cached');
      final service = CacheService(
        store: store,
        driveClient: driveClient,
        fileStorage: FakeFileStorage(),
        now: () => DateTime.utc(2026, 4, 20),
      );
      final scoped = ProviderContainer(
        overrides: <Override>[cacheServiceProvider.overrideWithValue(service)],
      );
      addTearDown(scoped.dispose);

      await scoped.read(cacheSyncControllerProvider).syncVault(<Note>[
        note(title: 'Cached', driveFileId: 'cached'),
      ]);

      final status = scoped.read(syncStatusProvider);
      expect(status.status, CacheSyncPhase.complete);
      expect(status.syncedFiles, 1);
      expect(store.files.keys, <String>['cached']);
    },
  );

  test(
    'CacheSyncController checkForUpdates completes and invalidates summary',
    () async {
      final store = FakeCacheStore();
      await store.upsertCacheFile(
        CacheFileMetadata(
          fileId: 'stale',
          localPath: '/cache/stale.md',
          cachedAt: DateTime.utc(2026, 4, 19),
          fileSize: 1,
        ),
      );
      final service = CacheService(
        store: store,
        driveClient: FakeCacheDriveClient(content: '# Updated'),
        fileStorage: FakeFileStorage(),
        now: () => DateTime.utc(2026, 4, 20),
      );
      final scoped = ProviderContainer(
        overrides: <Override>[cacheServiceProvider.overrideWithValue(service)],
      );
      addTearDown(scoped.dispose);

      final firstSummary = await scoped.read(cacheSummaryProvider.future);
      await scoped.read(cacheSyncControllerProvider).checkForUpdates(<Note>[
        note(title: 'Stale', driveFileId: 'stale'),
      ]);
      final secondSummary = await scoped.read(cacheSummaryProvider.future);

      expect(firstSummary.totalSizeBytes, 1);
      expect(scoped.read(syncStatusProvider).status, CacheSyncPhase.complete);
      expect(secondSummary.totalSizeBytes, '# Updated'.length);
    },
  );

  test(
    'CacheSyncController stores error status and rethrows failures',
    () async {
      final service = CacheService(
        store: FakeCacheStore(),
        driveClient: FakeCacheDriveClient(error: StateError('download failed')),
        fileStorage: FakeFileStorage(),
      );
      final scoped = ProviderContainer(
        overrides: <Override>[cacheServiceProvider.overrideWithValue(service)],
      );
      addTearDown(scoped.dispose);

      await expectLater(
        scoped.read(cacheSyncControllerProvider).checkForUpdates(<Note>[
          note(title: 'Broken', driveFileId: 'broken'),
        ]),
        throwsA(isA<StateError>()),
      );

      final status = scoped.read(syncStatusProvider);
      expect(status.status, CacheSyncPhase.error);
      expect(status.errorMessage, contains('download failed'));
    },
  );
}

class FakeCacheStore implements CacheMetadataStore {
  FakeCacheStore({
    this.summary = const CacheSummary(fileCount: 0, totalSizeBytes: 0),
  });

  final CacheSummary summary;
  final files = <String, CacheFileMetadata>{};

  @override
  Future<CacheFileMetadata?> getCacheFile(String fileId) async => files[fileId];

  @override
  Future<CacheSummary> getCacheSummary() async {
    if (files.isEmpty) return summary;
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

class FakeCacheDriveClient implements CacheDriveClient {
  FakeCacheDriveClient({this.content = '', this.error});

  final String content;
  final Object? error;

  @override
  Future<String> downloadMarkdown(String fileId) async {
    final currentError = error;
    if (currentError is Error) throw currentError;
    if (currentError is Exception) throw currentError;
    return content;
  }
}

class FakeFileStorage implements FileStorage {
  final data = <String, String>{};

  @override
  Future<bool> exists(String path) async => data.containsKey(path);

  @override
  Future<String> getCacheDirectory() async => '/cache';

  @override
  Future<int> length(String path) async => data[path]?.length ?? 0;

  @override
  Future<String> readString(String path) async => data[path] ?? '';

  @override
  Future<void> writeString(String path, String content) async {
    data[path] = content;
  }
}

Note note({required String title, required String driveFileId}) {
  return Note(
    id: 1,
    vaultId: 1,
    title: title,
    filePath: '$title.md',
    driveFileId: driveFileId,
    updatedAt: DateTime.utc(2026, 4, 20).toIso8601String(),
    isFavorite: false,
  );
}
