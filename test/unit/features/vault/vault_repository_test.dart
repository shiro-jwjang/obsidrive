import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:obsidrive/core/database.dart';
import 'package:obsidrive/features/vault/data/vault_repository.dart';

void main() {
  late AppDatabase db;
  late VaultRepository repository;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repository = VaultRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  test('searchNotes filters by vault and sorts title matches first', () async {
    await _insertNote(
      db,
      vaultId: 1,
      title: 'Project Plan',
      content: 'Schedule and tasks',
    );
    await _insertNote(
      db,
      vaultId: 1,
      title: 'Daily',
      content: 'Today I reviewed the project scope.',
    );
    await _insertNote(
      db,
      vaultId: 2,
      title: 'Other Project',
      content: 'Different vault',
    );

    final results = await repository.searchNotes(1, 'PROJECT');

    expect(results.map((note) => note.title), <String>[
      'Project Plan',
      'Daily',
    ]);
  });

  test('searchNotes limits results to 50', () async {
    for (var index = 0; index < 55; index += 1) {
      await _insertNote(
        db,
        vaultId: 1,
        title: 'Note $index',
        content: 'needle',
      );
    }

    final results = await repository.searchNotes(1, 'needle');

    expect(results, hasLength(50));
  });

  test('listDriveFileIds returns IDs for one vault only', () async {
    await _insertNote(
      db,
      vaultId: 1,
      title: 'One',
      content: '',
      driveFileId: 'drive-one',
    );
    await _insertNote(
      db,
      vaultId: 2,
      title: 'Two',
      content: '',
      driveFileId: 'drive-two',
    );

    final ids = await repository.listDriveFileIds(1);

    expect(ids, <String>{'drive-one'});
  });

  test('deleteNotesByDriveIds removes matching notes', () async {
    await _insertNote(
      db,
      vaultId: 1,
      title: 'Deleted',
      content: '',
      driveFileId: 'deleted-id',
    );
    await _insertNote(
      db,
      vaultId: 1,
      title: 'Kept',
      content: '',
      driveFileId: 'kept-id',
    );

    await repository.deleteNotesByDriveIds(<String>['deleted-id']);

    final remaining = await repository.listNotes(1);
    expect(remaining.map((note) => note.driveFileId), <String>['kept-id']);
  });
}

Future<void> _insertNote(
  AppDatabase db, {
  required int vaultId,
  required String title,
  required String content,
  String? driveFileId,
}) {
  return db
      .into(db.notes)
      .insert(
        NotesCompanion.insert(
          vaultId: Value(vaultId),
          title: Value(title),
          filePath: Value('$title.md'),
          driveFileId: Value(driveFileId ?? 'drive-$vaultId-$title'),
          content: Value(content),
        ),
      );
}
