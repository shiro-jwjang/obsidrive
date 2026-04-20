import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:obsidrive/core/database.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  test('creates all app tables and exposes schema version', () async {
    expect(db.schemaVersion, 3);

    await db
        .into(db.vaults)
        .insert(
          VaultsCompanion.insert(
            name: const Value('Main'),
            driveFolderId: const Value('drive-root'),
          ),
        );
    await db
        .into(db.notes)
        .insert(
          NotesCompanion.insert(
            vaultId: const Value(1),
            title: const Value('Daily'),
            filePath: const Value('Daily.md'),
            driveFileId: const Value('daily-drive'),
            content: const Value('# Daily'),
            isFavorite: const Value(true),
          ),
        );
    await db
        .into(db.wikilinkIndex)
        .insert(
          WikilinkIndexCompanion.insert(
            sourceNoteId: const Value(1),
            targetTitle: const Value('Other'),
          ),
        );
    await db
        .into(db.appSettings)
        .insert(
          AppSettingsCompanion.insert(
            key: const Value('selected_vault_id'),
            value: const Value('1'),
          ),
        );
    await db
        .into(db.cacheFiles)
        .insert(
          CacheFilesCompanion.insert(
            fileId: const Value('daily-drive'),
            localPath: const Value('/cache/daily.md'),
            cachedAt: Value(DateTime.utc(2026, 4, 21).toIso8601String()),
            fileSize: const Value(7),
          ),
        );

    expect(await db.select(db.vaults).get(), hasLength(1));
    expect((await db.select(db.notes).get()).single.isFavorite, isTrue);
    expect(await db.select(db.wikilinkIndex).get(), hasLength(1));
    expect((await db.select(db.appSettings).get()).single.value, '1');
    expect((await db.select(db.cacheFiles).get()).single.fileSize, 7);
  });

  test(
    'supports vault CRUD operations directly through drift tables',
    () async {
      final id = await db
          .into(db.vaults)
          .insert(
            VaultsCompanion.insert(
              name: const Value('Main'),
              driveFolderId: const Value('drive-root'),
              lastSyncedAt: const Value('2026-04-20T00:00:00.000Z'),
            ),
          );

      await (db.update(db.vaults)..where((t) => t.id.equals(id))).write(
        const VaultsCompanion(name: Value('Renamed')),
      );

      final renamed = await (db.select(
        db.vaults,
      )..where((t) => t.id.equals(id))).getSingle();
      expect(renamed.name, 'Renamed');
      expect(renamed.driveFolderId, 'drive-root');

      await (db.delete(db.vaults)..where((t) => t.id.equals(id))).go();

      expect(await db.select(db.vaults).get(), isEmpty);
    },
  );

  test('supports note CRUD and defaults isFavorite to false', () async {
    await db
        .into(db.vaults)
        .insert(
          VaultsCompanion.insert(
            name: const Value('Main'),
            driveFolderId: const Value('drive-root'),
          ),
        );
    final noteId = await db
        .into(db.notes)
        .insert(
          NotesCompanion.insert(
            vaultId: const Value(1),
            title: const Value('Daily'),
            filePath: const Value('Daily.md'),
            driveFileId: const Value('daily-drive'),
          ),
        );

    var row = await (db.select(
      db.notes,
    )..where((t) => t.id.equals(noteId))).getSingle();
    expect(row.isFavorite, isFalse);

    await (db.update(db.notes)..where((t) => t.id.equals(noteId))).write(
      const NotesCompanion(
        content: Value('# Daily'),
        cachedAt: Value('2026-04-20T01:00:00.000Z'),
        isFavorite: Value(true),
      ),
    );

    row = await (db.select(
      db.notes,
    )..where((t) => t.id.equals(noteId))).getSingle();
    expect(row.content, '# Daily');
    expect(row.isFavorite, isTrue);

    await (db.delete(db.notes)..where((t) => t.id.equals(noteId))).go();

    expect(await db.select(db.notes).get(), isEmpty);
  });

  test('app settings upsert stores selected vault id values', () async {
    await db
        .into(db.appSettings)
        .insert(
          AppSettingsCompanion.insert(
            key: const Value('selected_vault_id'),
            value: const Value('1'),
          ),
        );
    await db
        .into(db.appSettings)
        .insert(
          const AppSettingsCompanion(
            key: Value('selected_vault_id'),
            value: Value('2'),
          ),
          mode: InsertMode.insertOrReplace,
        );

    final row = await (db.select(
      db.appSettings,
    )..where((t) => t.key.equals('selected_vault_id'))).getSingle();

    expect(row.value, '2');
  });

  test('wikilink index stores aliases and target note references', () async {
    await db
        .into(db.vaults)
        .insert(
          VaultsCompanion.insert(
            name: const Value('Main'),
            driveFolderId: const Value('drive-root'),
          ),
        );
    final sourceId = await db
        .into(db.notes)
        .insert(
          NotesCompanion.insert(
            vaultId: const Value(1),
            title: const Value('Source'),
            filePath: const Value('Source.md'),
            driveFileId: const Value('source-drive'),
          ),
        );
    final targetId = await db
        .into(db.notes)
        .insert(
          NotesCompanion.insert(
            vaultId: const Value(1),
            title: const Value('Target'),
            filePath: const Value('Target.md'),
            driveFileId: const Value('target-drive'),
          ),
        );

    await db
        .into(db.wikilinkIndex)
        .insert(
          WikilinkIndexCompanion.insert(
            sourceNoteId: Value(sourceId),
            targetTitle: const Value('Target'),
            targetNoteId: Value(targetId),
            alias: const Value('Read next'),
          ),
        );

    final row = await db.select(db.wikilinkIndex).getSingle();
    expect(row.sourceNoteId, sourceId);
    expect(row.targetNoteId, targetId);
    expect(row.alias, 'Read next');
  });

  test(
    'deleting a note leaves orphaned wikilink index entries without PRAGMA foreign_keys',
    () async {
      await db
          .into(db.vaults)
          .insert(
            VaultsCompanion.insert(
              name: const Value('Main'),
              driveFolderId: const Value('drive-root'),
            ),
          );
      await db
          .into(db.notes)
          .insert(
            NotesCompanion.insert(
              vaultId: const Value(1),
              title: const Value('Source'),
              filePath: const Value('Source.md'),
              driveFileId: const Value('source-drive'),
            ),
          );
      await db
          .into(db.wikilinkIndex)
          .insert(
            WikilinkIndexCompanion.insert(
              sourceNoteId: const Value(1),
              targetTitle: const Value('Target'),
            ),
          );

      await (db.delete(db.notes)..where((t) => t.id.equals(1))).go();

      // Without PRAGMA foreign_keys = ON, wikilink index entry persists
      final remaining = await db.select(db.wikilinkIndex).get();
      expect(remaining, hasLength(1));
      expect(remaining.first.sourceNoteId, 1);
    },
  );
}
