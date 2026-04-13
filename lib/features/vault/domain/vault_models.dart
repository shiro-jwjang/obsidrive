import 'package:drift/drift.dart' show Value;

import '../../../core/database.dart' show Vault, Note;
export '../../../core/database.dart' show Vault, Note;

class DriveFolder {
  const DriveFolder({required this.id, required this.name});

  final String id;
  final String name;

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

class ScanProgress {
  const ScanProgress({
    this.status = ScanStatus.idle,
    this.totalFiles = 0,
    this.syncedFiles = 0,
    this.lastError,
  });

  final ScanStatus status;
  final int totalFiles;
  final int syncedFiles;
  final String? lastError;

  ScanProgress copyWith({
    ScanStatus? status,
    int? totalFiles,
    int? syncedFiles,
    String? lastError,
    bool clearError = false,
  }) {
    return ScanProgress(
      status: status ?? this.status,
      totalFiles: totalFiles ?? this.totalFiles,
      syncedFiles: syncedFiles ?? this.syncedFiles,
      lastError: clearError ? null : lastError ?? this.lastError,
    );
  }
}

enum ScanStatus { idle, syncing, complete, error }
