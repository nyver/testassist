import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:test_assistant/app/app.dart';
import 'package:test_assistant/core/errors/app_failure.dart';
import 'package:test_assistant/core/security/certificate_probe.dart';

import '../support/harness.dart';

const _fingerprint =
    'A6:DB:F0:CA:E2:29:AD:8C:3D:25:BD:40:31:83:4B:72:58:78:2B:C6:A4:10:7F:BC:6D:3C:8B:23:F8:9F:73:EF';

Future<void> _pumpApp(WidgetTester tester, Harness h) async {
  tester.view.physicalSize = const Size(900, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      retry: (count, error) => null,
      overrides: h.overrides(withServer: false),
      child: const TestAssistantApp(),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _fillForm(
  WidgetTester tester, {
  String url = 'https://192.168.1.10:8443',
  String name = 'Home',
  String token = 'secret-token',
}) async {
  await tester.enterText(find.byKey(const Key('setup-url')), url);
  await tester.enterText(find.byKey(const Key('setup-name')), name);
  await tester.enterText(find.byKey(const Key('setup-token')), token);
}

/// Pumps a few frames. pumpAndSettle cannot be used while the connect button
/// shows its indeterminate progress indicator.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  late Harness h;

  setUp(() async => h = await Harness.create());
  tearDown(() => h.dispose());

  testWidgets('without a server the app opens the setup screen', (
    tester,
  ) async {
    await _pumpApp(tester, h);
    expect(find.byKey(const Key('setup-url')), findsOneWidget);
    expect(find.byKey(const Key('main-take-photo')), findsNothing);
  });

  testWidgets('an http address is rejected without any connection attempt', (
    tester,
  ) async {
    await _pumpApp(tester, h);

    await _fillForm(tester, url: 'http://192.168.1.10:8443');
    await tester.tap(find.byKey(const Key('setup-connect')));
    await tester.pumpAndSettle();

    expect(find.text('Only https:// addresses are supported.'), findsOneWidget);
    expect(h.probe.probed, isEmpty);
    expect(h.infoApi.calls, 0);
  });

  testWidgets('a malformed address and empty fields are rejected', (
    tester,
  ) async {
    await _pumpApp(tester, h);

    await _fillForm(tester, url: 'not a url', name: '', token: '');
    await tester.tap(find.byKey(const Key('setup-connect')));
    await tester.pumpAndSettle();

    expect(
      find.text('Enter a valid address that starts with https://'),
      findsOneWidget,
    );
    expect(find.text('Enter a name.'), findsOneWidget);
    expect(find.text('Enter the token.'), findsOneWidget);
    expect(h.probe.probed, isEmpty);
  });

  testWidgets(
    'cancelling the fingerprint dialog saves nothing and sends no token',
    (tester) async {
      h.probe.result = const ProbeUntrusted(_fingerprint);
      await _pumpApp(tester, h);

      await _fillForm(tester);
      await tester.tap(find.byKey(const Key('setup-connect')));
      await _settle(tester);

      // The dialog names the server and shows the fingerprint to compare.
      expect(find.text('Trust this certificate?'), findsOneWidget);
      expect(
        tester
            .widget<SelectableText>(find.byKey(const Key('trust-fingerprint')))
            .data,
        _fingerprint,
      );
      expect(find.textContaining('https://192.168.1.10:8443'), findsWidgets);

      await tester.tap(find.text('Cancel'));
      await _settle(tester);

      expect(h.infoApi.calls, 0, reason: 'the token must not be used');
      expect(await h.servers.current(), isNull);
      expect(h.secrets.values, isEmpty);
      expect(find.byKey(const Key('setup-url')), findsOneWidget);
    },
  );

  testWidgets('an invalid token is reported and nothing is saved', (
    tester,
  ) async {
    h.infoApi.failure = const ApiFailure(
      code: 'UNAUTHORIZED',
      message: 'nope',
      requestId: 'r1',
      statusCode: 401,
    );
    await _pumpApp(tester, h);

    await _fillForm(tester, token: 'wrong');
    await tester.tap(find.byKey(const Key('setup-connect')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('setup-error')), findsOneWidget);
    expect(find.textContaining('The token is invalid'), findsOneWidget);
    expect(await h.servers.current(), isNull);
    expect(h.secrets.values, isEmpty);
  });

  testWidgets('an unreachable server shows the network message', (
    tester,
  ) async {
    h.probe.result = const NetworkFailure('refused');
    await _pumpApp(tester, h);

    await _fillForm(tester);
    await tester.tap(find.byKey(const Key('setup-connect')));
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Could not connect to the server. Check the network and server address.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('trusting the fingerprint stores it and the token securely', (
    tester,
  ) async {
    h.probe.result = const ProbeUntrusted(_fingerprint);
    await _pumpApp(tester, h);

    await _fillForm(tester);
    await tester.tap(find.byKey(const Key('setup-connect')));
    await _settle(tester);
    await tester.tap(find.text('Trust'));
    await _settle(tester);
    await tester.pumpAndSettle();

    final record = (await h.servers.current())!;
    expect(record.serverId, Harness.serverId);
    expect(record.name, 'Home');
    expect(h.secrets.values, {
      'v1/server/${record.id}/token': 'secret-token',
      'v1/server/${record.id}/fingerprint': _fingerprint,
    });
    // The main screen is usable.
    expect(find.byKey(const Key('main-take-photo')), findsOneWidget);
  });

  testWidgets('a publicly trusted certificate needs no confirmation or pin', (
    tester,
  ) async {
    h.probe.result = const ProbeTrusted();
    await _pumpApp(tester, h);

    await _fillForm(tester);
    await tester.tap(find.byKey(const Key('setup-connect')));
    await tester.pumpAndSettle();

    expect(find.text('Trust this certificate?'), findsNothing);
    final record = (await h.servers.current())!;
    expect(h.secrets.values.keys, ['v1/server/${record.id}/token']);
    expect(find.byKey(const Key('main-take-photo')), findsOneWidget);
  });

  testWidgets('the four main actions are visible', (tester) async {
    await h.seedServer();
    await _pumpApp(tester, h);

    for (final key in [
      'main-take-photo',
      'main-choose-image',
      'main-history',
      'main-settings',
    ]) {
      expect(find.byKey(Key(key)), findsOneWidget, reason: key);
    }
  });

  group('server settings', () {
    Future<void> openServerSettings(WidgetTester tester) async {
      await tester.tap(find.byKey(const Key('main-server-settings')));
      await tester.pumpAndSettle();
    }

    testWidgets('shows name, address, id and the pinned fingerprint', (
      tester,
    ) async {
      await h.seedServer(pin: _fingerprint);
      await _pumpApp(tester, h);
      await openServerSettings(tester);

      expect(find.text('Home'), findsWidgets);
      expect(find.text('https://192.168.1.10:8443'), findsOneWidget);
      expect(find.text(Harness.serverId), findsOneWidget);
      expect(find.text(_fingerprint), findsOneWidget);
    });

    testWidgets('reset trust deletes the pin and asks for the new one', (
      tester,
    ) async {
      await h.seedServer(pin: 'OLD:PIN');
      h.probe.result = const ProbeUntrusted(_fingerprint);
      await _pumpApp(tester, h);
      await openServerSettings(tester);

      await tester.tap(find.byKey(const Key('server-reset-trust')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();

      // The next connection shows the fingerprint confirmation dialog.
      expect(find.text('Trust this certificate?'), findsOneWidget);
      final id = (await h.servers.current())!.id;
      expect(h.secrets.values['v1/server/$id/fingerprint'], isNull);

      await tester.tap(find.text('Trust'));
      await tester.pumpAndSettle();
      expect(h.secrets.values['v1/server/$id/fingerprint'], _fingerprint);
      expect(find.text(_fingerprint), findsOneWidget);
    });

    testWidgets('cancelling after a reset leaves no pin', (tester) async {
      await h.seedServer(pin: 'OLD:PIN');
      h.probe.result = const ProbeUntrusted(_fingerprint);
      await _pumpApp(tester, h);
      await openServerSettings(tester);

      await tester.tap(find.byKey(const Key('server-reset-trust')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      final id = (await h.servers.current())!.id;
      expect(h.secrets.values['v1/server/$id/fingerprint'], isNull);
      expect(h.secrets.values['v1/server/$id/token'], 'token-1');
    });

    testWidgets('declining the reset confirmation keeps the pin', (
      tester,
    ) async {
      await h.seedServer(pin: 'OLD:PIN');
      await _pumpApp(tester, h);
      await openServerSettings(tester);

      await tester.tap(find.byKey(const Key('server-reset-trust')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      final id = (await h.servers.current())!.id;
      expect(h.secrets.values['v1/server/$id/fingerprint'], 'OLD:PIN');
      expect(h.probe.probed, isEmpty);
    });

    testWidgets('a new token is verified and stored only on success', (
      tester,
    ) async {
      await h.seedServer();
      await _pumpApp(tester, h);
      await openServerSettings(tester);
      final id = (await h.servers.current())!.id;

      h.infoApi.failure = const ApiFailure(
        code: 'UNAUTHORIZED',
        message: 'no',
        statusCode: 401,
      );
      await tester.tap(find.byKey(const Key('server-replace-token')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'bad-token');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(h.secrets.values['v1/server/$id/token'], 'token-1');
      expect(find.textContaining('The token is invalid'), findsOneWidget);

      h.infoApi.failure = null;
      await tester.tap(find.byKey(const Key('server-replace-token')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'new-token');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(h.secrets.values['v1/server/$id/token'], 'new-token');
    });

    testWidgets('removing the server deletes its secrets', (tester) async {
      await h.seedServer(pin: _fingerprint);
      await _pumpApp(tester, h);
      await openServerSettings(tester);

      await tester.tap(find.byKey(const Key('server-remove')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove'));
      await tester.pumpAndSettle();

      expect(h.secrets.values, isEmpty);
      expect(await h.servers.current(), isNull);
      expect(find.byKey(const Key('setup-url')), findsOneWidget);
    });
  });
}
