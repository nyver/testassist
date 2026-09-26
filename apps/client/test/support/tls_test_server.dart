import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Directory of the test-only TLS fixtures (see its README).
const tlsFixtureDir = 'test/fixtures/tls';

/// Reads the first certificate of a PEM file as DER bytes.
Uint8List pemToDer(String path) {
  final pem = File(path).readAsStringSync();
  final body = pem
      .split('-----BEGIN CERTIFICATE-----')[1]
      .split('-----END CERTIFICATE-----')[0]
      .replaceAll(RegExp(r'\s'), '');
  return base64.decode(body);
}

/// An HTTPS server on loopback that records what it receives.
class TlsTestServer {
  TlsTestServer._(this._server);

  final HttpServer _server;

  /// `Authorization` header values of every request that reached the server.
  final List<String?> authorizationHeaders = [];

  int get requestCount => authorizationHeaders.length;
  int get port => _server.port;

  /// Starts a server presenting [certFile] with [keyFile] (names inside
  /// [tlsFixtureDir]). [chainFile] overrides the served chain when given.
  static Future<TlsTestServer> start({
    required String certFile,
    required String keyFile,
  }) async {
    final context = SecurityContext()
      ..useCertificateChain('$tlsFixtureDir/$certFile')
      ..usePrivateKey('$tlsFixtureDir/$keyFile');
    final server = await HttpServer.bindSecure(
      InternetAddress.loopbackIPv4,
      0,
      context,
    );
    final wrapper = TlsTestServer._(server);
    server.listen((request) async {
      wrapper.authorizationHeaders.add(
        request.headers.value(HttpHeaders.authorizationHeader),
      );
      request.response
        ..statusCode = 200
        ..headers.contentType = ContentType.json
        ..write(
          '{"serverId":"019d2f6e-8a3c-7c1e-9b41-5d2a6f0e1c77",'
          '"name":"Test","version":"0.1.0"}',
        );
      await request.response.close();
    });
    return wrapper;
  }

  Future<void> close() => _server.close(force: true);
}

/// A [SecurityContext] that trusts only the test CA.
SecurityContext testCaContext() {
  return SecurityContext(withTrustedRoots: false)
    ..setTrustedCertificates('$tlsFixtureDir/ca.pem');
}
