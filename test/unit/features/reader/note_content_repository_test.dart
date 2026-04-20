import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:obsidrive/features/cache/data/cache_service.dart';
import 'package:obsidrive/features/reader/data/note_content_repository.dart';
import 'package:obsidrive/features/vault/domain/vault_models.dart';

void main() {
  late DateTime now;
  late FakeNoteContentStore store;
  late FakeDriveFileContentClient driveClient;

  setUp(() {
    now = DateTime.utc(2026, 4, 13, 9);
    store = FakeNoteContentStore();
    driveClient = FakeDriveFileContentClient();
  });

  NoteContentRepository createRepository({
    CacheService? cacheService,
    bool Function()? isOnline,
  }) {
    return NoteContentRepository(
      store: store,
      driveClient: driveClient,
      cacheService: cacheService,
      isOnline: isOnline,
      now: () => now,
      staleAfter: const Duration(minutes: 30),
    );
  }

  test('getContent returns cached content when available', () async {
    final cached = note(
      content: '# Cached',
      cachedAt: now.subtract(const Duration(minutes: 5)),
    );
    store.notes[cached.id] = cached;

    final content = await createRepository().getContent(cached);

    expect(content, '# Cached');
    expect(driveClient.downloadedFileIds, isEmpty);
  });

  test('getContent fetches from Drive when not cached', () async {
    final uncached = note();
    store.notes[uncached.id] = uncached;
    driveClient.contents[uncached.driveFileId] = '# Fresh';

    final content = await createRepository().getContent(uncached);

    expect(content, '# Fresh');
    expect(driveClient.downloadedFileIds, <String>[uncached.driveFileId]);
    expect(store.notes[uncached.id]!.content, '# Fresh');
    expect(store.notes[uncached.id]!.cachedAt, now.toIso8601String());
  });

  test(
    'getContent returns stale content as-is (revalidation is separate)',
    () async {
      final stale = note(
        content: '# Old',
        cachedAt: now.subtract(const Duration(hours: 2)),
      );
      store.notes[stale.id] = stale;
      driveClient.contents[stale.driveFileId] = '# Fresh';

      // getContent returns whatever is in cache when content is non-null
      final content = await createRepository().getContent(stale);

      expect(content, '# Old');
      expect(driveClient.downloadedFileIds, isEmpty);
    },
  );

  test('revalidateIfNeeded re-fetches stale content', () async {
    final stale = note(
      content: '# Old',
      cachedAt: now.subtract(const Duration(hours: 2)),
    );
    store.notes[stale.id] = stale;
    driveClient.contents[stale.driveFileId] = '# Fresh';

    final content = await createRepository().revalidateIfNeeded(stale);

    expect(content, '# Fresh');
    expect(driveClient.downloadedFileIds, <String>[stale.driveFileId]);
    expect(store.notes[stale.id]!.content, '# Fresh');
    expect(store.notes[stale.id]!.cachedAt, now.toIso8601String());
  });

  test(
    'revalidateIfNeeded skips offline, fresh, uncached, and invalid updatedAt rows',
    () async {
      final fresh = note(
        content: '# Fresh',
        cachedAt: now.subtract(const Duration(minutes: 5)),
      );
      final uncached = note().copyWith(id: 2, driveFileId: 'uncached-drive');
      final invalidUpdatedAt =
          note(
            content: '# Old',
            cachedAt: now.subtract(const Duration(minutes: 5)),
          ).copyWith(
            id: 3,
            driveFileId: 'invalid-updated-drive',
            updatedAt: const Value('not-a-date'),
          );
      store.notes
        ..[fresh.id] = fresh
        ..[uncached.id] = uncached
        ..[invalidUpdatedAt.id] = invalidUpdatedAt;

      expect(
        await createRepository(isOnline: () => false).revalidateIfNeeded(fresh),
        isNull,
      );
      expect(await createRepository().revalidateIfNeeded(fresh), isNull);
      expect(await createRepository().revalidateIfNeeded(uncached), isNull);
      expect(
        await createRepository().revalidateIfNeeded(invalidUpdatedAt),
        isNull,
      );
      expect(driveClient.downloadedFileIds, isEmpty);
    },
  );

  test('revalidateIfNeeded treats invalid cachedAt as stale', () async {
    final stale = note(
      content: '# Old',
    ).copyWith(cachedAt: const Value('not-a-date'));
    store.notes[stale.id] = stale;
    driveClient.contents[stale.driveFileId] = '# Fresh';

    final content = await createRepository().revalidateIfNeeded(stale);

    expect(content, '# Fresh');
  });

  test('renameNote preserves markdown extension in Drive filename', () async {
    final original = note();
    store.notes[original.id] = original;

    final renamed = await createRepository().renameNote(original, 'New Title');

    expect(driveClient.renamedFiles, <String, String>{
      original.driveFileId: 'New Title.md',
    });
    expect(renamed.title, 'New Title');
    expect(renamed.filePath, 'New Title.md');
    expect(store.notes[original.id]!.title, 'New Title');
  });

  test(
    'renameNote preserves folder path and avoids duplicate md suffix',
    () async {
      final original = note().copyWith(filePath: 'Journal/Daily Note.md');
      store.notes[original.id] = original;

      final renamed = await createRepository().renameNote(
        original,
        'Weekly Note.md',
      );

      expect(driveClient.renamedFiles, <String, String>{
        original.driveFileId: 'Weekly Note.md',
      });
      expect(renamed.title, 'Weekly Note');
      expect(renamed.filePath, 'Journal/Weekly Note.md');
    },
  );

  test('saveContent uploads markdown and refreshes local cache', () async {
    final original = note();
    store.notes[original.id] = original;

    await createRepository().saveContent(original, '# Saved');

    expect(driveClient.uploadedFiles, <String, String>{
      original.driveFileId: '# Saved',
    });
    expect(store.notes[original.id]!.content, '# Saved');
    expect(store.notes[original.id]!.cachedAt, now.toIso8601String());
  });

  test(
    'getContent uses offline cache service before database content',
    () async {
      final cached = note(content: '# Database');
      store.notes[cached.id] = cached;
      final cacheService = FakeCacheService(cachedContent: '# Offline');

      final content = await createRepository(
        cacheService: cacheService,
        isOnline: () => false,
      ).getContent(cached);

      expect(content, '# Offline');
      expect(cacheService.requestedNotes.single.id, cached.id);
      expect(driveClient.downloadedFileIds, isEmpty);
    },
  );

  test('getContent falls back to database content while offline', () async {
    final cached = note(content: '# Database');
    store.notes[cached.id] = cached;

    final content = await createRepository(
      cacheService: FakeCacheService(),
      isOnline: () => false,
    ).getContent(cached);

    expect(content, '# Database');
  });

  test('getContent throws when offline content is unavailable', () async {
    final uncached = note();
    store.notes[uncached.id] = uncached;

    await expectLater(
      createRepository(
        cacheService: FakeCacheService(),
        isOnline: () => false,
      ).getContent(uncached),
      throwsA(isA<OfflineNoteUnavailableException>()),
    );
  });

  test('resolveNote matches normalized path and title targets', () async {
    store.notes
      ..[1] = note().copyWith(
        filePath: 'Projects/Daily Note.md',
        title: 'Daily Note',
      )
      ..[2] = note().copyWith(
        id: 2,
        filePath: 'Archive/Meeting.md',
        title: 'Meeting',
        driveFileId: 'meeting-drive',
      );

    expect(
      (await createRepository().resolveNote(7, 'projects//daily note'))?.id,
      1,
    );
    expect((await createRepository().resolveNote(7, 'meeting.md'))?.id, 2);
    expect(await createRepository().resolveNote(7, 'missing'), isNull);
  });

  test('resolveNote ignores notes from other vaults', () async {
    store.notes
      ..[1] = note().copyWith(title: 'Daily', filePath: 'Daily.md')
      ..[2] = note().copyWith(
        id: 2,
        vaultId: 99,
        title: 'Secret',
        filePath: 'Secret.md',
        driveFileId: 'secret-drive',
      );

    expect(await createRepository().resolveNote(7, 'Secret'), isNull);
    expect((await createRepository().resolveNote(7, 'daily'))?.id, 1);
  });

  test('renameNote handles files without markdown extension', () async {
    final original = note().copyWith(filePath: 'Inbox/Plain', title: 'Plain');
    store.notes[original.id] = original;

    final renamed = await createRepository().renameNote(original, 'Next');

    expect(driveClient.renamedFiles, <String, String>{
      original.driveFileId: 'Next',
    });
    expect(renamed.title, 'Next');
    expect(renamed.filePath, 'Inbox/Next');
  });

  test('renameNote rejects blank titles', () async {
    await expectLater(
      createRepository().renameNote(note(), '   '),
      throwsA(isA<ArgumentError>()),
    );
    expect(driveClient.renamedFiles, isEmpty);
  });
}

