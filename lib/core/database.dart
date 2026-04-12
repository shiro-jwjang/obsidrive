import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

class AppDatabase {
  AppDatabase({Database? database}) : _database = database;

  static const databaseName = 'obsidrive.db';
  static const databaseVersion = 1;

  Database? _database;

  Future<Database> get database async {
    final existing = _database;
    if (existing != null) {
      return existing;
    }

    final directory = await getApplicationDocumentsDirectory();
    final path = '${directory.path}/$databaseName';
    final opened = await openDatabase(
      path,
      version: databaseVersion,
      onCreate: (db, version) => _ensureSchema(db),
      onOpen: _ensureSchema,
    );
    _database = opened;
    return opened;
  }

  static Future<void> _ensureSchema(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS vaults (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        drive_folder_id TEXT NOT NULL UNIQUE,
        last_synced_at TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS notes (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        vault_id INTEGER NOT NULL,
        title TEXT NOT NULL,
        file_path TEXT NOT NULL,
        drive_file_id TEXT NOT NULL,
        content TEXT,
        cached_at TEXT,
        updated_at TEXT,
        UNIQUE(vault_id, drive_file_id),
        FOREIGN KEY(vault_id) REFERENCES vaults(id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS wikilink_index (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        source_note_id INTEGER NOT NULL,
        target_title TEXT NOT NULL,
        target_note_id INTEGER,
        alias TEXT,
        FOREIGN KEY(source_note_id) REFERENCES notes(id) ON DELETE CASCADE,
        FOREIGN KEY(target_note_id) REFERENCES notes(id) ON DELETE SET NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS app_settings (
        key TEXT PRIMARY KEY,
        value TEXT
      )
    ''');

    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_notes_vault_path ON notes(vault_id, file_path)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_wikilink_source ON wikilink_index(source_note_id)',
    );
  }
}
