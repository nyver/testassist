import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../domain/server_record.dart';

class DriftServerRepository implements ServerRepository {
  DriftServerRepository(this._db, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final AppDatabase _db;
  final DateTime Function() _clock;

  SimpleSelectStatement<$ServersTable, Server> get _first =>
      _db.select(_db.servers)
        ..orderBy([(t) => OrderingTerm.asc(t.id)])
        ..limit(1);

  @override
  Future<ServerRecord?> current() async {
    final row = await _first.getSingleOrNull();
    return row == null ? null : _map(row);
  }

  @override
  Stream<ServerRecord?> watchCurrent() =>
      _first.watchSingleOrNull().map((row) => row == null ? null : _map(row));

  @override
  Future<ServerRecord> add({
    required String serverId,
    required String name,
    required Uri baseUrl,
  }) async {
    final now = _clock();
    final id = await _db
        .into(_db.servers)
        .insert(
          ServersCompanion.insert(
            serverId: serverId,
            name: name,
            baseUrl: baseUrl.toString(),
            createdAt: now,
            lastUsedAt: now,
          ),
        );
    final row = await (_db.select(
      _db.servers,
    )..where((t) => t.id.equals(id))).getSingle();
    return _map(row);
  }

  @override
  Future<void> rename(int id, String name) => (_db.update(
    _db.servers,
  )..where((t) => t.id.equals(id))).write(ServersCompanion(name: Value(name)));

  @override
  Future<void> touch(int id) =>
      (_db.update(_db.servers)..where((t) => t.id.equals(id))).write(
        ServersCompanion(lastUsedAt: Value(_clock())),
      );

  @override
  Future<void> remove(int id) =>
      (_db.delete(_db.servers)..where((t) => t.id.equals(id))).go();

  ServerRecord _map(Server row) => ServerRecord(
    id: row.id,
    serverId: row.serverId,
    name: row.name,
    baseUrl: Uri.parse(row.baseUrl),
    createdAt: row.createdAt,
    lastUsedAt: row.lastUsedAt,
  );
}
