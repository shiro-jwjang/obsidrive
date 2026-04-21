import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:obsidrive/core/markdown_parser.dart';
import 'package:obsidrive/features/cache/data/cache_service.dart';
import 'package:obsidrive/features/cache/domain/cache_provider.dart';
import 'package:obsidrive/features/reader/data/note_content_repository.dart';
import 'package:obsidrive/features/reader/domain/reader_provider.dart';
import 'package:obsidrive/features/vault/domain/vault_models.dart';

void main() {
  late FakeNoteContentStore store;
  late FakeDriveClient driveClient;
  late ProviderContainer container;

  setUp(() {
    store = FakeNoteContentStore();
    driveClient = FakeDriveClient();
    container = ProviderContainer(
      overrides: <Override>[
        noteContentStoreProvider.overrideWithValue(store),
        driveFileContentClientProvider.overrideWithValue(driveClient),
        isOnlineProvider.overrideWithValue(true),
        cacheServiceProvider.overrideWithValue(FakeCacheService()),
      ],
    );
  });

  tearDown(() {
    container.dispose();
  });

  test('currentNoteProvider and noteHistoryProvider start empty', () {
    expect(container.read(currentNoteProvider), isNull);
    expect(container.read(noteHistoryProvider), isEmpty);
  });

  test('noteContentProvider downloads content through repository', () async {
    final target = note(id: 1, title: 'Remote', driveFileId: 'remote');
    driveClient.downloads['remote'] = '# Remote';

    final content = await container.read(noteContentProvider(target).future);

    expect(content, '# Remote');
    expect(store.saved.single.content, '# Remote');
  });

  test(
    'backgroundRevalidateProvider returns null for fresh cached content',
    () async {
      final target = note(
        id: 1,
        title: 'Fresh',
        driveFileId: 'fresh',
        content: '# Fresh',
        cachedAt: DateTime.now().toIso8601String(),
      );
      store.notes[target.id] = target;

      expect(
        await container.read(backgroundRevalidateProvider(target).future),
        isNull,
      );
    },
  );

  test('vaultWikilinksProvider lists notes for a vault', () async {
    store.notes
      ..[1] = note(id: 1, title: 'One', driveFileId: 'one')
      ..[2] = note(id: 2, title: 'Two', driveFileId: 'two', vaultId: 2);

    final notes = await container.read(vaultWikilinksProvider(1).future);

    expect(notes.map((note) => note.title), <String>['One']);
  });

  test('parsedWikilinksProvider parses wiki links', () {
    final links = container.read(
      parsedWikilinksProvider('See [[Target|Alias]]'),
    );

    expect(links.single, isA<Wikilink>());
    expect(links.single.target, 'Target');
    expect(links.single.displayText, 'Alias');
  });
}

class FakeNoteContentStore implements NoteContentStore {
  final notes = <int, Note>{};
  final saved = <Note>[];

  @override
  Future<Note?> getNote(int id) async => notes[id];

  @override
  Future<List<Note>> listNotes(int vaultId) async {
    return notes.values.where((note) => note.vaultId == vaultId).toList();
  }

  @override
  Future<Note> upsertNote(Note note) async {
    notes[note.id] = note;
    saved.add(note);
    return note;
  }
}

class FakeDriveClient implements DriveFileContentClient {
  final downloads = <String, String>{};

  @override
  Future<String> downloadMarkdown(String fileId) async =>
      downloads[fileId] ?? '';

  @override
  Future<void> renameFile(String fileId, String name) async {}

  @override
  Future<void> uploadMarkdown(String fileId, String content) async {}
}

Note note({
  required int id,
  required String title,
  required String driveFileId,
  int vaultId = 1,
  String? content,
  String? cachedAt,
}) {
  return Note(
    id: id,
    vaultId: vaultId,
    title: title,
    filePath: '$title.md',
    driveFileId: driveFileId,
    content: content,
    cachedAt: cachedAt,
    isFavorite: false,
  );
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
