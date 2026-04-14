import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

part 'database.g.dart';

class Vaults extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().withDefault(const Constant(''))();
  TextColumn get driveFolderId =>
      text().withDefault(const Constant('')).unique()();
  TextColumn get lastSyncedAt => text().nullable()();
}

class Notes extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get vaultId =>
      integer().withDefault(const Constant(0)).references(Vaults, #id)();
  TextColumn get title => text().withDefault(const Constant(''))();
  TextColumn get filePath => text().withDefault(const Constant(''))();
  TextColumn get driveFileId => text().withDefault(const Constant(''))();
  TextColumn get content => text().nullable()();
  TextColumn get cachedAt => text().nullable()();
  TextColumn get updatedAt => text().nullable()();

  @override
  List<Set<Column>> get uniqueKeys => [
    {vaultId, driveFileId},
  ];
}

class WikilinkIndex extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get sourceNoteId => integer()
      .withDefault(const Constant(0))
      .references(
        Notes,
        #id,
        onUpdate: KeyAction.cascade,
        onDelete: KeyAction.cascade,
      )();
  TextColumn get targetTitle => text().withDefault(const Constant(''))();
  IntColumn get targetNoteId => integer().nullable().references(
    Notes,
    #id,
    onUpdate: KeyAction.cascade,
    onDelete: KeyAction.setNull,
  )();
  TextColumn get alias => text().nullable()();
}

class AppSettings extends Table {
  TextColumn get key => text().withDefault(const Constant(''))();
  TextColumn get value => text().nullable()();

  @override
  Set<Column> get primaryKey => {key};
}

class CacheFiles extends Table {
  TextColumn get fileId => text().withDefault(const Constant(''))();
  TextColumn get localPath => text().withDefault(const Constant(''))();
  TextColumn get cachedAt => text().withDefault(const Constant(''))();
  IntColumn get fileSize => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {fileId};
}

@DriftDatabase(tables: [Vaults, Notes, WikilinkIndex, AppSettings, CacheFiles])
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor])
    : super(executor ?? _defaultExecutor());

  static QueryExecutor _defaultExecutor() {
    return driftDatabase(
      name: 'obsidrive.db',
      web: DriftWebOptions(
        sqlite3Wasm: Uri.parse('sqlite3.wasm'),
        driftWorker: Uri.parse('drift_worker.js'),
      ),
    );
  }

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (Migrator m) async {
      await m.createAll();
    },
    onUpgrade: (Migrator m, int from, int to) async {
      await m.createAll();
    },
  );
}
