import 'package:sqflite/sqflite.dart';

import '../../../core/database.dart';
import '../domain/vault_models.dart';

class VaultRepository {
  VaultRepository(this._appDatabase);

  static const _selectedVaultKey = 'selected_vault_id';

  final AppDatabase _appDatabase;

  Future<List<Vault>> listVaults() async {
    final db = await _appDatabase.database;
    final rows = await db.query('vaults', orderBy: 'name COLLATE NOCASE ASC');
    return rows.map(Vault.fromMap).toList();
  }

  Future<Vault?> getVault(int id) async {
    final db = await _appDatabase.database;
    final rows = await db.query(
      'vaults',
      where: 'id = ?',
      whereArgs: <Object?>[id],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }

    return Vault.fromMap(rows.single);
  }

  Future<Vault> upsertVault(Vault vault) async {
    final db = await _appDatabase.database;
    final map = vault.toMap()..remove('id');
    final existingId = vault.id;
    if (existingId != null) {
      await db.update(
        'vaults',
        map,
        where: 'id = ?',
        whereArgs: <Object?>[existingId],
      );
      return vault;
    }

    final id = await db.insert(
      'vaults',
      map,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    return vault.copyWith(id: id);
  }

  Future<void> deleteVault(int id) async {
    final db = await _appDatabase.database;
    await db.delete('vaults', where: 'id = ?', whereArgs: <Object?>[id]);
  }

  Future<List<Note>> listNotes(int vaultId) async {
    final db = await _appDatabase.database;
    final rows = await db.query(
      'notes',
      where: 'vault_id = ?',
      whereArgs: <Object?>[vaultId],
      orderBy: 'file_path COLLATE NOCASE ASC',
    );
    return rows.map(Note.fromMap).toList();
  }

  Future<Note?> getNote(int id) async {
    final db = await _appDatabase.database;
    final rows = await db.query(
      'notes',
      where: 'id = ?',
      whereArgs: <Object?>[id],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }

    return Note.fromMap(rows.single);
  }

  Future<Note> upsertNote(Note note) async {
    final db = await _appDatabase.database;
    final map = note.toMap()..remove('id');
    final existingId = note.id;
    if (existingId != null) {
      await db.update(
        'notes',
        map,
        where: 'id = ?',
        whereArgs: <Object?>[existingId],
      );
      return note;
    }

    final id = await db.insert(
      'notes',
      map,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    return note.copyWith(id: id);
  }

  Future<void> deleteNote(int id) async {
    final db = await _appDatabase.database;
    await db.delete('notes', where: 'id = ?', whereArgs: <Object?>[id]);
  }

  Future<void> bulkInsertNotes(int vaultId, List<Note> notes) async {
    final db = await _appDatabase.database;
    await db.transaction((txn) async {
      await txn.delete(
        'notes',
        where: 'vault_id = ?',
        whereArgs: <Object?>[vaultId],
      );
      final batch = txn.batch();
      for (final note in notes) {
        batch.insert(
          'notes',
          note.copyWith(vaultId: vaultId).toMap()..remove('id'),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      await batch.commit(noResult: true);
    });
  }

  Future<int?> getSelectedVaultId() async {
    final db = await _appDatabase.database;
    final rows = await db.query(
      'app_settings',
      columns: const <String>['value'],
      where: 'key = ?',
      whereArgs: const <Object?>[_selectedVaultKey],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }

    return int.tryParse(rows.single['value'] as String? ?? '');
  }

  Future<void> setSelectedVaultId(int vaultId) async {
    final db = await _appDatabase.database;
    await db.insert('app_settings', <String, Object?>{
      'key': _selectedVaultKey,
      'value': vaultId.toString(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<Vault?> getSelectedVault() async {
    final id = await getSelectedVaultId();
    if (id == null) {
      return null;
    }

    return getVault(id);
  }
}
