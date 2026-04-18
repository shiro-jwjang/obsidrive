import 'dart:convert';

import '../../../core/storage.dart';
import '../../vault/domain/vault_models.dart';

class CacheService {
  CacheService({
    required CacheMetadataStore store,
    required CacheDriveClient driveClient,
    FileStorage? fileStorage,
    DateTime Function()? now,
  }) : _store = store,
       _driveClient = driveClient,
       _fileStorage = fileStorage,
       _now = now ?? DateTime.now;

  final CacheMetadataStore _store;
  final CacheDriveClient _driveClient;
  final FileStorage? _fileStorage;
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

    final storage = _fileStorage;
    if (storage == null) {
      return null;
    }

    final exists = await storage.exists(metadata.localPath);
    if (!exists) {
      return null;
    }

    return storage.readString(metadata.localPath);
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
    final storage = _fileStorage;
    if (storage == null) return;

    final content = await _driveClient.downloadMarkdown(note.driveFileId);
    final directory = await storage.getCacheDirectory();
    final filePath = '$directory/${_cacheFileName(note)}';
    await storage.writeString(filePath, content);
    final fileSize = await storage.length(filePath);
    await _store.upsertCacheFile(
      CacheFileMetadata(
        fileId: note.driveFileId,
        localPath: filePath,
        cachedAt: _now(),
        fileSize: fileSize,
      ),
    );
  }

  bool _isDriveVersionNewer(Note note, CacheFileMetadata metadata) {
    final updatedAtStr = note.updatedAt;
    if (updatedAtStr == null) {
      return false;
    }
    final updatedAt = DateTime.tryParse(updatedAtStr);
    if (updatedAt == null) {
      return false;
    }
    return updatedAt.isAfter(metadata.cachedAt);
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

// ignore: one_member_abstracts
abstract class CacheDriveClient {
  Future<String> downloadMarkdown(String fileId);
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

  // ignore: prefer_constructors_over_static_methods
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
