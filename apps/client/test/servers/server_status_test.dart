import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:test_assistant/core/errors/app_failure.dart';
import 'package:test_assistant/features/servers/domain/server_info_api.dart';
import 'package:test_assistant/features/servers/domain/server_status.dart';

import '../support/harness.dart';

void main() {
  late Harness h;
  setUp(() async => h = await Harness.create());
  tearDown(() => h.dispose());

  ProviderContainer container() {
    final c = ProviderContainer(
      retry: (count, error) => null,
      // The real identity check: it reads the stored server when it runs.
      overrides: h.overrides(withServer: false),
    );
    addTearDown(c.dispose);
    return c;
  }

  test('a cold start does not report the server as missing', () async {
    await h.seedServer();
    final c = container();

    // Asked at once, while the stored server is still being read.
    expect(await c.read(serverStatusProvider.future), isNull);
  });

  test('a server that answers as another one is reported', () async {
    await h.seedServer();
    h.infoApi.info = const ServerInfo(
      serverId: 'someone-else',
      name: 'Home',
      version: '0.1.0',
    );
    final c = container();

    expect(
      await c.read(serverStatusProvider.future),
      isA<ServerMismatchFailure>(),
    );
  });

  test('nothing is reported while no server is configured', () async {
    final c = container();

    expect(await c.read(serverStatusProvider.future), isNull);
  });
}
