import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../../../core/database.dart';
import '../../vault/domain/vault_models.dart';

class CacheService {
  CacheService({
    required CacheMetadataStore store,
    required CacheDriveClient driveClient,
    Directory? storageDirectory,
    DateTime Function()? now,
  }) : _store = store,
       _driveClient = driveClient,
       _storageDirectory = storageDirectory,
       _now = now ?? DateTime.now;

  final CacheMetadataStore _store;
  final CacheDriveClient _driveClient;
  final Directory? _storageDirectory;
  final DateTime Function() _now;

  Future<void> syncVault(
    List<Note> notes, {
    void Function(CacheSyncStatus status)? onProgress,
  }) async {
    final markdownNotes = notes.where(_isMarkdownNote).toList();
    onProgress?.call(
      CacheSyncStatus(
        status: CacheSyncPhase.syncing,
        totalFiles: markdownNotes.length,
      ),
    );

    var syncedFiles = 0;
    for (final note in markdownNotes) {
      await _downloadToCache(note);
      syncedFiles += 1;
      onProgress?.call(
        CacheSyncStatus(
          status: CacheSyncPhase.syncing,
          totalFiles: markdownNotes.length,
          syncedFiles: syncedFiles,
        ),
      );
    }

    onProgress?.call(
      CacheSyncStatus(
        status: CacheSyncPhase.complete,
        totalFiles: markdownNotes.length,
        syncedFiles: syncedFiles,
      ),
    );
  }

  Future<String?> getCachedNote(Note note) async {
    final metadata = await _store.getCacheFile(note.driveFileId);
    if (metadata == null) {
      return null;
    }

    final file = File(metadata.localPath);
    if (!await file.exists()) {
      return null;
    }

    return file.readAsString();
  }

  Future<void> checkForUpdates(
    List<Note> notes, {
    void Function(CacheSyncStatus status)? onProgress,
  }) async {
    final modifiedNotes = <Note>[];
    for (final note in notes.where(_isMarkdownNote)) {
      final metadata = await _store.getCacheFile(note.driveFileId);
      if (metadata == null || _isDriveVersionNewer(note, metadata)) {
        modifiedNotes.add(note);
      }
    }

    await syncVault(modifiedNotes, onProgress: onProgress);
  }

  Future<CacheSummary> getSummary() {
    return _store.getCacheSummary();
  }

  Future<void> _downloadToCache(Note note) async {
    final content = await _driveClient.downloadMarkdown(note.driveFileId);
    final directory = await _cacheDirectory();
    final file = File('${directory.path}/${_cacheFileName(note)}');
    await file.writeAsString(content, flush: true);
    final fileSize = await file.length();
    await _store.upsertCacheFile(
      CacheFileMetadata(
        fileId: note.driveFileId,
        localPath: file.path,
        cachedAt: _now(),
        fileSize: fileSize,
      ),
    );
  }

  Future<Directory> _cacheDirectory() async {
    final base = _storageDirectory ?? await getApplicationDocumentsDirectory();
    final directory = Directory('${base.path}/offline_cache');
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }

    return directory;
  }

  bool _isDriveVersionNewer(Note note, CacheFileMetadata metadata) {
    final driveModifiedTime = note.updatedAt;
    if (driveModifiedTime == null) {
      return false;
    }

    return driveModifiedTime.isAfter(metadata.cachedAt);
  }

  static bool _isMarkdownNote(Note note) {
    return note.filePath.toLowerCase().endsWith('.md');
  }

  static String _cacheFileName(Note note) {
    final encoded = base64Url.encode(utf8.encode(note.driveFileId));
    return '$encoded.md';
  }
}

abstract class CacheMetadataStore {
  Future<CacheFileMetadata?> getCacheFile(String fileId);

  Future<void> upsertCacheFile(CacheFileMetadata metadata);

  Future<CacheSummary> getCacheSummary();
}

abstract class CacheDriveClient {
  Future<String> downloadMarkdown(String fileId);
}

class SqliteCacheMetadataStore implements CacheMetadataStore {
  SqliteCacheMetadataStore(this._appDatabase);

  final AppDatabase _appDatabase;

  @override
  Future<CacheFileMetadata?> getCacheFile(String fileId) async {
    final db = await _appDatabase.database;
    final rows = await db.query(
      'cache_files',
      where: 'file_id = ?',
      whereArgs: <Object?>[fileId],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }

    return CacheFileMetadata.fromMap(rows.single);
  }

  @override
  Future<CacheSummary> getCacheSummary() async {
    final db = await _appDatabase.database;
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS file_count, COALESCE(SUM(file_size), 0) AS total_size FROM cache_files',
    );
    final row = rows.single;
    return CacheSummary(
      fileCount: row['file_count'] as int? ?? 0,
      totalSizeBytes: row['total_size'] as int? ?? 0,
    );
  }

  @override
  Future<void> upsertCacheFile(CacheFileMetadata metadata) async {
    final db = await _appDatabase.database;
    await db.insert(
      'cache_files',
      metadata.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
}

class CacheFileMetadata {
  const CacheFileMetadata({
    required this.fileId,
    required this.localPath,
    required this.cachedAt,
    required this.fileSize,
  });

  final String fileId;
  final String localPath;
  final DateTime cachedAt;
  final int fileSize;

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'file_id': fileId,
      'local_path': localPath,
      'cached_at': cachedAt.toIso8601String(),
      'file_size': fileSize,
    };
  }

  static CacheFileMetadata fromMap(Map<String, Object?> map) {
    return CacheFileMetadata(
      fileId: map['file_id'] as String,
      localPath: map['local_path'] as String,
      cachedAt: DateTime.parse(map['cached_at'] as String),
      fileSize: map['file_size'] as int,
    );
  }
}

class CacheSummary {
  const CacheSummary({required this.fileCount, required this.totalSizeBytes});

  final int fileCount;
  final int totalSizeBytes;
}

class CacheSyncStatus {
  const CacheSyncStatus({
    this.status = CacheSyncPhase.idle,
    this.totalFiles = 0,
    this.syncedFiles = 0,
    this.errorMessage,
  });

  final CacheSyncPhase status;
  final int totalFiles;
  final int syncedFiles;
  final String? errorMessage;
}

enum CacheSyncPhase { idle, syncing, complete, error }
