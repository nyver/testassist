import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:test_assistant/core/errors/app_failure.dart';
import 'package:test_assistant/core/network/pinned_dio.dart';
import 'package:test_assistant/core/security/certificate_probe.dart';
import 'package:test_assistant/core/security/fingerprint.dart';

import '../support/tls_test_server.dart';

void main() {
  group('fingerprint', () {
    test('matches the Go server fixture (independent openssl value)', () {
      const dir = '../../protocol/fixtures/tls';
      final der = pemToDer('$dir/fingerprint_cert.pem');
      final expected = File('$dir/fingerprint_cert.sha256.txt')
          .readAsStringSync()
          .trim();

      final actual = certificateFingerprint(der);

      expect(actual, expected);
      expect(actual.length, 95);
      expect(actual, matches(RegExp(r'^([0-9A-F]{2}:){31}[0-9A-F]{2}$')));
    });
  });

  group('TLS trust', () {
    late String self1Fingerprint;
    late String self2Fingerprint;

    setUpAll(() {
      self1Fingerprint = certificateFingerprint(
        pemToDer('$tlsFixtureDir/self1.pem'),
      );
      self2Fingerprint = certificateFingerprint(
        pemToDer('$tlsFixtureDir/self2.pem'),
      );
    });

    Uri urlOf(TlsTestServer server, {String host = '127.0.0.1'}) =>
        Uri.parse('https://$host:${server.port}');

    test('the fixtures are distinct certificates', () {
      expect(self1Fingerprint, isNot(self2Fingerprint));
    });

    test('a certificate from a trusted CA needs no pin', () async {
      final server = await TlsTestServer.start(
        certFile: 'leaf.pem',
        keyFile: 'leaf.key.pem',
      );
      addTearDown(server.close);

      final probe = await SocketCertificateProbe(
        securityContext: testCaContext(),
      ).probe(urlOf(server));
      expect(probe, isA<ProbeTrusted>());
      expect(
        server.requestCount,
        0,
        reason: 'a probe must not send HTTP bytes',
      );

      final connection = createApiConnection(
        baseUrl: urlOf(server),
        token: 'secret-token',
        trustedRoots: testCaContext(),
      );
      addTearDown(connection.close);
      final response = await connection.guard(
        (dio) => dio.get<Object?>('/api/v1/server/info'),
      );
      expect(response.statusCode, 200);
      expect(server.authorizationHeaders, ['Bearer secret-token']);
    });

    test('a self-signed certificate is captured by the probe without sending '
        'any request', () async {
      final server = await TlsTestServer.start(
        certFile: 'self1.pem',
        keyFile: 'self1.key.pem',
      );
      addTearDown(server.close);

      final probe = await SocketCertificateProbe(
        securityContext: SecurityContext(withTrustedRoots: false),
      ).probe(urlOf(server));

      expect(probe, isA<ProbeUntrusted>());
      expect((probe as ProbeUntrusted).fingerprint, self1Fingerprint);
      expect(server.requestCount, 0);
    });

    test('without a pin an untrusted certificate is rejected and no token is '
        'sent', () async {
      final server = await TlsTestServer.start(
        certFile: 'self1.pem',
        keyFile: 'self1.key.pem',
      );
      addTearDown(server.close);
      final connection = createApiConnection(
        baseUrl: urlOf(server),
        token: 'secret-token',
        trustedRoots: SecurityContext(withTrustedRoots: false),
      );
      addTearDown(connection.close);

      await expectLater(
        connection.guard((dio) => dio.get<Object?>('/api/v1/server/info')),
        throwsA(isA<NetworkFailure>()),
      );
      expect(server.requestCount, 0);
    });

    test('a pinned server with the matching certificate is served', () async {
      final server = await TlsTestServer.start(
        certFile: 'self1.pem',
        keyFile: 'self1.key.pem',
      );
      addTearDown(server.close);
      final connection = createApiConnection(
        baseUrl: urlOf(server),
        pinnedFingerprint: self1Fingerprint,
        token: 'secret-token',
      );
      addTearDown(connection.close);

      final response = await connection.guard(
        (dio) => dio.get<Object?>('/api/v1/server/info'),
      );

      expect(response.statusCode, 200);
      expect(server.authorizationHeaders, ['Bearer secret-token']);
    });

    test('a changed certificate is blocked as CERTIFICATE_CHANGED before any '
        'request data is sent', () async {
      final server = await TlsTestServer.start(
        certFile: 'self2.pem',
        keyFile: 'self2.key.pem',
      );
      addTearDown(server.close);
      final connection = createApiConnection(
        baseUrl: urlOf(server),
        pinnedFingerprint: self1Fingerprint, // pinned earlier, now different
        token: 'secret-token',
      );
      addTearDown(connection.close);

      await expectLater(
        connection.guard((dio) => dio.get<Object?>('/api/v1/server/info')),
        throwsA(isA<CertificateChangedFailure>()),
      );
      expect(server.requestCount, 0, reason: 'the token must not be sent');
      expect(server.authorizationHeaders, isEmpty);
    });

    test('a pin also rejects a certificate that a CA would accept, if it is a '
        'different one', () async {
      // The leaf is valid under the test CA, but the pin says otherwise.
      final server = await TlsTestServer.start(
        certFile: 'leaf.pem',
        keyFile: 'leaf.key.pem',
      );
      addTearDown(server.close);
      final connection = createApiConnection(
        baseUrl: urlOf(server),
        pinnedFingerprint: self1Fingerprint,
        token: 'secret-token',
        trustedRoots: testCaContext(),
      );
      addTearDown(connection.close);

      await expectLater(
        connection.guard((dio) => dio.get<Object?>('/api/v1/server/info')),
        throwsA(isA<CertificateChangedFailure>()),
      );
      expect(server.requestCount, 0);
    });

    test('the pin applies only to the configured host and port', () async {
      final pinnedServer = await TlsTestServer.start(
        certFile: 'self1.pem',
        keyFile: 'self1.key.pem',
      );
      final otherPort = await TlsTestServer.start(
        certFile: 'self1.pem', // identical certificate, different port
        keyFile: 'self1.key.pem',
      );
      addTearDown(pinnedServer.close);
      addTearDown(otherPort.close);
      final connection = createApiConnection(
        baseUrl: urlOf(pinnedServer),
        pinnedFingerprint: self1Fingerprint,
        token: 'secret-token',
      );
      addTearDown(connection.close);

      // Same certificate and host, other port: rejected.
      await expectLater(
        connection.guard(
          (dio) => dio.getUri<Object?>(urlOf(otherPort).resolve('/x')),
        ),
        throwsA(isA<AppFailure>()),
      );
      // Same certificate and port, other host name: rejected.
      await expectLater(
        connection.guard(
          (dio) => dio.getUri<Object?>(
            urlOf(pinnedServer, host: 'localhost').resolve('/x'),
          ),
        ),
        throwsA(isA<AppFailure>()),
      );
      expect(otherPort.requestCount, 0);
      expect(pinnedServer.requestCount, 0);

      // The configured host and port still work.
      final ok = await connection.guard(
        (dio) => dio.get<Object?>('/api/v1/server/info'),
      );
      expect(ok.statusCode, 200);
    });

    test('an unrelated self-signed host is rejected without a pin', () async {
      final server = await TlsTestServer.start(
        certFile: 'self2.pem',
        keyFile: 'self2.key.pem',
      );
      addTearDown(server.close);
      // The application-wide default client must not have been loosened.
      final client = HttpClient(
        context: SecurityContext(withTrustedRoots: false),
      );
      addTearDown(() => client.close(force: true));
      await expectLater(
        client.getUrl(urlOf(server)).then((r) => r.close()),
        throwsA(isA<HandshakeException>()),
      );
    });

    test('unreachable server is a network failure', () async {
      final server = await TlsTestServer.start(
        certFile: 'self1.pem',
        keyFile: 'self1.key.pem',
      );
      final url = urlOf(server);
      await server.close();

      await expectLater(
        SocketCertificateProbe().probe(url),
        throwsA(isA<NetworkFailure>()),
      );
      final connection = createApiConnection(
        baseUrl: url,
        pinnedFingerprint: self1Fingerprint,
      );
      addTearDown(connection.close);
      await expectLater(
        connection.guard((dio) => dio.get<Object?>('/api/v1/server/info')),
        throwsA(isA<NetworkFailure>()),
      );
    });
  });

  group('connection settings', () {
    test('timeouts follow the specification', () {
      final connection = createApiConnection(
        baseUrl: Uri.parse('https://example.test:8443'),
      );
      addTearDown(connection.close);
      expect(
        connection.dio.options.connectTimeout,
        const Duration(seconds: 10),
      );
      expect(
        connection.dio.options.receiveTimeout,
        const Duration(seconds: 60),
      );
    });

    test('a trailing slash of the base URL is dropped', () {
      final connection = createApiConnection(
        baseUrl: Uri.parse('https://example.test:8443/'),
      );
      addTearDown(connection.close);
      expect(connection.dio.options.baseUrl, 'https://example.test:8443');
    });
  });

  group('mapDioException', () {
    final request = RequestOptions(path: '/x');

    Response<Object?> envelopeResponse(Object? data, int status) =>
        Response<Object?>(
          requestOptions: request,
          data: data,
          statusCode: status,
        );

    test('an error envelope becomes an ApiFailure with its request id', () {
      final failure = mapDioException(
        DioException.badResponse(
          statusCode: 500,
          requestOptions: request,
          response: envelopeResponse({
            'error': {
              'code': 'INTERNAL_ERROR',
              'message': 'Internal server error.',
              'requestId': 'abc',
            },
          }, 500),
        ),
        PinRecorder(),
      );
      expect(failure, isA<ApiFailure>());
      final api = failure as ApiFailure;
      expect(api.code, 'INTERNAL_ERROR');
      expect(api.requestId, 'abc');
      expect(api.statusCode, 500);
    });

    test('a body that is not an envelope is unexpected, not raw text', () {
      final failure = mapDioException(
        DioException.badResponse(
          statusCode: 502,
          requestOptions: request,
          response: envelopeResponse('<html>bad gateway</html>', 502),
        ),
        PinRecorder(),
      );
      expect(failure, isA<UnexpectedFailure>());
    });

    test('cancellation, timeouts and connection errors', () {
      expect(
        mapDioException(
          DioException.requestCancelled(requestOptions: request, reason: 'x'),
          PinRecorder(),
        ),
        isA<CancelledFailure>(),
      );
      expect(
        mapDioException(
          DioException.connectionTimeout(
            timeout: const Duration(seconds: 1),
            requestOptions: request,
          ),
          PinRecorder(),
        ),
        isA<NetworkFailure>(),
      );
      expect(
        mapDioException(
          DioException.connectionError(
            requestOptions: request,
            reason: 'refused',
          ),
          PinRecorder(),
        ),
        isA<NetworkFailure>(),
      );
      expect(
        mapDioException(
          DioException(
            requestOptions: request,
            error: const SocketException('down'),
          ),
          PinRecorder(),
        ),
        isA<NetworkFailure>(),
      );
    });

    test('a recorded pin mismatch wins over the generic handshake error', () {
      final recorder = PinRecorder()..recordMismatch();
      expect(
        mapDioException(
          DioException.connectionError(requestOptions: request, reason: 'tls'),
          recorder,
        ),
        isA<CertificateChangedFailure>(),
      );
    });
  });
}
