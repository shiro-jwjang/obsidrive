import 'package:googleapis/drive/v3.dart' as drive;

import '../domain/vault_models.dart';

abstract class DriveFilesClient {
  Future<drive.FileList> list({
    required String q,
    int? pageSize,
    String? pageToken,
    String? fields,
  });
}

class DriveFilesListRequest {
  const DriveFilesListRequest({
    required this.q,
    this.pageSize,
    this.pageToken,
    this.fields,
  });

  final String q;
  final int? pageSize;
  final String? pageToken;
  final String? fields;
}

class GoogleDriveFilesClient implements DriveFilesClient {
  GoogleDriveFilesClient(drive.DriveApi api) : _api = api;

  final drive.DriveApi _api;

  @override
  Future<drive.FileList> list({
    required String q,
    int? pageSize,
    String? pageToken,
    String? fields,
  }) {
    return _api.files.list(
      q: q,
      pageSize: pageSize,
      pageToken: pageToken,
      $fields: fields,
      spaces: 'drive',
      orderBy: 'folder,name',
      supportsAllDrives: true,
      includeItemsFromAllDrives: true,
    );
  }
}

class DriveFolderService {
  DriveFolderService(this._filesClient, {this.pageSize = 1000});

  static const folderMimeType = 'application/vnd.google-apps.folder';

  final DriveFilesClient _filesClient;
  final int pageSize;

  Future<List<DriveFolder>> listFolders(String parentFolderId) async {
    final folders = <DriveFolder>[];
    var pageToken = null as String?;

    do {
      final response = await _filesClient.list(
        q: _folderQuery(parentFolderId),
        pageSize: pageSize,
        pageToken: pageToken,
        fields: 'nextPageToken, files(id, name, mimeType)',
      );

      folders.addAll(
        (response.files ?? const <drive.File>[])
            .where(_isFolder)
            .where((file) => file.id != null && file.name != null)
            .map((file) => DriveFolder(id: file.id!, name: file.name!)),
      );
      pageToken = response.nextPageToken;
    } while (pageToken != null);

    return folders;
  }

  Future<List<Note>> scanVault({
    required int vaultId,
    required String rootFolderId,
  }) async {
    final notes = <Note>[];
    await _scanFolder(
      notes: notes,
      vaultId: vaultId,
      folderId: rootFolderId,
      pathPrefix: '',
    );
    return notes;
  }

  Future<void> _scanFolder({
    required List<Note> notes,
    required int vaultId,
    required String folderId,
    required String pathPrefix,
  }) async {
    var pageToken = null as String?;

    do {
      final response = await _filesClient.list(
        q: _scanQuery(folderId),
        pageSize: pageSize,
        pageToken: pageToken,
        fields: 'nextPageToken, files(id, name, mimeType, modifiedTime)',
      );

      for (final file in response.files ?? const <drive.File>[]) {
        final name = file.name;
        final id = file.id;
        if (name == null || id == null) {
          continue;
        }

        if (_isFolder(file)) {
          if (name == '.obsidian') {
            continue;
          }

          await _scanFolder(
            notes: notes,
            vaultId: vaultId,
            folderId: id,
            pathPrefix: '$pathPrefix$name/',
          );
          continue;
        }

        if (!_isMarkdownFile(name)) {
          continue;
        }

        notes.add(
          Note(
            vaultId: vaultId,
            title: _titleFromName(name),
            filePath: '$pathPrefix$name',
            driveFileId: id,
            updatedAt: file.modifiedTime,
          ),
        );
      }

      pageToken = response.nextPageToken;
    } while (pageToken != null);
  }

  static bool _isFolder(drive.File file) => file.mimeType == folderMimeType;

  static bool _isMarkdownFile(String name) {
    return name.toLowerCase().endsWith('.md');
  }

  static String _titleFromName(String name) {
    return name.substring(0, name.length - 3);
  }

  static String _folderQuery(String parentFolderId) {
    return [
      "'${_escape(parentFolderId)}' in parents",
      "mimeType = '$folderMimeType'",
      'trashed = false',
    ].join(' and ');
  }

  static String _scanQuery(String parentFolderId) {
    return [
      "'${_escape(parentFolderId)}' in parents",
      "(mimeType = '$folderMimeType' or name contains '.md')",
      'trashed = false',
    ].join(' and ');
  }

  static String _escape(String value) => value.replaceAll("'", r"\'");
}
