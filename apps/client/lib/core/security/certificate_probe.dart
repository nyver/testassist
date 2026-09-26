import 'dart:async';
import 'dart:io';

import '../errors/app_failure.dart';
import 'fingerprint.dart';

/// Outcome of probing a server's TLS certificate.
sealed class ProbeResult {
  const ProbeResult();
}

/// The certificate passed standard platform validation. No pin is needed.
final class ProbeTrusted extends ProbeResult {
  const ProbeTrusted();
}

/// The certificate failed standard validation. [fingerprint] is what the user
/// has to compare with the one printed by the server.
final class ProbeUntrusted extends ProbeResult {
  const ProbeUntrusted(this.fingerprint);

  final String fingerprint;
}

/// Reads the certificate a server presents, without sending any HTTP request.
abstract interface class CertificateProbe {
  Future<ProbeResult> probe(Uri url);
}

/// Probes with a bare TLS handshake. A bad certificate is captured and then
/// rejected, so the connection is always closed after the handshake and no
/// bytes (and therefore no token) are ever written to it.
class SocketCertificateProbe implements CertificateProbe {
  SocketCertificateProbe({
    this.securityContext,
    this.timeout = const Duration(seconds: 10),
  });

  /// Trust anchors to use instead of the platform defaults. Tests inject a
  /// test CA here.
  final SecurityContext? securityContext;
  final Duration timeout;

  @override
  Future<ProbeResult> probe(Uri url) async {
    final port = url.hasPort ? url.port : 443;
    X509Certificate? captured;

    try {
      final socket = await SecureSocket.connect(
        url.host,
        port,
        context: securityContext,
        timeout: timeout,
        onBadCertificate: (certificate) {
          captured = certificate;
          return false; // Never accept here: the user decides afterwards.
        },
      );
      await socket.close();
      socket.destroy();
      return const ProbeTrusted();
    } on HandshakeException catch (e) {
      final certificate = captured;
      if (certificate == null) {
        throw NetworkFailure('TLS handshake failed: ${e.message}');
      }
      return ProbeUntrusted(certificateFingerprint(certificate.der));
    } on TlsException catch (e) {
      throw NetworkFailure('TLS error: ${e.message}');
    } on SocketException catch (e) {
      throw NetworkFailure('Socket error: ${e.message}');
    } on TimeoutException {
      throw const NetworkFailure('Connection timed out');
    }
  }
}
