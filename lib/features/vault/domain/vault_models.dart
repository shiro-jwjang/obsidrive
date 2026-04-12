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

class Vault {
  const Vault({
    this.id,
    required this.name,
    required this.driveFolderId,
    this.lastSyncedAt,
  });

  final int? id;
  final String name;
  final String driveFolderId;
  final DateTime? lastSyncedAt;

  Vault copyWith({
    int? id,
    String? name,
    String? driveFolderId,
    DateTime? lastSyncedAt,
  }) {
    return Vault(
      id: id ?? this.id,
      name: name ?? this.name,
      driveFolderId: driveFolderId ?? this.driveFolderId,
      lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
    );
  }

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'id': id,
      'name': name,
      'drive_folder_id': driveFolderId,
      'last_synced_at': lastSyncedAt?.toIso8601String(),
    };
  }

  static Vault fromMap(Map<String, Object?> map) {
    return Vault(
      id: map['id'] as int?,
      name: map['name'] as String,
      driveFolderId: map['drive_folder_id'] as String,
      lastSyncedAt: _dateTimeFromMap(map['last_synced_at']),
    );
  }
}

class Note {
  const Note({
    this.id,
    required this.vaultId,
    required this.title,
    required this.filePath,
    required this.driveFileId,
    this.content,
    this.cachedAt,
    this.updatedAt,
  });

  final int? id;
  final int vaultId;
  final String title;
  final String filePath;
  final String driveFileId;
  final String? content;
  final DateTime? cachedAt;
  final DateTime? updatedAt;

  Note copyWith({
    int? id,
    int? vaultId,
    String? title,
    String? filePath,
    String? driveFileId,
    String? content,
    DateTime? cachedAt,
    DateTime? updatedAt,
  }) {
    return Note(
      id: id ?? this.id,
      vaultId: vaultId ?? this.vaultId,
      title: title ?? this.title,
      filePath: filePath ?? this.filePath,
      driveFileId: driveFileId ?? this.driveFileId,
      content: content ?? this.content,
      cachedAt: cachedAt ?? this.cachedAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'id': id,
      'vault_id': vaultId,
      'title': title,
      'file_path': filePath,
      'drive_file_id': driveFileId,
      'content': content,
      'cached_at': cachedAt?.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
    };
  }

  static Note fromMap(Map<String, Object?> map) {
    return Note(
      id: map['id'] as int?,
      vaultId: map['vault_id'] as int,
      title: map['title'] as String,
      filePath: map['file_path'] as String,
      driveFileId: map['drive_file_id'] as String,
      content: map['content'] as String?,
      cachedAt: _dateTimeFromMap(map['cached_at']),
      updatedAt: _dateTimeFromMap(map['updated_at']),
    );
  }
}

class WikilinkIndex {
  const WikilinkIndex({
    this.id,
    required this.sourceNoteId,
    required this.targetTitle,
    this.targetNoteId,
    this.alias,
  });

  final int? id;
  final int sourceNoteId;
  final String targetTitle;
  final int? targetNoteId;
  final String? alias;
}

class AppSettings {
  const AppSettings({
    this.selectedVaultId,
    this.themeMode = 'system',
    this.cacheSizeMB = 0,
  });

  final int? selectedVaultId;
  final String themeMode;
  final int cacheSizeMB;
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

DateTime? _dateTimeFromMap(Object? value) {
  if (value == null) {
    return null;
  }

  return DateTime.tryParse(value as String);
}
