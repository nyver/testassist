import '../core/errors/app_failure.dart';
import '../l10n/generated/app_localizations.dart';

/// The localized, actionable message for a failure. Raw exception text is
/// never shown to the user.
String failureMessage(AppLocalizations l10n, AppFailure failure) {
  switch (failure) {
    case NetworkFailure():
      return l10n.errorNetwork;
    case CertificateChangedFailure():
      return l10n.errorCertificateChanged;
    case ServerMismatchFailure():
      return l10n.serverMismatchBlocked;
    case CancelledFailure():
      return l10n.recognitionRequestCancelled;
    case UnexpectedFailure():
      return l10n.errorGenericNoId;
    case ApiFailure():
      return _apiMessage(l10n, failure);
  }
}

String _apiMessage(AppLocalizations l10n, ApiFailure failure) {
  switch (failure.code) {
    case ApiErrorCodes.unauthorized:
      return l10n.errorUnauthorized;
    case ApiErrorCodes.rateLimited:
      return l10n.errorRateLimited;
    case ApiErrorCodes.llmTimeout:
      return l10n.errorLlmTimeout;
    case ApiErrorCodes.modelNoVision:
      return l10n.errorModelNoVision;
    case ApiErrorCodes.modelNotFound:
    case ApiErrorCodes.providerNotFound:
      return l10n.errorModelNotFound;
    case ApiErrorCodes.llmProviderUnavailable:
      return l10n.errorProviderUnavailable;
    case ApiErrorCodes.llmInvalidResponse:
      return l10n.errorInvalidModelResponse;
    default:
      final id = failure.requestId;
      return id == null ? l10n.errorGenericNoId : l10n.errorGeneric(id);
  }
}

/// Extra advice shown below a message, or null.
String? failureHint(AppLocalizations l10n, AppFailure failure) {
  if (failure is CertificateChangedFailure) {
    return l10n.errorCertificateChangedHint;
  }
  return null;
}

/// Whether trying the same action again can help.
bool failureIsRetryable(AppFailure failure) {
  switch (failure) {
    case NetworkFailure():
    case UnexpectedFailure():
      return true;
    case CertificateChangedFailure():
    case ServerMismatchFailure():
    case CancelledFailure():
      return false;
    case ApiFailure():
      return const {
        ApiErrorCodes.llmTimeout,
        ApiErrorCodes.rateLimited,
        ApiErrorCodes.llmProviderUnavailable,
        ApiErrorCodes.llmInvalidResponse,
        ApiErrorCodes.internalError,
      }.contains(failure.code);
  }
}
