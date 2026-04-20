import 'package:flutter_test/flutter_test.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:obsidrive/features/vault/data/drive_folder_service.dart';
import 'package:obsidrive/features/vault/domain/vault_models.dart';

void main() {
  group('DriveFolderService', () {
    test('listFolders returns folder list from Drive API mock', () async {
      final client = FakeDriveFilesClient()
        ..queueResponse(
          drive.FileList(
            files: <drive.File>[
              drive.File(
                id: 'folder-a',
                name: 'Archive',
                mimeType: DriveFolderService.folderMimeType,
              ),
              drive.File(
                id: 'folder-b',
                name: 'Work',
                mimeType: DriveFolderService.folderMimeType,
              ),
            ],
          ),
        );
      final service = DriveFolderService(client);

      final folders = await service.listFolders('root');

      expect(folders, <DriveFolder>[
        const DriveFolder(id: 'folder-a', name: 'Archive'),
        const DriveFolder(id: 'folder-b', name: 'Work'),
      ]);
      expect(client.requests.single.q, contains("'root' in parents"));
      expect(
        client.requests.single.q,
        contains(DriveFolderService.folderMimeType),
      );
    });

    test(
      'scanVault returns NotesCompanion list recursively for .md files only',
      () async {
        final client = FakeDriveFilesClient()
          ..queueResponse(
            drive.FileList(
              files: <drive.File>[
                folder('folder-notes', 'Notes'),
                markdown('root-note', 'Root.md'),
                drive.File(
                  id: 'image',
                  name: 'photo.png',
                  mimeType: 'image/png',
                ),
              ],
            ),
          )
          ..queueResponse(
            drive.FileList(
              files: <drive.File>[
                markdown('nested-note', 'Nested.md'),
                drive.File(
                  id: 'todo',
                  name: 'todo.txt',
                  mimeType: 'text/plain',
                ),
              ],
            ),
          );
        final service = DriveFolderService(client);

        final notes = await service.scanVault(vaultId: 7, rootFolderId: 'root');

        expect(notes.map((n) => n.title.value), <String>['Nested', 'Root']);
        expect(notes.map((n) => n.filePath.value), <String>[
          'Notes/Nested.md',
          'Root.md',
        ]);
        expect(notes.every((n) => n.vaultId.value == 7), isTrue);
      },
    );

    test('scanVault paginates when 500+ files', () async {
      final firstPage = List<drive.File>.generate(
        500,
        (index) => markdown('note-$index', 'Note $index.md'),
      );
      final secondPage = List<drive.File>.generate(
        25,
        (index) => markdown('note-${index + 500}', 'Note ${index + 500}.md'),
      );
      final client = FakeDriveFilesClient()
        ..queueResponse(
          drive.FileList(files: firstPage, nextPageToken: 'page-2'),
        )
        ..queueResponse(drive.FileList(files: secondPage));
      final service = DriveFolderService(client, pageSize: 500);

      final notes = await service.scanVault(vaultId: 1, rootFolderId: 'root');

      expect(notes, hasLength(525));
      expect(client.requests, hasLength(2));
      expect(client.requests.last.pageToken, 'page-2');
    });

    test('scanVault excludes .obsidian folder', () async {
      final client = FakeDriveFilesClient()
        ..queueResponse(
          drive.FileList(
            files: <drive.File>[
              folder('obsidian', '.obsidian'),
              folder('notes', 'Notes'),
            ],
          ),
        )
        ..queueResponse(
          drive.FileList(files: <drive.File>[markdown('note', 'Visible.md')]),
        );
      final service = DriveFolderService(client);

      final notes = await service.scanVault(vaultId: 1, rootFolderId: 'root');

      expect(notes.map((n) => n.filePath.value), <String>['Notes/Visible.md']);
      expect(client.requests, hasLength(2));
      expect(client.requests.last.q, contains("'notes' in parents"));
    });

    test('listFilesInFolder separates folder path from file name', () async {
      final client = FakeDriveFilesClient()
        ..queueResponse(
          drive.FileList(
            files: <drive.File>[
              markdown('root-note', 'Root.md'),
              drive.File(id: 'image', name: 'photo.png', mimeType: 'image/png'),
            ],
          ),
        );
      final service = DriveFolderService(client);

      final notes = await service.listFilesInFolder(
        vaultId: 7,
        folderId: 'folder-notes',
        pathPrefix: 'Notes',
      );

      expect(notes.map((note) => note.filePath.value), <String>[
        'Notes/Root.md',
      ]);
    });

    test(
      'getAllFiles returns markdown metadata with recursive paths',
      () async {
        final modified = DateTime.utc(2026, 1, 2, 3, 4, 5);
        final client = FakeDriveFilesClient()
          ..queueResponse(
            drive.FileList(
              files: <drive.File>[
                folder('folder-notes', 'Notes'),
                markdown('root-note', 'Root.md', modifiedTime: modified),
                drive.File(
                  id: 'image',
                  name: 'photo.png',
                  mimeType: 'image/png',
                ),
              ],
            ),
          )
          ..queueResponse(
            drive.FileList(
              files: <drive.File>[markdown('nested', 'Nested.md')],
            ),
          );
        final service = DriveFolderService(client);

        final files = await service.getAllFiles('root');

        expect(files.map((file) => file.id), <String>['nested', 'root-note']);
        expect(files.map((file) => file.path), <String>[
          'Notes/Nested.md',
          'Root.md',
        ]);
        expect(files.last.modifiedTime, modified.toIso8601String());
        expect(client.requests.first.fields, contains('modifiedTime'));
      },
    );

    test(
      'fetchAllFilesParallel fetches root and folder files with paths',
      () async {
        final modified = DateTime.utc(2026, 1, 2, 3, 4, 5);
        final client = FakeDriveFilesClient()
          ..queueResponse(
            drive.FileList(
              files: <drive.File>[
                markdown('root-note', 'Root.md', modifiedTime: modified),
                drive.File(
                  id: 'image',
                  name: 'photo.png',
                  mimeType: 'image/png',
                ),
              ],
            ),
          )
          ..queueResponse(
            drive.FileList(
              files: <drive.File>[markdown('nested', 'Nested.md')],
            ),
          )
          ..queueResponse(
            drive.FileList(files: <drive.File>[markdown('todo', 'Todo.md')]),
          );
        final service = DriveFolderService(client);

        final files = await service.fetchAllFilesParallel(
          const <String, String>{
            'folder-notes': 'Notes',
            'folder-projects': 'Projects/Active',
          },
          rootFolderId: 'root',
          concurrency: 2,
        );

        expect(files.map((file) => file.path), <String>[
          'Root.md',
          'Notes/Nested.md',
          'Projects/Active/Todo.md',
        ]);
        expect(files.first.modifiedTime, modified.toIso8601String());
        expect(client.requests, hasLength(3));
        expect(client.requests[0].q, contains("'root' in parents"));
        expect(client.requests[1].q, contains("'folder-notes' in parents"));
        expect(client.requests[2].q, contains("'folder-projects' in parents"));
        expect(client.requests.first.q, contains("name contains '.md'"));
      },
    );
  });
}

drive.File folder(String id, String name) {
  return drive.File(
    id: id,
    name: name,
    mimeType: DriveFolderService.folderMimeType,
  );
}

drive.File markdown(String id, String name, {DateTime? modifiedTime}) {
  return drive.File(
    id: id,
    name: name,
    mimeType: 'text/markdown',
    modifiedTime: modifiedTime,
  );
}

class FakeDriveFilesClient implements DriveFilesClient {
  final requests = <DriveFilesListRequest>[];
  final _responses = <drive.FileList>[];

  void queueResponse(drive.FileList response) {
    _responses.add(response);
  }

  @override
  Future<drive.FileList> list({
    required String q,
    int? pageSize,
    String? pageToken,
    String? fields,
  }) async {
    requests.add(
      DriveFilesListRequest(
        q: q,
        pageSize: pageSize,
        pageToken: pageToken,
        fields: fields,
      ),
    );
    return _responses.removeAt(0);
  }
}
