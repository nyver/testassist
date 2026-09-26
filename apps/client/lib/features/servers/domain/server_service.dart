import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/providers.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/network/pinned_dio.dart';
import '../../../core/security/certificate_probe.dart';
import '../data/dio_server_info_api.dart';
import 'server_info_api.dart';
import 'server_record.dart';

/// Builds the server-info client for a connection. Tests replace it with a
/// fake so no network is needed.
typedef ServerInfoApiFactory = ServerInfoApi Function(ApiConnection connection);

final serverInfoApiFactoryProvider = Provider<ServerInfoApiFactory>(
  (ref) =>
      (connection) => DioServerInfoApi(connection),
);

final serverServiceProvider = Provider<ServerService>(ServerService.new);

/// How server setup ended.
sealed class SetupOutcome {
  const SetupOutcome();
}

final class SetupSuccess extends SetupOutcome {
  const SetupSuccess();
}

/// The user declined to trust the certificate. Nothing was saved and no token
/// was sent.
final class SetupCancelled extends SetupOutcome {
  const SetupCancelled();
}

final class SetupError extends SetupOutcome {
  const SetupError(this.failure);

  final AppFailure failure;
}

/// Why a URL was rejected.
enum ServerUrlProblem { invalid, notHttps }

/// Validates the server address typed by the user. Only `https` is accepted.
/// Returns the parsed address or the reason it was rejected.
({Uri? url, ServerUrlProblem? problem}) parseServerUrl(String input) {
  final text = input.trim();
  final uri = Uri.tryParse(text);
  if (uri == null || !uri.hasScheme || text.isEmpty) {
    return (url: null, problem: ServerUrlProblem.invalid);
  }
  if (uri.scheme.toLowerCase() != 'https') {
    return (url: null, problem: ServerUrlProblem.notHttps);
  }
  if (uri.host.isEmpty || uri.hasQuery || uri.hasFragment) {
    return (url: null, problem: ServerUrlProblem.invalid);
  }
  final path = uri.path.endsWith('/')
      ? uri.path.substring(0, uri.path.length - 1)
      : uri.path;
  return (url: uri.replace(path: path), problem: null);
}

/// Shows the fingerprint to the user and returns whether they chose "Trust".
typedef ConfirmTrust = Future<bool> Function(String fingerprint);

/// Server setup, trust handling and maintenance of the configured server.
class ServerService {
  ServerService(this._ref);

  final Ref _ref;

  /// Connects to a new server. The certificate is probed first, without any
  /// HTTP request. A publicly trusted certificate proceeds directly; otherwise
  /// [confirmTrust] must return true before the fingerprint is stored and the
  /// token is sent.
  Future<SetupOutcome> connect({
    required Uri baseUrl,
    required String name,
    required String token,
    required ConfirmTrust confirmTrust,
  }) async {
    String? pin;
    try {
      final probe = await _ref.read(certificateProbeProvider).probe(baseUrl);
      if (probe is ProbeUntrusted) {
        if (!await confirmTrust(probe.fingerprint)) {
          return const SetupCancelled();
        }
        pin = probe.fingerprint;
      }

      final info = await _fetchInfo(baseUrl, pin: pin, token: token);
      final record = await _ref
          .read(serverRepositoryProvider)
          .add(
            serverId: info.serverId,
            name: name.trim().isEmpty ? info.name : name.trim(),
            baseUrl: baseUrl,
          );
      final secrets = _ref.read(serverSecretsProvider);
      try {
        await secrets.writeToken(record.id, token);
        if (pin != null) await secrets.writeFingerprint(record.id, pin);
      } on Object {
        // Do not leave a half-configured server behind.
        await secrets.deleteAll(record.id);
        await _ref.read(serverRepositoryProvider).remove(record.id);
        rethrow;
      }
      await _ref.read(serverSessionProvider.notifier).reload();
      return const SetupSuccess();
    } on AppFailure catch (failure) {
      return SetupError(failure);
    } on Object catch (e) {
      return SetupError(UnexpectedFailure(e.runtimeType.toString()));
    }
  }

