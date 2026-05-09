import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:googleapis/drive/v3.dart' as drive;

import '../../cache/data/cache_service.dart';
import '../../vault/data/vault_repository.dart';
import '../../vault/domain/vault_models.dart';

abstract class DriveFileContentClient {
  Future<String> downloadMarkdown(String fileId);
  Future<void> uploadMarkdown(String fileId, String content);
  Future<void> renameFile(String fileId, String name);
}

class GoogleDriveFileContentClient implements DriveFileContentClient {
  GoogleDriveFileContentClient(this._api);

  final drive.DriveApi _api;

  @override
  Future<String> downloadMarkdown(String fileId) async {
    final response = await _api.files.get(
      fileId,
      downloadOptions: drive.DownloadOptions.fullMedia,
      supportsAllDrives: true,
    );
    final media = response as drive.Media;
    return utf8.decodeStream(media.stream);
  }

  @override
  Future<void> uploadMarkdown(String fileId, String content) async {
    final media = drive.Media(
      Stream.value(utf8.encode(content)),
      utf8.encode(content).length,
    );
    await _api.files.update(
      drive.File(),
      fileId,
      uploadMedia: media,
      supportsAllDrives: true,
    );
  }

  @override
  Future<void> renameFile(String fileId, String name) async {
    await _api.files.update(
      drive.File(name: name),
      fileId,
      supportsAllDrives: true,
    );
  }
}

abstract class NoteContentStore {
  Future<Note?> getNote(int id);

  Future<Note> upsertNote(Note note);

  Future<List<Note>> listNotes(int vaultId);
}

class VaultNoteContentStore implements NoteContentStore {
  VaultNoteContentStore(this._repository);

  final VaultRepository _repository;

  @override
  Future<Note?> getNote(int id) {
    return _repository.getNote(id);
  }

  @override
  Future<List<Note>> listNotes(int vaultId) {
    return _repository.listNotes(vaultId);
  }

  @override
  Future<Note> upsertNote(Note note) {
    return _repository.upsertNote(note);
  }
}

class NoteContentRepository {
  NoteContentRepository({
    required NoteContentStore store,
    required DriveFileContentClient driveClient,
    CacheService? cacheService,
    bool Function()? isOnline,
    DateTime Function()? now,
    this.staleAfter = const Duration(minutes: 15),
  }) : _store = store,
       _driveClient = driveClient,
       _cacheService = cacheService,
       _isOnline = isOnline ?? (() => true),
       _now = now ?? DateTime.now;

  final NoteContentStore _store;
  final DriveFileContentClient _driveClient;
  final CacheService? _cacheService;
  final bool Function() _isOnline;
  final DateTime Function() _now;
  final Duration staleAfter;

  Future<String> getContent(Note note) async {
    final cached = await _latestNote(note);
    if (!_isOnline()) {
      final offlineContent = await _cacheService?.getCachedNote(cached);
      if (offlineContent != null) {
        return offlineContent;
      }

      final dbContent = cached.content;
      if (dbContent != null) {
        return dbContent;
      }

      throw const OfflineNoteUnavailableException();
    }

    if (cached.content != null) {
      return cached.content!;
    }

    final content = await _driveClient.downloadMarkdown(cached.driveFileId);
    await _store.upsertNote(
      cached.copyWith(
        content: Value(content),
        cachedAt: Value(_now().toIso8601String()),
      ),
    );
    return content;
  }

  Future<String?> revalidateIfNeeded(Note note) async {
    final cached = await _latestNote(note);
    if (!_isOnline() || _hasFreshCache(cached) || cached.content == null) {
      return null;
    }

    final content = await _driveClient.downloadMarkdown(cached.driveFileId);
    await _store.upsertNote(
      cached.copyWith(
        content: Value(content),
        cachedAt: Value(_now().toIso8601String()),
      ),
    );
    return content;
  }

  Future<void> forceRefresh(Note note) async {
    if (!_isOnline()) {
      throw const OfflineNoteUnavailableException();
    }

    final cached = await _latestNote(note);
    final content = await _driveClient.downloadMarkdown(cached.driveFileId);
    await _store.upsertNote(
      cached.copyWith(
        content: Value(content),
        cachedAt: Value(_now().toIso8601String()),
      ),
    );
  }

