import 'package:drift/drift.dart';

part 'app_database.g.dart';

/// The single configured server (the table allows more for the roadmap's
/// multi-server support). Secrets never live here: the token and the pinned
/// fingerprint are in secure storage, keyed by [id].
class Servers extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// The server's own UUID, learned from `GET /api/v1/server/info`.
  TextColumn get serverId => text().unique()();
  TextColumn get name => text()();
  TextColumn get baseUrl => text()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get lastUsedAt => dateTime()();
}

/// One analyzed question. `options_json` and `answer_json` carry `"v": 1` so
/// their layout can evolve without a table migration.
@TableIndex(name: 'questions_created_at', columns: {#createdAt})
class Questions extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// Entries outlive the server record: removing the server keeps the history.
  IntColumn get serverRef => integer().nullable().references(
    Servers,
    #id,
    onDelete: KeyAction.setNull,
  )();

  /// Path relative to the app-private image directory, or null.
  TextColumn get imagePath => text().nullable()();
  TextColumn get ocrText => text()();
  TextColumn get questionText => text()();
  TextColumn get optionsJson => text()();
  TextColumn get answerJson => text()();
  TextColumn get provider => text()();
  TextColumn get model => text()();
  RealColumn get confidence => real()();
  TextColumn get confidenceLevel => text()();
  TextColumn get requestId => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
}

/// The question being edited. At most one row, so it survives process death.
class Drafts extends Table {
  // The CHECK refers to the column being defined, which is how drift expects
  // it; the recursion lint does not apply.
  // ignore: recursive_getters
  IntColumn get id => integer().check(id.equals(1))();
  TextColumn get imagePath => text().nullable()();
  TextColumn get ocrText => text()();
  TextColumn get questionText => text()();
  TextColumn get optionsJson => text()();
  BoolColumn get sendImage => boolean().withDefault(const Constant(false))();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DriftDatabase(tables: [Servers, Questions, Drafts])
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  /// Increase together with a new migration step and a new schema snapshot in
  /// `drift_schemas/` (`dart run drift_dev schema dump`).
  static const currentSchemaVersion = 1;

  @override
  int get schemaVersion => currentSchemaVersion;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => m.createAll(),
    onUpgrade: (m, from, to) async {
      // Version 1 is the first released schema, so there is nothing to upgrade
      // from yet. Every later version adds a step here plus a migration test.
      throw StateError('Unsupported schema upgrade from $from to $to');
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );
}