  /// Calls server info and compares the returned `serverId` with the stored
  /// one. Throws [ServerMismatchFailure] when a different server answered.
  Future<ServerInfo> verifyIdentity() async {
    final session = _ref.read(serverSessionProvider).value;
    final api = _ref.read(serverInfoApiProvider);
    if (session == null || api == null) {
      throw const UnexpectedFailure('no server configured');
    }
    final info = await api.fetch();
    if (info.serverId != session.record.serverId) {
      throw const ServerMismatchFailure();
    }
    await _ref.read(serverRepositoryProvider).touch(session.record.id);
    return info;
  }

  Future<void> rename(String name) async {
    final record = _requireRecord();
    await _ref.read(serverRepositoryProvider).rename(record.id, name.trim());
    await _ref.read(serverSessionProvider.notifier).reload();
  }

  /// Verifies [newToken] against the server and stores it only on success.
  /// Returns the failure, or null when the token was replaced.
  Future<AppFailure?> replaceToken(String newToken) async {
    final session = _ref.read(serverSessionProvider).value;
    if (session == null) return const UnexpectedFailure('no server configured');
    try {
      final info = await _fetchInfo(
        session.record.baseUrl,
        pin: session.pinnedFingerprint,
        token: newToken,
      );
      if (info.serverId != session.record.serverId) {
        return const ServerMismatchFailure();
      }
      await _ref
          .read(serverSecretsProvider)
          .writeToken(session.record.id, newToken);
      await _ref.read(serverSessionProvider.notifier).reload();
      return null;
    } on AppFailure catch (failure) {
      return failure;
    } on Object catch (e) {
      // For example a secure-storage error: report it, keep the old token.
      return UnexpectedFailure(e.runtimeType.toString());
    }
  }

  /// Deletes the stored fingerprint and runs trust on first use again: the
  /// certificate is probed and, if it is not publicly trusted, [confirmTrust]
  /// decides whether the new fingerprint is stored.
  Future<SetupOutcome> resetTrust(ConfirmTrust confirmTrust) async {
    final record = _requireRecord();
    final secrets = _ref.read(serverSecretsProvider);
    try {
      await secrets.deleteFingerprint(record.id);
      await _ref.read(serverSessionProvider.notifier).reload();

      final probe = await _ref
          .read(certificateProbeProvider)
          .probe(record.baseUrl);
      if (probe is ProbeUntrusted) {
        if (!await confirmTrust(probe.fingerprint)) {
          return const SetupCancelled();
        }
        await secrets.writeFingerprint(record.id, probe.fingerprint);
        await _ref.read(serverSessionProvider.notifier).reload();
      }

      try {
        await verifyIdentity();
      } on ServerMismatchFailure {
        // A different server holds this certificate: do not keep trusting it.
        await secrets.deleteFingerprint(record.id);
        await _ref.read(serverSessionProvider.notifier).reload();
        rethrow;
      }
      return const SetupSuccess();
    } on AppFailure catch (failure) {
      return SetupError(failure);
    } on Object catch (e) {
      return SetupError(UnexpectedFailure(e.runtimeType.toString()));
    }
  }

  /// Removes the server, its token and its pinned fingerprint. History stays.
  Future<void> remove() async {
    final record = _requireRecord();
    await _ref.read(serverSecretsProvider).deleteAll(record.id);
    await _ref.read(serverRepositoryProvider).remove(record.id);
    await _ref.read(serverSessionProvider.notifier).reload();
  }

  ServerRecord _requireRecord() {
    final record = _ref.read(serverSessionProvider).value?.record;
    if (record == null) throw StateError('no server configured');
    return record;
  }

  Future<ServerInfo> _fetchInfo(
    Uri baseUrl, {
    required String? pin,
    required String token,
  }) async {
    final connection = _ref.read(apiConnectionFactoryProvider)(
      baseUrl: baseUrl,
      pinnedFingerprint: pin,
      token: token,
    );
    try {
      return await _ref.read(serverInfoApiFactoryProvider)(connection).fetch();
    } finally {
      connection.close();
    }
  }
}

/// Verifies that the server at the configured address is the one that was set
/// up. Throws [ServerMismatchFailure] or another [AppFailure].
final serverIdentityVerifierProvider = Provider<Future<void> Function()>((ref) {
  final service = ref.watch(serverServiceProvider);
  return () async {
    await service.verifyIdentity();
  };
});
