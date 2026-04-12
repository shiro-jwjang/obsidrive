import 'dart:convert';

import 'package:googleapis/drive/v3.dart' as drive;

import '../../cache/data/cache_service.dart';
import '../../vault/data/vault_repository.dart';
import '../../vault/domain/vault_models.dart';

abstract class DriveFileContentClient {
  Future<String> downloadMarkdown(String fileId);
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

      throw const OfflineNoteUnavailableException();
    }

    if (_hasFreshCache(cached)) {
      return cached.content!;
    }

    final content = await _driveClient.downloadMarkdown(cached.driveFileId);
    await _store.upsertNote(
      cached.copyWith(content: content, cachedAt: _now()),
    );
    return content;
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
    final id = note.id;
    if (id == null) {
      return note;
    }

    return await _store.getNote(id) ?? note;
  }

  bool _hasFreshCache(Note note) {
    final content = note.content;
    final cachedAt = note.cachedAt;
    if (content == null || cachedAt == null) {
      return false;
    }

    final updatedAt = note.updatedAt;
    if (updatedAt != null && updatedAt.isAfter(cachedAt)) {
      return false;
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
}

class OfflineNoteUnavailableException implements Exception {
  const OfflineNoteUnavailableException();

  @override
  String toString() {
    return '오프라인 — 싱크 후 사용 가능';
  }
}
