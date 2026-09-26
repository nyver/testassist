import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';

import '../errors/app_failure.dart';
import '../security/fingerprint.dart';

/// Connect and response timeouts required by the specification.
const connectTimeout = Duration(seconds: 10);
const receiveTimeout = Duration(seconds: 60);

/// Remembers whether the last handshake was rejected because the presented
/// certificate did not match the pin. Dio only reports a generic handshake
/// error, so this is how the failure becomes `CERTIFICATE_CHANGED`.
class PinRecorder {
  bool _mismatch = false;

  bool get certificateChanged => _mismatch;

  void recordMismatch() => _mismatch = true;

  void reset() => _mismatch = false;
}

/// An HTTP client for exactly one server, with its trust decision built in.
class ApiConnection {
  ApiConnection({required this.dio, required this.recorder});

  final Dio dio;
  final PinRecorder recorder;

  /// Runs [call] and converts every Dio failure to an [AppFailure].
  Future<T> guard<T>(Future<T> Function(Dio dio) call) async {
    try {
      return await call(dio);
    } on DioException catch (e) {
      throw mapDioException(e, recorder);
    } on AppFailure {
      rethrow;
    } on Object catch (e) {
      // Decoding problems and the like: keep the type, drop the content.
      throw UnexpectedFailure(e.runtimeType.toString());
    }
  }

  void close() => dio.close(force: true);
}

/// Creates the HTTP client for the configured server.
///
/// * Without a pin the platform trust store decides and nothing is overridden:
///   the certificate must be valid for the host.
/// * With a pin no system roots are trusted. Every handshake then goes through
///   the bad-certificate callback, which accepts only the pinned server's host
///   and port and only the pinned leaf fingerprint. This holds even for
///   certificates a public CA would accept, so a pinned server cannot be
///   swapped for another certificate, and a mismatch aborts the handshake
///   before any request data (including the token) is written.
///
/// There is deliberately no code path that accepts a certificate
/// unconditionally.
ApiConnection createApiConnection({
  required Uri baseUrl,
  String? pinnedFingerprint,
  String? token,
  SecurityContext? trustedRoots,
}) {
  final recorder = PinRecorder();
  final pinned = pinnedFingerprint;
  final host = baseUrl.host;
  final port = baseUrl.hasPort ? baseUrl.port : 443;

  bool matchesPin(X509Certificate? cert, String forHost, int forPort) {
    if (pinned == null || cert == null) return false;
    if (forHost != host || forPort != port) return false;
    final matches = certificateFingerprint(cert.der) == pinned;
    if (!matches) recorder.recordMismatch();
    return matches;
  }

  final adapter = IOHttpClientAdapter(
    createHttpClient: () {
      final context = pinned != null
          ? SecurityContext(withTrustedRoots: false)
          : (trustedRoots ?? SecurityContext(withTrustedRoots: true));
      final client = HttpClient(context: context);
      client.badCertificateCallback = matchesPin;
      return client;
    },
    // Defense in depth: after a response, re-check the pin for pinned servers.
    validateCertificate: (cert, forHost, forPort) =>
        pinned == null || matchesPin(cert, forHost, forPort),
  );

  final dio = Dio(
    BaseOptions(
      baseUrl: _normalizedBase(baseUrl),
      connectTimeout: connectTimeout,
      receiveTimeout: receiveTimeout,
      sendTimeout: receiveTimeout,
      responseType: ResponseType.json,
      headers: {'Accept': 'application/json'},
    ),
  )..httpClientAdapter = adapter;

  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) {
        recorder.reset();
        if (token != null && token.isNotEmpty) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        handler.next(options);
      },
    ),
  );

  return ApiConnection(dio: dio, recorder: recorder);
}

String _normalizedBase(Uri url) {
  final text = url.toString();
  return text.endsWith('/') ? text.substring(0, text.length - 1) : text;
}

/// Converts a Dio failure to an [AppFailure].
AppFailure mapDioException(DioException e, PinRecorder recorder) {
  if (e.type == DioExceptionType.cancel) return const CancelledFailure();
  if (recorder.certificateChanged) return const CertificateChangedFailure();

  final response = e.response;
  if (response != null) {
    final failure = ApiFailure.fromEnvelope(
      response.data,
      statusCode: response.statusCode,
    );
    if (failure != null) return failure;
    return UnexpectedFailure('HTTP ${response.statusCode}');
  }

  switch (e.type) {
    case DioExceptionType.connectionTimeout:
    case DioExceptionType.sendTimeout:
    case DioExceptionType.receiveTimeout:
    case DioExceptionType.connectionError:
    case DioExceptionType.badCertificate:
      return NetworkFailure(e.type.name);
    case DioExceptionType.badResponse:
    case DioExceptionType.cancel:
    case DioExceptionType.transformTimeout:
    case DioExceptionType.unknown:
      final inner = e.error;
      if (inner is SocketException ||
          inner is TlsException ||
          inner is HttpException) {
        return NetworkFailure(inner.runtimeType.toString());
      }
      return UnexpectedFailure(e.type.name);
  }
}
