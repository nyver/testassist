import '../../../core/errors/app_failure.dart';
import '../../../core/network/pinned_dio.dart';
import '../domain/server_info_api.dart';

class DioServerInfoApi implements ServerInfoApi {
  DioServerInfoApi(this._connection);

  final ApiConnection _connection;

  @override
  Future<ServerInfo> fetch() => _connection.guard((dio) async {
    final response = await dio.get<Map<String, Object?>>('/api/v1/server/info');
    final body = response.data;
    final serverId = body?['serverId'];
    final name = body?['name'];
    final version = body?['version'];
    if (serverId is! String || name is! String || version is! String) {
      throw const UnexpectedFailure('server info has an unexpected shape');
    }
    return ServerInfo(serverId: serverId, name: name, version: version);
  });
}
