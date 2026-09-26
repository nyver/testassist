import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:test_assistant/app/app.dart';
import 'package:test_assistant/core/di/providers.dart';
import 'package:test_assistant/core/errors/app_failure.dart';
import 'package:test_assistant/features/servers/domain/server_info_api.dart';
import 'package:test_assistant/features/servers/domain/server_service.dart';

import '../support/harness.dart';

void main() {
  group('parseServerUrl', () {
    test('accepts https addresses and normalizes a trailing slash', () {
      for (final (input, expected) in [
        ('https://192.168.1.10:8443', 'https://192.168.1.10:8443'),
        ('https://assistant.example.com', 'https://assistant.example.com'),
        ('  https://a.example:8443/  ', 'https://a.example:8443'),
        ('HTTPS://a.example', 'https://a.example'),
        ('https://a.example/prefix/', 'https://a.example/prefix'),
      ]) {
        final r = parseServerUrl(input);
        expect(r.problem, isNull, reason: input);
        expect(r.url.toString(), expected, reason: input);
      }
    });

    test('rejects other schemes and malformed input', () {
      for (final input in [
        'http://192.168.1.10:8443',
        'ftp://a.example',
        'ws://a.example',
      ]) {
        expect(
          parseServerUrl(input).problem,
          ServerUrlProblem.notHttps,
          reason: input,
        );
      }
      for (final input in [
        '',
        '   ',
        'a.example',
        'not a url',
        'https://',
        'https://a.example/?x=1',
        'https://a.example/#frag',
      ]) {
        expect(
          parseServerUrl(input).problem,
          ServerUrlProblem.invalid,
          reason: input,
        );
      }
    });
  });

  group('server identity check', () {
    late Harness h;
    setUp(() async => h = await Harness.create());
    tearDown(() => h.dispose());

    ProviderContainer containerFor() {
      final c = ProviderContainer(
        retry: (count, error) => null,
        overrides: h.overrides(withServer: false),
      );
      addTearDown(c.dispose);
      return c;
    }

    test('the same serverId passes', () async {
      await h.seedServer();
      final c = containerFor();
      await c.read(serverSessionProvider.future);

      final info = await c.read(serverServiceProvider).verifyIdentity();

      expect(info.serverId, Harness.serverId);
    });

    test('a different serverId is a mismatch', () async {
      await h.seedServer();
      h.infoApi.info = const ServerInfo(
        serverId: '00000000-0000-7000-8000-000000000000',
        name: 'Other',
        version: '0.1.0',
      );
      final c = containerFor();
      await c.read(serverSessionProvider.future);

      await expectLater(
        c.read(serverServiceProvider).verifyIdentity(),
        throwsA(isA<ServerMismatchFailure>()),
      );
    });

    test('an unreachable server keeps its own failure type', () async {
      await h.seedServer();
      h.infoApi.failure = const NetworkFailure('down');
      final c = containerFor();
      await c.read(serverSessionProvider.future);

      await expectLater(
        c.read(serverServiceProvider).verifyIdentity(),
        throwsA(isA<NetworkFailure>()),
      );
    });

    test(
      'resetting trust against a different server removes the pin again',
      () async {
        await h.seedServer(pin: 'OLD');
        h.infoApi.info = const ServerInfo(
          serverId: 'ffffffff-0000-7000-8000-000000000000',
          name: 'Other',
          version: '0.1.0',
        );
        final c = containerFor();
        await c.read(serverSessionProvider.future);
        final id = (await h.servers.current())!.id;

        final outcome = await c
            .read(serverServiceProvider)
            .resetTrust((fingerprint) async => true);

        expect(outcome, isA<SetupError>());
        expect((outcome as SetupError).failure, isA<ServerMismatchFailure>());
        expect(h.secrets.values['v1/server/$id/fingerprint'], isNull);
      },
    );

    test(
      'replacing the token reports a storage error and keeps the old one',
      () async {
        await h.seedServer(token: 'old-token');
        final id = (await h.servers.current())!.id;
        final c = containerFor();
        await c.read(serverSessionProvider.future);
        h.secrets.failWrites = true;

        final failure = await c
            .read(serverServiceProvider)
            .replaceToken('new-token');

        expect(failure, isA<UnexpectedFailure>());
        expect(h.secrets.values['v1/server/$id/token'], 'old-token');
      },
    );

    test(
      'resetting trust reports an unexpected error instead of throwing',
      () async {
        await h.seedServer(pin: 'PIN');
        h.probe.result = StateError('boom');
        final c = containerFor();
        await c.read(serverSessionProvider.future);

        final outcome = await c
            .read(serverServiceProvider)
            .resetTrust((fingerprint) async => true);

        expect(outcome, isA<SetupError>());
        expect((outcome as SetupError).failure, isA<UnexpectedFailure>());
      },
    );

    testWidgets('the main screen tells the user that another server answered', (
      tester,
    ) async {
      await h.seedServer();
      tester.view.physicalSize = const Size(900, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          retry: (count, error) => null,
          overrides: [
            ...h.overrides(withServer: false),
            serverIdentityVerifierProvider.overrideWithValue(
              () async => throw const ServerMismatchFailure(),
            ),
          ],
          child: const TestAssistantApp(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('server-banner')), findsOneWidget);
      expect(
        find.textContaining('A different server responded at this address'),
        findsOneWidget,
      );
    });

    testWidgets('a changed certificate is reported with advice', (
      tester,
    ) async {
      await h.seedServer(pin: 'PIN');
      tester.view.physicalSize = const Size(900, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          retry: (count, error) => null,
          overrides: [
            ...h.overrides(withServer: false),
            serverIdentityVerifierProvider.overrideWithValue(
              () async => throw const CertificateChangedFailure(),
            ),
          ],
          child: const TestAssistantApp(),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('Server certificate has changed. Connection blocked.'),
        findsOneWidget,
      );
      expect(
        find.textContaining('reset the trusted certificate'),
        findsOneWidget,
      );
    });
  });
}
