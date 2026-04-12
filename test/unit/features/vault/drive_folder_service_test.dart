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
      'scanVault returns Note list recursively for .md files only',
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

        expect(notes.map((note) => note.title), <String>['Nested', 'Root']);
        expect(notes.map((note) => note.filePath), <String>[
          'Notes/Nested.md',
          'Root.md',
        ]);
        expect(notes.every((note) => note.vaultId == 7), isTrue);
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

      expect(notes.map((note) => note.filePath), <String>['Notes/Visible.md']);
      expect(client.requests, hasLength(2));
      expect(client.requests.last.q, contains("'notes' in parents"));
    });
  });
}

drive.File folder(String id, String name) {
  return drive.File(
    id: id,
    name: name,
    mimeType: DriveFolderService.folderMimeType,
  );
}

drive.File markdown(String id, String name) {
  return drive.File(id: id, name: name, mimeType: 'text/markdown');
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
