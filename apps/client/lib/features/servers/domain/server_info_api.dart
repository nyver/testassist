import 'package:flutter/foundation.dart';

@immutable
class ServerInfo {
  const ServerInfo({
    required this.serverId,
    required this.name,
    required this.version,
  });

  final String serverId;
  final String name;
  final String version;
}

/// `GET /api/v1/server/info`.
abstract interface class ServerInfoApi {
  Future<ServerInfo> fetch();
}
