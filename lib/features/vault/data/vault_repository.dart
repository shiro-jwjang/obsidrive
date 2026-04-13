import 'package:drift/drift.dart';

import '../../../core/database.dart';

class VaultRepository {
  VaultRepository(this._db);

  static const _selectedVaultKey = 'selected_vault_id';

  final AppDatabase _db;

  Future<List<Vault>> listVaults() {
    return (_db.select(
      _db.vaults,
    )..orderBy([(t) => OrderingTerm.asc(t.name)])).get();
  }

  Future<Vault?> getVault(int id) {
    return (_db.select(
      _db.vaults,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
  }

  Future<Vault> upsertVault(Vault vault) async {
    // Try to find existing vault by driveFolderId
    final existing =
        await (_db.select(_db.vaults)
              ..where((t) => t.driveFolderId.equals(vault.driveFolderId)))
            .getSingleOrNull();

    if (existing != null) {
      await (_db.update(
        _db.vaults,
      )..where((t) => t.id.equals(existing.id))).write(
        VaultsCompanion(
          name: Value(vault.name),
          driveFolderId: Value(vault.driveFolderId),
          lastSyncedAt: Value(vault.lastSyncedAt),
        ),
      );
      return existing.copyWith(
        name: vault.name,
        lastSyncedAt: vault.lastSyncedAt == null
            ? const Value.absent()
            : Value(vault.lastSyncedAt),
      );
    }

    final id = await _db
        .into(_db.vaults)
        .insert(
          VaultsCompanion.insert(
            name: Value(vault.name),
            driveFolderId: Value(vault.driveFolderId),
            lastSyncedAt: Value(vault.lastSyncedAt),
          ),
          mode: InsertMode.insertOrReplace,
        );
    return vault.copyWith(id: id);
  }

  Future<void> deleteVault(int id) {
    return (_db.delete(_db.vaults)..where((t) => t.id.equals(id))).go();
  }

  Future<List<Note>> listNotes(int vaultId) {
    return (_db.select(_db.notes)
          ..where((t) => t.vaultId.equals(vaultId))
          ..orderBy([(t) => OrderingTerm.asc(t.filePath)]))
        .get();
  }

  Future<Note?> getNote(int id) {
    return (_db.select(
      _db.notes,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
  }

  Future<Note> upsertNote(Note note) async {
    final existing = await getNote(note.id);
    if (existing != null) {
      await (_db.update(_db.notes)..where((t) => t.id.equals(note.id))).write(
        NotesCompanion(
          vaultId: Value(note.vaultId),
          title: Value(note.title),
          filePath: Value(note.filePath),
          driveFileId: Value(note.driveFileId),
          content: Value(note.content),
          cachedAt: Value(note.cachedAt),
          updatedAt: Value(note.updatedAt),
        ),
      );
      return note;
    }

    await _db
        .into(_db.notes)
        .insert(
          NotesCompanion.insert(
            vaultId: Value(note.vaultId),
            title: Value(note.title),
            filePath: Value(note.filePath),
            driveFileId: Value(note.driveFileId),
            content: Value(note.content),
            cachedAt: Value(note.cachedAt),
            updatedAt: Value(note.updatedAt),
          ),
          mode: InsertMode.insertOrReplace,
        );
    final inserted = await (_db.select(
      _db.notes,
    )..where((t) => t.driveFileId.equals(note.driveFileId))).getSingleOrNull();
    return inserted ?? note;
  }

  Future<void> deleteNote(int id) {
    return (_db.delete(_db.notes)..where((t) => t.id.equals(id))).go();
  }

  Future<void> bulkInsertNotes(int vaultId, List<NotesCompanion> notes) async {
    await _db.transaction(() async {
      // Delete existing notes for this vault
      await (_db.delete(
        _db.notes,
      )..where((t) => t.vaultId.equals(vaultId))).go();
      // Batch insert new notes
      for (final note in notes) {
        await _db
            .into(_db.notes)
            .insert(
              NotesCompanion.insert(
                vaultId: Value(vaultId),
                title: note.title,
                filePath: note.filePath,
                driveFileId: note.driveFileId,
                content: note.content,
                cachedAt: note.cachedAt,
                updatedAt: note.updatedAt,
              ),
              mode: InsertMode.insertOrReplace,
            );
      }
    });
  }

  Future<int?> getSelectedVaultId() async {
    final row = await (_db.select(
      _db.appSettings,
    )..where((t) => t.key.equals(_selectedVaultKey))).getSingleOrNull();
    if (row == null) return null;
    return int.tryParse(row.value ?? '');
  }

  Future<void> setSelectedVaultId(int vaultId) async {
    await _db
        .into(_db.appSettings)
        .insert(
          AppSettingsCompanion(
            key: Value(_selectedVaultKey),
            value: Value(vaultId.toString()),
          ),
          mode: InsertMode.insertOrReplace,
        );
  }

  Future<Vault?> getSelectedVault() async {
    final id = await getSelectedVaultId();
    if (id == null) return null;
    return getVault(id);
  }
}
