import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:obsidrive/features/auth/data/auth_repository.dart';
import 'package:obsidrive/features/auth/domain/auth_state.dart';
import 'package:obsidrive/features/cache/data/cache_service.dart';
import 'package:obsidrive/features/cache/domain/cache_provider.dart';
import 'package:obsidrive/features/reader/data/note_content_repository.dart';
import 'package:obsidrive/features/reader/domain/reader_provider.dart';
import 'package:obsidrive/features/vault/domain/vault_models.dart';

void main() {
  late ProviderContainer container;
  late FakeNoteContentStore store;
  late FakeDriveContentClient driveClient;
  late FakeAuthRepository authRepository;

  setUp(() {
    store = FakeNoteContentStore();
    driveClient = FakeDriveContentClient();
    authRepository = FakeAuthRepository();

    container = ProviderContainer(
      overrides: [
        noteContentStoreProvider.overrideWithValue(store),
        driveFileContentClientProvider.overrideWithValue(driveClient),
        isOnlineProvider.overrideWithValue(true),
        cacheServiceProvider.overrideWithValue(FakeCacheService()),
        authRepositoryProvider.overrideWithValue(authRepository),
      ],
    );
  });

  tearDown(() {
    container.dispose();
  });

  Note makeNote({int id = 1, String driveFileId = 'note-1'}) => Note(
    id: id,
    vaultId: 1,
    title: 'Test Note',
    filePath: 'Test Note.md',
    driveFileId: driveFileId,
    isFavorite: false,
  );

  test(
    'noteContentProvider propagates Drive error as AsyncValue error',
    () async {
      driveClient.errorForFileId['note-1'] = Exception('401 Unauthorized');
      final note = makeNote();

      // FutureProvider.family needs await to trigger the fetch
      await expectLater(
        container.read(noteContentProvider(note).future),
        throwsA(isA<Exception>()),
      );
      expect(container.read(noteContentProvider(note)).hasError, true);
    },
  );

  test(
    'noteContentProvider fetches from Drive when store has no content',
    () async {
      driveClient.contents['note-1'] = '# Fresh';
      final note = makeNote();

      // Note exists in store but has no cached content
      store.notes[note.id] = note;

      final content = await container.read(noteContentProvider(note).future);
      expect(content, '# Fresh');
      expect(driveClient.downloadCount, 1);
    },
  );

  test(
    'noteContentProvider retries Drive fetch after invalidate removes cache',
    () async {
      // 1. Store note with cached content → no Drive call
      final note = makeNote().copyWith(
        content: const Value('# Cached'),
        cachedAt: Value(DateTime.now().toIso8601String()),
      );
      store.notes[note.id] = note;

      final content1 = await container.read(noteContentProvider(note).future);
      expect(content1, '# Cached');
      expect(driveClient.downloadCount, 0);

      // 2. Simulate cache cleared (e.g. DB reset) and Drive updated
      store.notes[note.id] = note.copyWith(
        content: const Value(null),
        cachedAt: const Value(null),
      );
      driveClient.contents['note-1'] = '# Updated from Drive';

      // 3. Invalidate → provider rebuilds → fetches from Drive
      container.invalidate(noteContentProvider(note));
      final content2 = await container.read(noteContentProvider(note).future);

      expect(content2, '# Updated from Drive');
      expect(driveClient.downloadCount, 1);
    },
  );

  test('noteContentProvider succeeds after Drive error is resolved', () async {
    // 1. First attempt: Drive returns error
    driveClient.errorForFileId['note-1'] = Exception('401 Unauthorized');
    final note = makeNote();
    store.notes[note.id] = note;

    await expectLater(
      container.read(noteContentProvider(note).future),
      throwsA(isA<Exception>()),
    );

    // 2. Fix: Drive is now accessible with new content
    driveClient.errorForFileId.remove('note-1');
    driveClient.contents['note-1'] = '# Recovered Content';

    // 3. Invalidate and retry
    container.invalidate(noteContentProvider(note));
    final content = await container.read(noteContentProvider(note).future);

    expect(content, '# Recovered Content');
    expect(driveClient.downloadCount, 2);
  });
}

class FakeNoteContentStore implements NoteContentStore {
  final notes = <int, Note>{};
  final saved = <Note>[];

  @override
  Future<Note?> getNote(int id) async => notes[id];

  @override
  Future<List<Note>> listNotes(int vaultId) async {
    return notes.values.where((n) => n.vaultId == vaultId).toList();
  }

  @override
  Future<Note> upsertNote(Note note) async {
    notes[note.id] = note;
    saved.add(note);
    return note;
  }
}

class FakeDriveContentClient implements DriveFileContentClient {
  final contents = <String, String>{};
  final errorForFileId = <String, Exception>{};
  int downloadCount = 0;

  @override
  Future<String> downloadMarkdown(String fileId) async {
    downloadCount += 1;
    final error = errorForFileId[fileId];
    if (error != null) throw error;
    return contents[fileId] ?? '';
  }

  @override
  Future<void> renameFile(String fileId, String name) async {}

  @override
  Future<void> uploadMarkdown(String fileId, String content) async {}
}

class FakeAuthRepository implements AuthRepository {
  AuthUser? signInUser;

  @override
  Future<AuthUser> signIn() async => signInUser!;

  @override
  Future<AuthUser?> restoreSession() async => null;

  @override
  Future<AuthUser> refreshToken() async => signInUser!;

  @override
  Future<void> signOut() async {}

  @override
  Future<void> clearSession() async {}
}

class FakeCacheService implements CacheService {
  @override
  Future<String?> getCachedNote(Note note) async => null;

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