  Future<void> saveContent(Note note, String content) async {
    await _driveClient.uploadMarkdown(note.driveFileId, content);
    await _store.upsertNote(
      note.copyWith(
        content: Value(content),
        cachedAt: Value(_now().toIso8601String()),
      ),
    );
  }

  Future<Note> renameNote(Note note, String newTitle) async {
    final trimmedTitle = newTitle.trim();
    if (trimmedTitle.isEmpty) {
      throw ArgumentError('파일 이름을 입력해 주세요.');
    }

    final renamed = _renamedNote(note, trimmedTitle);
    await _driveClient.renameFile(note.driveFileId, _fileNameFromPath(renamed));
    return _store.upsertNote(renamed);
  }

  Future<Note?> resolveNote(int vaultId, String target) async {
    final notes = await _store.listNotes(vaultId);
    final normalizedTarget = _normalizedTarget(target);

    for (final note in notes) {
      if (_normalizePath(note.filePath) == normalizedTarget) {
        return note;
      }
    }

    final normalizedTitle = _normalizeTitle(target);
    for (final note in notes) {
      if (_normalizeTitle(note.title) == normalizedTitle) {
        return note;
      }
    }

    return null;
  }

  Future<Note> _latestNote(Note note) async {
    return await _store.getNote(note.id) ?? note;
  }

  bool _hasFreshCache(Note note) {
    final content = note.content;
    final cachedAtStr = note.cachedAt;
    if (content == null || cachedAtStr == null) {
      return false;
    }

    final cachedAt = DateTime.tryParse(cachedAtStr);
    if (cachedAt == null) {
      return false;
    }

    final updatedAtStr = note.updatedAt;
    if (updatedAtStr != null) {
      final updatedAt = DateTime.tryParse(updatedAtStr);
      if (updatedAt != null && updatedAt.isAfter(cachedAt)) {
        return false;
      }
    }

    return _now().difference(cachedAt) <= staleAfter;
  }

  String _normalizedTarget(String target) {
    final normalized = _normalizePath(target);
    if (normalized.toLowerCase().endsWith('.md')) {
      return normalized;
    }

    return '$normalized.md';
  }

  String _normalizePath(String value) {
    return value.trim().replaceAll(RegExp(r'/+'), '/').toLowerCase();
  }

  String _normalizeTitle(String value) {
    final trimmed = value.trim();
    if (trimmed.toLowerCase().endsWith('.md')) {
      return trimmed.substring(0, trimmed.length - 3).toLowerCase();
    }

    final separator = trimmed.lastIndexOf('/');
    final title = separator == -1 ? trimmed : trimmed.substring(separator + 1);
    return title.toLowerCase();
  }

  Note _renamedNote(Note note, String newTitle) {
    final folderPrefix = _folderPrefix(note.filePath);
    final hasMarkdownExtension = note.filePath.toLowerCase().endsWith('.md');
    final title = hasMarkdownExtension
        ? _withoutMarkdownExtension(newTitle)
        : newTitle;
    final fileName = hasMarkdownExtension ? '$title.md' : title;

    return note.copyWith(title: title, filePath: '$folderPrefix$fileName');
  }

  String _folderPrefix(String filePath) {
    final separator = filePath.lastIndexOf('/');
    if (separator == -1) {
      return '';
    }

    return filePath.substring(0, separator + 1);
  }

  String _fileNameFromPath(Note note) {
    final separator = note.filePath.lastIndexOf('/');
    if (separator == -1) {
      return note.filePath;
    }

    return note.filePath.substring(separator + 1);
  }

  String _withoutMarkdownExtension(String value) {
    if (value.toLowerCase().endsWith('.md')) {
      return value.substring(0, value.length - 3);
    }

    return value;
  }
}

class OfflineNoteUnavailableException implements Exception {
  const OfflineNoteUnavailableException();

  @override
  String toString() {
    return '오프라인 — 싱크 후 사용 가능';
  }
}
