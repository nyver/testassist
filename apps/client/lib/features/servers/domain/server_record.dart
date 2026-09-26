import 'package:flutter/foundation.dart';

/// The configured server as stored locally. The token and pinned fingerprint
/// are deliberately not part of it: they live in secure storage.
@immutable
class ServerRecord {
  const ServerRecord({
    required this.id,
    required this.serverId,
    required this.name,
    required this.baseUrl,
    required this.createdAt,
    required this.lastUsedAt,
  });

  /// Local database id, also the key of the server's secrets.
  final int id;

  /// The server's own UUID.
  final String serverId;
  final String name;
  final Uri baseUrl;
  final DateTime createdAt;
  final DateTime lastUsedAt;
}

/// Storage of the configured server.
abstract interface class ServerRepository {
  /// The configured server, or null before setup.
  Future<ServerRecord?> current();

  Stream<ServerRecord?> watchCurrent();

  Future<ServerRecord> add({
    required String serverId,
    required String name,
    required Uri baseUrl,
  });

  Future<void> rename(int id, String name);

  Future<void> touch(int id);

  Future<void> remove(int id);
}
