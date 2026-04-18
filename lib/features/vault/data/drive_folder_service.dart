import 'package:drift/drift.dart';
import 'package:googleapis/drive/v3.dart' as drive;

import '../../../core/database.dart';
import '../domain/vault_models.dart';

// ignore: one_member_abstracts
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

  /// List immediate child folders of [parentFolderId].
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
            .map(
              (file) => DriveFolder(
                id: file.id!,
                name: file.name!,
                parentId: parentFolderId,
              ),
            ),
      );
      pageToken = response.nextPageToken;
    } while (pageToken != null);

    return folders;
  }

  /// Recursively list all folders under [rootFolderId].
  /// Returns a flat list of all folders with parentId set.
  Future<List<DriveFolder>> listAllFoldersRecursive(String rootFolderId) async {
    final allFolders = <DriveFolder>[];
    await _collectFoldersRecursive(
      parentFolderId: rootFolderId,
      allFolders: allFolders,
    );
    return allFolders;
  }

  Future<void> _collectFoldersRecursive({
    required String parentFolderId,
    required List<DriveFolder> allFolders,
  }) async {
    final children = await listFolders(parentFolderId);
    allFolders.addAll(children);
    for (final child in children) {
      if (child.name == '.obsidian') continue;
      await _collectFoldersRecursive(
        parentFolderId: child.id,
        allFolders: allFolders,
      );
    }
  }

  /// List .md files in a specific folder (non-recursive, single API call).
  Future<List<NotesCompanion>> listFilesInFolder({
    required int vaultId,
    required String folderId,
    required String pathPrefix,
  }) async {
    final notes = <NotesCompanion>[];
    var pageToken = null as String?;

    do {
      final response = await _filesClient.list(
        q: _filesQuery(folderId),
        pageSize: pageSize,
        pageToken: pageToken,
        fields: 'nextPageToken, files(id, name, mimeType, modifiedTime)',
      );

      for (final file in response.files ?? const <drive.File>[]) {
        final name = file.name;
        final id = file.id;
        if (name == null || id == null) continue;
        if (!_isMarkdownFile(name)) continue;

        notes.add(
          NotesCompanion.insert(
            vaultId: Value(vaultId),
            title: Value(_titleFromName(name)),
            filePath: Value('$pathPrefix$name'),
            driveFileId: Value(id),
            updatedAt: Value(file.modifiedTime?.toIso8601String()),
          ),
        );
      }

      pageToken = response.nextPageToken;
    } while (pageToken != null);

    return notes;
  }

  /// Scans a vault folder recursively and returns all markdown notes.
  ///
  /// [onProgress] is called after each folder is processed with the current
  /// count of notes found and the folder path being scanned.
  Future<List<NotesCompanion>> scanVault({
    required int vaultId,
    required String rootFolderId,
    void Function(int notesFound, String currentFolder)? onProgress,
  }) async {
    final notes = <NotesCompanion>[];
    await _scanFolder(
      notes: notes,
      vaultId: vaultId,
      folderId: rootFolderId,
      pathPrefix: '',
      onProgress: onProgress,
    );
    return notes;
  }

  Future<void> _scanFolder({
    required List<NotesCompanion> notes,
    required int vaultId,
    required String folderId,
    required String pathPrefix,
    void Function(int notesFound, String currentFolder)? onProgress,
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
            onProgress: onProgress,
          );
          continue;
        }

        if (!_isMarkdownFile(name)) {
          continue;
        }

        notes.add(
          NotesCompanion.insert(
            vaultId: Value(vaultId),
            title: Value(_titleFromName(name)),
            filePath: Value('$pathPrefix$name'),
            driveFileId: Value(id),
            updatedAt: Value(file.modifiedTime?.toIso8601String()),
          ),
        );
      }

      pageToken = response.nextPageToken;
    } while (pageToken != null);

    onProgress?.call(notes.length, pathPrefix);
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

  /// Query for .md files only (no folders) in a specific parent.
  static String _filesQuery(String parentFolderId) {
    return [
      "'${_escape(parentFolderId)}' in parents",
      "mimeType != '$folderMimeType'",
      "name contains '.md'",
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
