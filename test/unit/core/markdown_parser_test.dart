import 'package:flutter_test/flutter_test.dart';
import 'package:obsidrive/core/markdown_parser.dart';
import 'package:obsidrive/features/vault/domain/vault_models.dart';

void main() {
  group('parseFrontmatter', () {
    test('strips YAML dash-dash-dash block and returns content', () {
      const markdown = '''
---
title: Daily Note
---
# Daily Note

Body
''';

      expect(parseFrontmatter(markdown), '# Daily Note\n\nBody\n');
    });

    test('returns original text when no frontmatter', () {
      const markdown = '# Title\n\nBody';

      expect(parseFrontmatter(markdown), markdown);
    });

    test('handles multi-line YAML', () {
      const markdown = '''
---
title: Daily Note
tags:
  - work
  - notes
created: 2026-04-13
---
Content
''';

      expect(parseFrontmatter(markdown), 'Content\n');
    });
  });

  group('parseWikilinks', () {
    test('double-bracket with name only parsed as Wikilink', () {
      final links = parseWikilinks('Open [[Daily Note]] today');

      expect(links, <Wikilink>[
        const Wikilink(target: 'Daily Note', title: 'Daily Note'),
      ]);
    });

    test('double-bracket with pipe and alias parsed correctly', () {
      final links = parseWikilinks('Open [[Daily Note|today]]');

      expect(links, <Wikilink>[
        const Wikilink(
          target: 'Daily Note',
          title: 'Daily Note',
          alias: 'today',
        ),
      ]);
    });

    test('double-bracket with path separator parsed with path', () {
      final links = parseWikilinks('Open [[Projects/Plan]]');

      expect(links, <Wikilink>[
        const Wikilink(
          target: 'Projects/Plan',
          title: 'Plan',
          path: 'Projects',
        ),
      ]);
    });

    test('multiple wikilinks in one text', () {
      final links = parseWikilinks('[[One]] links to [[Two|second]]');

      expect(links, <Wikilink>[
        const Wikilink(target: 'One', title: 'One'),
        const Wikilink(target: 'Two', title: 'Two', alias: 'second'),
      ]);
    });

    test('resolveInVault returns null for missing notes', () {
      final link = parseWikilinks('Missing [[Ghost]]').single;

      expect(resolveInVault(link, const <Note>[]), isNull);
    });

    test('resolveInVault resolves title and path links', () {
      final notes = <Note>[
        note(id: 1, title: 'Daily Note', path: 'Daily Note.md'),
        note(id: 2, title: 'Plan', path: 'Projects/Plan.md'),
      ];

      expect(
        resolveInVault(parseWikilinks('[[Daily Note]]').single, notes),
        notes[0],
      );
      expect(
        resolveInVault(parseWikilinks('[[Projects/Plan]]').single, notes),
        notes[1],
      );
    });
  });
}

Note note({required int id, required String title, required String path}) {
  return Note(
    id: id,
    vaultId: 1,
    title: title,
    filePath: path,
    driveFileId: 'drive-$id',
  );
}
