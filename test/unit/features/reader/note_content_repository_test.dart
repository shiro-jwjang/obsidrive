import 'package:flutter_test/flutter_test.dart';
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

  NoteContentRepository createRepository() {
    return NoteContentRepository(
      store: store,
      driveClient: driveClient,
      now: () => now,
      staleAfter: const Duration(minutes: 30),
    );
  }

  test('getContent returns cached content when available', () async {
    final cached = note(
      content: '# Cached',
      cachedAt: now.subtract(const Duration(minutes: 5)),
    );
    store.notes[cached.id!] = cached;

    final content = await createRepository().getContent(cached);

    expect(content, '# Cached');
    expect(driveClient.downloadedFileIds, isEmpty);
  });

  test('getContent fetches from Drive when not cached', () async {
    final uncached = note();
    store.notes[uncached.id!] = uncached;
    driveClient.contents[uncached.driveFileId] = '# Fresh';

    final content = await createRepository().getContent(uncached);

    expect(content, '# Fresh');
    expect(driveClient.downloadedFileIds, <String>[uncached.driveFileId]);
    expect(store.notes[uncached.id!]!.content, '# Fresh');
    expect(store.notes[uncached.id!]!.cachedAt, now);
  });

  test('getContent re-fetches when cache is stale', () async {
    final stale = note(
      content: '# Old',
      cachedAt: now.subtract(const Duration(hours: 2)),
    );
    store.notes[stale.id!] = stale;
    driveClient.contents[stale.driveFileId] = '# Fresh';

    final content = await createRepository().getContent(stale);

    expect(content, '# Fresh');
    expect(driveClient.downloadedFileIds, <String>[stale.driveFileId]);
    expect(store.notes[stale.id!]!.content, '# Fresh');
    expect(store.notes[stale.id!]!.cachedAt, now);
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
    cachedAt: cachedAt,
    updatedAt: DateTime.utc(2026, 4, 13, 8),
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
    notes[note.id!] = note;
    return note;
  }
}

class FakeDriveFileContentClient implements DriveFileContentClient {
  final contents = <String, String>{};
  final downloadedFileIds = <String>[];

  @override
  Future<String> downloadMarkdown(String fileId) async {
    downloadedFileIds.add(fileId);
    return contents[fileId] ?? '';
  }
}
