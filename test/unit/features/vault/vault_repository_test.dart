import 'package:drift/drift.dart' show InsertMode, Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:obsidrive/core/database.dart';
import 'package:obsidrive/features/vault/data/vault_repository.dart';
import 'package:obsidrive/features/vault/domain/vault_models.dart';

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

  test('upsertVault inserts and then updates by drive folder id', () async {
    final inserted = await repository.upsertVault(
      const Vault(
        id: -1,
        name: 'Main',
        driveFolderId: 'drive-root',
        lastSyncedAt: '2026-04-20T00:00:00.000Z',
      ),
    );

    final updated = await repository.upsertVault(
      const Vault(
        id: -1,
        name: 'Renamed',
        driveFolderId: 'drive-root',
        lastSyncedAt: '2026-04-21T00:00:00.000Z',
      ),
    );

    expect(updated.id, inserted.id);
    expect(updated.name, 'Renamed');
    expect(await repository.listVaults(), hasLength(1));
  });

  test('deleteVault removes the vault row', () async {
    final inserted = await repository.upsertVault(
      const Vault(id: -1, name: 'Main', driveFolderId: 'drive-root'),
    );

    await repository.deleteVault(inserted.id);

    expect(await repository.getVault(inserted.id), isNull);
  });

  test('upsertNote inserts and then updates by drive file id', () async {
    final inserted = await repository.upsertNote(
      const Note(
        id: -1,
        vaultId: 1,
        title: 'Daily',
        filePath: 'Daily.md',
        driveFileId: 'daily-drive',
        isFavorite: false,
      ),
    );

    final updated = await repository.upsertNote(
      const Note(
        id: -1,
        vaultId: 1,
        title: 'Daily Updated',
        filePath: 'Journal/Daily Updated.md',
        driveFileId: 'daily-drive',
        content: '# Updated',
        cachedAt: '2026-04-21T00:00:00.000Z',
        updatedAt: '2026-04-21T01:00:00.000Z',
        isFavorite: false,
      ),
    );

    expect(updated.id, inserted.id);
    expect(updated.title, 'Daily Updated');
    expect(updated.content, '# Updated');
    expect(await repository.listNotes(1), hasLength(1));
  });

  test('listNotesInFolder returns root and direct child notes only', () async {
    await _insertNote(db, vaultId: 1, title: 'Root', content: '');
    await _insertNote(
      db,
      vaultId: 1,
      title: 'Direct',
      content: '',
      filePath: 'Docs/Direct.md',
    );
    await _insertNote(
      db,
      vaultId: 1,
      title: 'Nested',
      content: '',
      filePath: 'Docs/Deep/Nested.md',
    );

    expect(
      (await repository.listNotesInFolder(1, '')).map((note) => note.title),
      <String>['Root'],
    );
    expect(
      (await repository.listNotesInFolder(1, 'Docs')).map((note) => note.title),
      <String>['Direct'],
    );
  });

  test('selected vault id ignores missing and invalid settings', () async {
    expect(await repository.getSelectedVaultId(), isNull);

    await db
        .into(db.appSettings)
        .insert(
          const AppSettingsCompanion(
            key: Value('selected_vault_id'),
            value: Value('not-an-int'),
          ),
        );

    expect(await repository.getSelectedVaultId(), isNull);

    final vault = await repository.upsertVault(
      const Vault(id: -1, name: 'Main', driveFolderId: 'drive-root'),
    );
    await repository.setSelectedVaultId(vault.id);

    expect(await repository.getSelectedVaultId(), vault.id);
    expect((await repository.getSelectedVault())?.name, 'Main');
  });

  test(
    'cacheFolders handles empty, invalid, and valid folder settings',
    () async {
      expect(await repository.listFolders(1), isEmpty);

      await db
          .into(db.appSettings)
          .insert(
            const AppSettingsCompanion(
              key: Value('vault_1_folders'),
              value: Value('{}'),
            ),
            mode: InsertMode.insertOrReplace,
          );
      expect(await repository.listFolders(1), isEmpty);

      await repository.cacheFolders(1, const [
        DriveFolder(id: 'docs', name: 'Docs', parentId: 'root'),
      ]);

      final folders = await repository.listFolders(1);
      expect(folders.single.id, 'docs');
      expect(folders.single.parentId, 'root');
    },
  );
}

Future<void> _insertNote(
  AppDatabase db, {
  required int vaultId,
  required String title,
  required String content,
  String? driveFileId,
  String? filePath,
}) {
  return db
      .into(db.notes)
      .insert(
        NotesCompanion.insert(
          vaultId: Value(vaultId),
          title: Value(title),
          filePath: Value(filePath ?? '$title.md'),
          driveFileId: Value(driveFileId ?? 'drive-$vaultId-$title'),
          content: Value(content),
        ),
      );
}
