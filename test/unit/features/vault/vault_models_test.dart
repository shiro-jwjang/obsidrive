import 'package:flutter_test/flutter_test.dart';
import 'package:obsidrive/core/markdown_parser.dart';
import 'package:obsidrive/features/vault/domain/vault_models.dart';

void main() {
  group('Note', () {
    test('creates note with timestamps and parses date helpers', () {
      final note = _note(
        cachedAt: DateTime.utc(2026, 4, 13, 10),
        updatedAt: DateTime.utc(2026, 4, 13, 11),
      );

      expect(note.title, 'Daily Note');
      expect(note.filePath, 'Journal/Daily Note.md');
      expect(note.cachedAtDateTime, DateTime.utc(2026, 4, 13, 10));
      expect(note.updatedAtDateTime, DateTime.utc(2026, 4, 13, 11));
    });

    test('copyWithDateTime updates only provided date fields', () {
      final note = _note(cachedAt: DateTime.utc(2026, 4, 13, 10));

      final updated = note.copyWithDateTime(
        updatedAt: DateTime.utc(2026, 4, 14, 9),
      );

      expect(updated.cachedAt, note.cachedAt);
      expect(updated.updatedAt, DateTime.utc(2026, 4, 14, 9).toIso8601String());
    });
  });

  group('Vault', () {
    test('copyWithDateTime stores ISO timestamp', () {
      const vault = Vault(id: 1, name: 'Main', driveFolderId: 'drive-root');
      final syncedAt = DateTime.utc(2026, 4, 13, 9);

      final updated = vault.copyWithDateTime(lastSyncedAt: syncedAt);

      expect(updated.lastSyncedAt, syncedAt.toIso8601String());
      expect(updated.lastSyncedAtDateTime, syncedAt);
    });
  });

  group('FolderNode', () {
    test('copyWith keeps existing fields and replaces children', () {
      const child = FolderNode(id: 2, name: 'Child', driveFolderId: 'child');
      const folder = FolderNode(id: 1, name: 'Root', driveFolderId: 'root');

      final updated = folder.copyWith(children: <FolderNode>[child]);

      expect(updated.id, folder.id);
      expect(updated.name, folder.name);
      expect(updated.children, <FolderNode>[child]);
    });
  });

  group('Wikilink', () {
    test('parses path target and alias containing pipe characters', () {
      final link = parseWikilinks('See [[Projects/Plan.md|Plan | Q2]]').single;

      expect(link.target, 'Projects/Plan.md');
      expect(link.path, 'Projects');
      expect(link.title, 'Plan');
      expect(link.alias, 'Plan | Q2');
      expect(link.displayText, 'Plan | Q2');
    });

    test('ignores blank targets after trimming', () {
      final links = parseWikilinks('Empty [[   ]] link');

      expect(links, isEmpty);
    });

    test('resolves title and normalized path in vault notes', () {
      final notes = <Note>[
        _note(id: 1, title: 'Daily Note', filePath: 'Journal/Daily Note.md'),
        _note(id: 2, title: 'Plan', filePath: 'Projects/Plan.md'),
      ];

      expect(
        resolveInVault(parseWikilinks('[[daily note]]').single, notes),
        notes[0],
      );
      expect(
        resolveInVault(parseWikilinks('[[projects//plan]]').single, notes),
        notes[1],
      );
    });
  });
}

Note _note({
  int id = 1,
  String title = 'Daily Note',
  String filePath = 'Journal/Daily Note.md',
  DateTime? cachedAt,
  DateTime? updatedAt,
}) {
  return Note(
    id: id,
    vaultId: 7,
    title: title,
    filePath: filePath,
    driveFileId: 'drive-$id',
    cachedAt: cachedAt?.toIso8601String(),
    updatedAt: updatedAt?.toIso8601String(),
    isFavorite: false,
  );
}
