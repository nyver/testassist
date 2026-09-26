import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../features/history/data/drift_history_repository.dart';
import '../../features/history/domain/history_entry.dart';
import '../../features/history/domain/history_service.dart';
import '../../features/questions/data/dio_questions_api.dart';
import '../../features/questions/data/drift_draft_repository.dart';
import '../../features/questions/domain/draft_repository.dart';
import '../../features/questions/domain/questions_api.dart';
import '../../features/servers/data/dio_server_info_api.dart';
import '../../features/servers/data/drift_server_repository.dart';
import '../../features/servers/domain/server_info_api.dart';
import '../../features/servers/domain/server_record.dart';
import '../../features/servers/domain/server_session.dart';
import '../../features/settings/data/settings_repository.dart';
import '../database/app_database.dart';
import '../network/pinned_dio.dart';
import '../security/certificate_probe.dart';
import '../security/secret_storage.dart';
import '../storage/image_store.dart';

// ---- Values that main() creates before the first frame -------------------

/// Overridden in `main` with the opened database.
final appDatabaseProvider = Provider<AppDatabase>(
  (ref) => throw UnimplementedError('appDatabaseProvider is not overridden'),
);

/// Overridden in `main`.
final sharedPreferencesProvider = Provider<SharedPreferences>(
  (ref) =>
      throw UnimplementedError('sharedPreferencesProvider is not overridden'),
);

/// Overridden in `main` with the app-private storage root.
final storageRootProvider = Provider<Directory>(
  (ref) => throw UnimplementedError('storageRootProvider is not overridden'),
);

// ---- Infrastructure ------------------------------------------------------

final imageStoreProvider = Provider<ImageStore>(
  (ref) => ImageStore(ref.watch(storageRootProvider)),
);

final secretStorageProvider = Provider<SecretStorage>(
  (ref) => KeystoreSecretStorage(),
);

final serverSecretsProvider = Provider<ServerSecretsRepository>(
  (ref) => ServerSecretsRepository(ref.watch(secretStorageProvider)),
);

final certificateProbeProvider = Provider<CertificateProbe>(
  (ref) => SocketCertificateProbe(),
);

/// Builds the HTTP client for a server. Tests replace it to inject trust
/// anchors.
typedef ApiConnectionFactory = ApiConnection Function({
  required Uri baseUrl,
  String? pinnedFingerprint,
  String? token,
});

final apiConnectionFactoryProvider = Provider<ApiConnectionFactory>(
  (ref) =>
      ({required baseUrl, pinnedFingerprint, token}) => createApiConnection(
        baseUrl: baseUrl,
        pinnedFingerprint: pinnedFingerprint,
        token: token,
      ),
);

// ---- Repositories --------------------------------------------------------

final serverRepositoryProvider = Provider<ServerRepository>(
  (ref) => DriftServerRepository(ref.watch(appDatabaseProvider)),
);

final historyRepositoryProvider = Provider<HistoryRepository>(
  (ref) => DriftHistoryRepository(ref.watch(appDatabaseProvider)),
);

final draftRepositoryProvider = Provider<DraftRepository>(
  (ref) => DriftDraftRepository(ref.watch(appDatabaseProvider)),
);

final historyServiceProvider = Provider<HistoryService>(
  (ref) => HistoryService(
    ref.watch(historyRepositoryProvider),
    ref.watch(imageStoreProvider),
  ),
);

final settingsRepositoryProvider = Provider<SettingsRepository>(
  (ref) => SettingsRepository(ref.watch(sharedPreferencesProvider)),
);

// ---- The configured server -----------------------------------------------

/// The configured server with its secrets, or null before setup. Invalidate it
/// after any change to the server, its token or its pin.
final serverSessionProvider =
    AsyncNotifierProvider<ServerSessionNotifier, ServerSession?>(
      ServerSessionNotifier.new,
    );

class ServerSessionNotifier extends AsyncNotifier<ServerSession?> {
  @override
  Future<ServerSession?> build() async {
    final record = await ref.watch(serverRepositoryProvider).current();
    if (record == null) return null;
    final secrets = ref.watch(serverSecretsProvider);
    return ServerSession(
      record: record,
      token: await secrets.readToken(record.id),
      pinnedFingerprint: await secrets.readFingerprint(record.id),
    );
  }

  /// Reloads the session and waits for it, so callers can rely on the result.
  Future<void> reload() async {
    ref.invalidateSelf();
    await future;
  }
}

/// The HTTP client of the configured server. It is rebuilt (and the old one
/// closed) whenever the session changes, so connections that were opened under
/// an old trust state are never reused.
final apiConnectionProvider = Provider<ApiConnection?>((ref) {
  final session = ref.watch(serverSessionProvider).value;
  if (session == null) return null;
  final connection = ref.watch(apiConnectionFactoryProvider)(
    baseUrl: session.record.baseUrl,
    pinnedFingerprint: session.pinnedFingerprint,
    token: session.token,
  );
  ref.onDispose(connection.close);
  return connection;
});

final serverInfoApiProvider = Provider<ServerInfoApi?>((ref) {
  final connection = ref.watch(apiConnectionProvider);
  return connection == null ? null : DioServerInfoApi(connection);
});

final questionsApiProvider = Provider<QuestionsApi?>((ref) {
  final connection = ref.watch(apiConnectionProvider);
  return connection == null ? null : DioQuestionsApi(connection);
});

// ---- Capture and OCR -----------------------------------------------------

/// Overridden in `main` with the app's cache directory, for intermediate
/// images that never need to survive a restart.
final tempDirectoryProvider = Provider<Directory>(
  (ref) => throw UnimplementedError('tempDirectoryProvider is not overridden'),
);