Note note({String? content, DateTime? cachedAt}) {
  return Note(
    id: 1,
    vaultId: 7,
    title: 'Daily Note',
    filePath: 'Daily Note.md',
    driveFileId: 'drive-note',
    content: content,
    cachedAt: cachedAt?.toIso8601String(),
    updatedAt: DateTime.utc(2026, 4, 13, 8).toIso8601String(),
    isFavorite: false,
  );
}

class FakeNoteContentStore implements NoteContentStore {
  final notes = <int, Note>{};

  @override
  Future<Note?> getNote(int id) async => notes[id];

  @override
  Future<List<Note>> listNotes(int vaultId) async {
    return notes.values.where((note) => note.vaultId == vaultId).toList();
  }

  @override
  Future<Note> upsertNote(Note note) async {
    notes[note.id] = note;
    return note;
  }
}

class FakeDriveFileContentClient implements DriveFileContentClient {
  final contents = <String, String>{};
  final downloadedFileIds = <String>[];
  final renamedFiles = <String, String>{};
  final uploadedFiles = <String, String>{};

  @override
  Future<String> downloadMarkdown(String fileId) async {
    downloadedFileIds.add(fileId);
    return contents[fileId] ?? '';
  }

  @override
  Future<void> uploadMarkdown(String fileId, String content) async {
    uploadedFiles[fileId] = content;
    contents[fileId] = content;
  }

  @override
  Future<void> renameFile(String fileId, String name) async {
    renamedFiles[fileId] = name;
  }
}

class FakeCacheService implements CacheService {
  FakeCacheService({this.cachedContent});

  final String? cachedContent;
  final requestedNotes = <Note>[];

  @override
  Future<String?> getCachedNote(Note note) async {
    requestedNotes.add(note);
    return cachedContent;
  }

  @override
  Future<CacheSummary> getSummary() async =>
      const CacheSummary(fileCount: 0, totalSizeBytes: 0);

  @override
  Future<void> syncVault(
    List<Note> notes, {
    void Function(CacheSyncStatus status)? onProgress,
  }) async {}

  @override
  Future<void> checkForUpdates(
    List<Note> notes, {
    void Function(CacheSyncStatus status)? onProgress,
  }) async {}
}
