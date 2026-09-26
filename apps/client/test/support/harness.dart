import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:test_assistant/app/app.dart';
import 'package:test_assistant/core/di/providers.dart';
import 'package:test_assistant/core/security/certificate_probe.dart';
import 'package:test_assistant/core/storage/image_store.dart';
import 'package:test_assistant/features/servers/domain/server_info_api.dart';
import 'package:test_assistant/features/servers/domain/server_service.dart';
import 'package:test_assistant/l10n/generated/app_localizations.dart';

import 'fakes.dart';

/// Everything a test needs to run screens and controllers without I/O.
class Harness {
  Harness._({
    required this.tmp,
    required this.prefs,
    required this.secrets,
    required this.servers,
    required this.history,
    required this.drafts,
    required this.probe,
    required this.infoApi,
    required this.questionsApi,
  }) : images = ImageStore(tmp);

  final Directory tmp;
  final SharedPreferences prefs;
  final InMemorySecretStorage secrets;
  final InMemoryServerRepository servers;
  final InMemoryHistoryRepository history;
  final InMemoryDraftRepository drafts;
  final FakeCertificateProbe probe;
  final FakeServerInfoApi infoApi;
  final FakeQuestionsApi questionsApi;
  final ImageStore images;

  static const serverId = '019d2f6e-8a3c-7c1e-9b41-5d2a6f0e1c77';

  static Future<Harness> create({
    Map<String, Object> preferences = const {},
    Directory? tmp,
  }) async {
    SharedPreferences.setMockInitialValues(preferences);
    return Harness._(
      tmp: tmp ?? Directory.systemTemp.createTempSync('harness_'),
      prefs: await SharedPreferences.getInstance(),
      secrets: InMemorySecretStorage(),
      servers: InMemoryServerRepository(),
      history: InMemoryHistoryRepository(),
      drafts: InMemoryDraftRepository(),
      probe: FakeCertificateProbe(const ProbeTrusted()),
      infoApi: FakeServerInfoApi(
        info: const ServerInfo(
          serverId: serverId,
          name: 'Home',
          version: '0.1.0',
        ),
      ),
      questionsApi: FakeQuestionsApi(),
    );
  }

  /// Providers wired to the fakes. [withServer] presets the questions API and
  /// the identity check, as after a successful setup.
  List<Override> overrides({
    bool withServer = true,
    Future<void> Function()? verifier,
  }) => [
    sharedPreferencesProvider.overrideWithValue(prefs),
    storageRootProvider.overrideWithValue(tmp),
    tempDirectoryProvider.overrideWithValue(tmp),
    secretStorageProvider.overrideWithValue(secrets),
    serverRepositoryProvider.overrideWithValue(servers),
    historyRepositoryProvider.overrideWithValue(history),
    draftRepositoryProvider.overrideWithValue(drafts),
    certificateProbeProvider.overrideWithValue(probe),
    serverInfoApiFactoryProvider.overrideWithValue((_) => infoApi),
    serverInfoApiProvider.overrideWithValue(infoApi),
    if (withServer) questionsApiProvider.overrideWithValue(questionsApi),
    if (withServer || verifier != null)
      serverIdentityVerifierProvider.overrideWithValue(verifier ?? () async {}),
  ];

  /// Stores a configured server, with its token and optional pin.
  Future<void> seedServer({String? pin, String token = 'token-1'}) async {
    final record = await servers.add(
      serverId: serverId,
      name: 'Home',
      baseUrl: Uri.parse('https://192.168.1.10:8443'),
    );
    await secrets.write('v1/server/${record.id}/token', token);
    if (pin != null) {
      await secrets.write('v1/server/${record.id}/fingerprint', pin);
    }
  }

  Future<void> dispose() async {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  }
}

/// Wraps [child] in the localized MaterialApp the screens need.
Widget localized(
  Widget child, {
  Locale locale = const Locale('en'),
  List<Override> overrides = const [],
}) {
  return ProviderScope(
    retry: (count, error) => null,
    overrides: overrides,
    child: MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: child,
    ),
  );
}

/// Runs the whole app with the fakes of [h] on a phone-sized surface and waits
/// for the first route. [extra] overrides come after the harness ones.
Future<void> pumpApp(
  WidgetTester tester,
  Harness h, {
  List<Override> extra = const [],
  bool withServer = true,
  bool settle = true,
}) async {
  tester.view.physicalSize = const Size(900, 2000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      retry: (count, error) => null,
      overrides: [
        ...h.overrides(withServer: withServer),
        ...extra,
      ],
      child: const TestAssistantApp(),
    ),
  );
  if (settle) await tester.pumpAndSettle();
}
