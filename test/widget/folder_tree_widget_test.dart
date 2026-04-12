import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:obsidrive/features/vault/domain/vault_models.dart';
import 'package:obsidrive/features/vault/presentation/folder_tree_widget.dart';

void main() {
  testWidgets('folder expand/collapse reveals and hides child files', (
    tester,
  ) async {
    await tester.pumpWidget(treeApp(sampleNotes()));

    expect(find.text('Projects'), findsOneWidget);
    expect(find.text('Plan.md'), findsNothing);

    await tester.tap(find.text('Projects'));
    await tester.pumpAndSettle();

    expect(find.text('Plan.md'), findsOneWidget);

    await tester.tap(find.text('Projects'));
    await tester.pumpAndSettle();

    expect(find.text('Plan.md'), findsNothing);
  });

  testWidgets('only .md files are displayed', (tester) async {
    await tester.pumpWidget(
      treeApp(<Note>[
        note(id: 1, title: 'Markdown', path: 'Markdown.md'),
        note(id: 2, title: 'Image', path: 'Image.png'),
      ]),
    );

    expect(find.text('Markdown.md'), findsOneWidget);
    expect(find.text('Image.png'), findsNothing);
  });

  testWidgets('file tap navigates to reader', (tester) async {
    final opened = <Note>[];

    await tester.pumpWidget(treeApp(sampleNotes(), opened: opened));

    await tester.tap(find.text('Root.md'));
    await tester.pumpAndSettle();

    expect(opened.single.driveFileId, 'root-note');
    expect(find.text('Reader: Root'), findsOneWidget);
  });
}

Widget treeApp(List<Note> notes, {List<Note>? opened}) {
  return MaterialApp(
    routes: <String, WidgetBuilder>{
      '/reader': (context) {
        final note = ModalRoute.of(context)!.settings.arguments! as Note;
        opened?.add(note);
        return Scaffold(body: Text('Reader: ${note.title}'));
      },
    },
    home: Scaffold(body: FolderTreeWidget(notes: notes)),
  );
}

List<Note> sampleNotes() {
  return <Note>[
    note(id: 1, driveFileId: 'root-note', title: 'Root', path: 'Root.md'),
    note(id: 2, title: 'Plan', path: 'Projects/Plan.md'),
  ];
}

Note note({
  required int id,
  String? driveFileId,
  required String title,
  required String path,
}) {
  return Note(
    id: id,
    vaultId: 1,
    title: title,
    filePath: path,
    driveFileId: driveFileId ?? 'drive-$id',
    updatedAt: DateTime.utc(2026, 4, 13),
  );
}
