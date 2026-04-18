import 'package:drift/drift.dart' show Value;

import '../../../core/database.dart' show Vault, Note;
export '../../../core/database.dart' show Vault, Note;

class DriveFolder {
  const DriveFolder({required this.id, required this.name, this.parentId});

  final String id;
  final String name;
  final String? parentId;

  @override
  bool operator ==(Object other) {
    return other is DriveFolder && other.id == id && other.name == name;
  }

  @override
  int get hashCode => Object.hash(id, name);
}

/// Extension helpers on drift-generated [Vault].
extension VaultX on Vault {
  DateTime? get lastSyncedAtDateTime =>
      lastSyncedAt == null ? null : DateTime.tryParse(lastSyncedAt!);

  Vault copyWithDateTime({DateTime? lastSyncedAt}) {
    return copyWith(
      lastSyncedAt: lastSyncedAt == null
          ? const Value.absent()
          : Value(lastSyncedAt.toIso8601String()),
    );
  }
}

/// Extension helpers on drift-generated [Note].
extension NoteX on Note {
  DateTime? get cachedAtDateTime =>
      cachedAt == null ? null : DateTime.tryParse(cachedAt!);

  DateTime? get updatedAtDateTime =>
      updatedAt == null ? null : DateTime.tryParse(updatedAt!);

  Note copyWithDateTime({DateTime? cachedAt, DateTime? updatedAt}) {
    return copyWith(
      cachedAt: cachedAt == null
          ? const Value.absent()
          : Value(cachedAt.toIso8601String()),
      updatedAt: updatedAt == null
          ? const Value.absent()
          : Value(updatedAt.toIso8601String()),
    );
  }
}

/// Phase of the vault scan process.
enum ScanPhase {
  /// Loading folder tree and top-level .md files quickly.
  quickSync,

  /// Full recursive scan for wikilink indexing.
  fullScan,
}

class ScanProgress {
  const ScanProgress({
    this.status = ScanStatus.idle,
    this.phase = ScanPhase.quickSync,
    this.totalFiles = 0,
    this.syncedFiles = 0,
    this.lastError,
    this.currentFolder,
  });

  final ScanStatus status;
  final ScanPhase phase;
  final int totalFiles;
  final int syncedFiles;
  final String? lastError;
  final String? currentFolder;

  ScanProgress copyWith({
    ScanStatus? status,
    ScanPhase? phase,
    int? totalFiles,
    int? syncedFiles,
    String? lastError,
    String? currentFolder,
    bool clearError = false,
  }) {
    return ScanProgress(
      status: status ?? this.status,
      phase: phase ?? this.phase,
      totalFiles: totalFiles ?? this.totalFiles,
      syncedFiles: syncedFiles ?? this.syncedFiles,
      lastError: clearError ? null : lastError ?? this.lastError,
      currentFolder: currentFolder ?? this.currentFolder,
    );
  }
}

enum ScanStatus { idle, syncing, complete, error }

/// Represents a folder node in the lazy-loaded tree.
class FolderNode {
  const FolderNode({
    required this.id,
    required this.name,
    required this.driveFolderId,
    this.children = const [],
    this.noteCount,
  });

  final int id;
  final String name;
  final String driveFolderId;

  /// Child folder nodes.
  final List<FolderNode> children;

  /// Number of .md notes in this folder (null if not yet loaded).
  final int? noteCount;

  FolderNode copyWith({List<FolderNode>? children, int? noteCount}) {
    return FolderNode(
      id: id,
      name: name,
      driveFolderId: driveFolderId,
      children: children ?? this.children,
      noteCount: noteCount ?? this.noteCount,
    );
  }
}
