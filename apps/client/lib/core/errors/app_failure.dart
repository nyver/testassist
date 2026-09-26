/// Typed failures that repositories and API clients throw.
///
/// The UI never shows exception text: it maps a failure to a localized message
/// (see `failure_messages.dart`).
sealed class AppFailure implements Exception {
  const AppFailure();
}

/// The server could not be reached: DNS, refused connection, timeout, or a TLS
/// handshake that failed for a reason other than a pin mismatch.
final class NetworkFailure extends AppFailure {
  const NetworkFailure([this.detail]);

  /// Short technical hint for logs. Never shown to the user.
  final String? detail;
}

/// A pinned server presented a certificate with a different fingerprint. The
/// connection was aborted before any request data was sent.
final class CertificateChangedFailure extends AppFailure {
  const CertificateChangedFailure();
}

/// The address answered with a `serverId` other than the stored one.
final class ServerMismatchFailure extends AppFailure {
  const ServerMismatchFailure();
}

/// The server answered with an error envelope.
final class ApiFailure extends AppFailure {
  const ApiFailure({
    required this.code,
    required this.message,
    this.requestId,
    this.statusCode,
  });

  /// One of the stable API error codes, for example `LLM_TIMEOUT`.
  final String code;

  /// English server message. Never shown to the user.
  final String message;
  final String? requestId;
  final int? statusCode;

  /// Builds a failure from a decoded error envelope, or `null` when [body] is
  /// not one.
  static ApiFailure? fromEnvelope(Object? body, {int? statusCode}) {
    if (body is! Map<String, Object?>) return null;
    final error = body['error'];
    if (error is! Map<String, Object?>) return null;
    final code = error['code'];
    if (code is! String) return null;
    final message = error['message'];
    final requestId = error['requestId'];
    return ApiFailure(
      code: code,
      message: message is String ? message : '',
      requestId: requestId is String && requestId.isNotEmpty ? requestId : null,
      statusCode: statusCode,
    );
  }
}

/// The user cancelled the operation.
final class CancelledFailure extends AppFailure {
  const CancelledFailure();
}

/// Anything else, for example an unreadable server reply.
final class UnexpectedFailure extends AppFailure {
  const UnexpectedFailure([this.detail]);

  /// Short technical hint for logs. Never shown to the user.
  final String? detail;
}

/// Stable API error codes the client reacts to.
abstract final class ApiErrorCodes {
  static const invalidRequest = 'INVALID_REQUEST';
  static const unauthorized = 'UNAUTHORIZED';
  static const providerNotFound = 'PROVIDER_NOT_FOUND';
  static const modelNotFound = 'MODEL_NOT_FOUND';
  static const imageTooLarge = 'IMAGE_TOO_LARGE';
  static const unsupportedImageType = 'UNSUPPORTED_IMAGE_TYPE';
  static const modelNoVision = 'MODEL_DOES_NOT_SUPPORT_VISION';
  static const rateLimited = 'RATE_LIMITED';
  static const internalError = 'INTERNAL_ERROR';
  static const llmProviderUnavailable = 'LLM_PROVIDER_UNAVAILABLE';
  static const llmInvalidResponse = 'LLM_INVALID_RESPONSE';
  static const llmTimeout = 'LLM_TIMEOUT';
}
