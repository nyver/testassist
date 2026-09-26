// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Test Assistant';

  @override
  String get actionCancel => 'Cancel';

  @override
  String get actionClose => 'Close';

  @override
  String get actionDelete => 'Delete';

  @override
  String get actionRemove => 'Remove';

  @override
  String get actionSave => 'Save';

  @override
  String get actionRetry => 'Retry';

  @override
  String get actionConfirm => 'Confirm';

  @override
  String get actionContinue => 'Continue';

  @override
  String get actionCopy => 'Copy';

  @override
  String get actionShare => 'Share';

  @override
  String get actionOpenSettings => 'Open settings';

  @override
  String get actionMore => 'More';

  @override
  String get actionChangeModel => 'Change model';

  @override
  String get actionSendTextOnly => 'Send text only';

  @override
  String get mainTakePhoto => 'Take photo';

  @override
  String get mainChooseImage => 'Choose image';

  @override
  String get mainHistory => 'History';

  @override
  String get mainSettings => 'Settings';

  @override
  String get setupTitle => 'Connect to server';

  @override
  String get setupIntro =>
      'Enter the address and token of your Test Assistant server.';

  @override
  String get setupUrlLabel => 'Server address';

  @override
  String get setupUrlHint => 'https://192.168.1.10:8447';

  @override
  String get setupNameLabel => 'Name';

  @override
  String get setupTokenLabel => 'Token';

  @override
  String get setupConnect => 'Connect';

  @override
  String get setupConnecting => 'Connecting…';

  @override
  String get setupUrlInvalid =>
      'Enter a valid address that starts with https://';

  @override
  String get setupUrlNotHttps => 'Only https:// addresses are supported.';

  @override
  String get setupNameRequired => 'Enter a name.';

  @override
  String get setupTokenRequired => 'Enter the token.';

  @override
  String get setupTokenInvalid =>
      'The token is invalid. Check it in the server output or with \"server token show\".';

  @override
  String get setupServerMismatch =>
      'A different server responded at this address.';

  @override
  String get trustDialogTitle => 'Trust this certificate?';

  @override
  String trustDialogBody(String url) {
    return 'The certificate of $url is not issued by a public authority. Compare this fingerprint with the one printed by the server (\"server certificate fingerprint\") and trust it only if they are identical.';
  }

  @override
  String get trustDialogFingerprint => 'SHA-256 fingerprint';

  @override
  String get trustActionTrust => 'Trust';

  @override
  String get serverSettingsTitle => 'Server';

  @override
  String get serverFieldName => 'Name';

  @override
  String get serverFieldUrl => 'Address';

  @override
  String get serverFieldId => 'Server ID';

  @override
  String get serverFieldFingerprint => 'Trusted certificate fingerprint';

  @override
  String get serverFingerprintNone => 'None (publicly trusted certificate)';

  @override
  String get serverEditName => 'Edit name';

  @override
  String get serverReplaceToken => 'Replace token';

  @override
  String get serverNewTokenLabel => 'New token';

  @override
  String get serverTokenReplaced => 'Token updated.';

  @override
  String get serverResetTrust => 'Reset trusted certificate';

  @override
  String get serverResetTrustConfirm =>
      'The stored fingerprint will be deleted. You will be asked to confirm the server certificate again.';

  @override
  String get serverResetTrustDone => 'Trusted certificate reset.';

  @override
  String get serverRemove => 'Remove server';

  @override
  String get serverRemoveConfirm =>
      'The server, its token and its trusted certificate will be removed from this device. History is kept.';

  @override
  String get serverMismatchBlocked =>
      'A different server responded at this address. Requests are blocked. Check the address or remove the server and set it up again.';

  @override
  String get errorNetwork =>
      'Could not connect to the server. Check the network and server address.';

  @override
  String get errorCertificateChanged =>
      'Server certificate has changed. Connection blocked.';

  @override
  String get errorCertificateChangedHint =>
      'If you changed the certificate on purpose, reset the trusted certificate in the server settings.';

  @override
  String get errorLlmTimeout => 'The model did not respond in time. Try again.';

  @override
  String get errorUnauthorized =>
      'The server rejected the token. Update the token in the server settings.';

  @override
  String get errorRateLimited =>
      'Too many requests. Wait a moment before trying again.';

  @override
  String get errorModelNoVision =>
      'The selected model does not support images. Only the recognized text will be sent.';

  @override
  String errorGeneric(String requestId) {
    return 'Something went wrong. Request ID: $requestId';
  }

  @override
  String get errorGenericNoId => 'Something went wrong. Try again.';

  @override
  String get errorModelNotFound =>
      'The selected model is not available on the server. Choose another model.';

  @override
  String get errorProviderUnavailable =>
      'The model provider is unavailable. Try again later or choose another model.';

  @override
  String get errorInvalidModelResponse =>
      'The model returned an unreadable answer. Try again or choose another model.';

  @override
  String get errorOcrFailed =>
      'Text recognition failed. You can type the question manually.';

  @override
  String get errorImageFailed =>
      'Could not process the image. Try another image.';

  @override
  String get cameraTitle => 'Take photo';

  @override
  String get cameraPermissionTitle => 'Camera access is needed';

  @override
  String get cameraPermissionDenied =>
      'The app needs the camera to photograph a question. You can also choose an existing image.';

  @override
  String get cameraPermissionPermanent =>
      'Camera access is turned off for this app. Open the app settings to allow it, or choose an image instead.';

  @override
  String get cameraUnavailable => 'The camera is not available on this device.';

  @override
  String get cameraCapture => 'Capture';

  @override
  String get cropTitle => 'Crop';

  @override
  String get cropHint => 'Drag the corners to select the question.';

  @override
  String get cropConfirm => 'Use selection';

  @override
  String get cropWholeImage => 'Whole image';

  @override
  String get cropProcessing => 'Preparing image…';

  @override
  String get recognitionTitle => 'Question';

  @override
  String get recognitionOcrRunning => 'Recognizing text…';

  @override
  String get recognitionRawText => 'Recognized text';

  @override
  String get recognitionReparse => 'Parse again';

  @override
  String get recognitionQuestion => 'Question';

  @override
  String get recognitionOptions => 'Options';

  @override
  String get recognitionOptionId => 'ID';

  @override
  String get recognitionOptionText => 'Option text';

  @override
  String get recognitionAddOption => 'Add option';

  @override
  String get recognitionRemoveOption => 'Remove option';

  @override
  String get recognitionMoveUp => 'Move up';

  @override
  String get recognitionMoveDown => 'Move down';

  @override
  String get recognitionDuplicateId => 'Duplicate option ID';

  @override
  String get recognitionEmptyId => 'Enter an ID';

  @override
  String get recognitionLowQuality =>
      'Could not reliably recognize the question. Try taking the photo again, or turn on \"Send image to model\" so the model reads it from the picture.';

  @override
  String get recognitionImageOnlyHint =>
      'The text is incomplete, so the model will read the question from the image.';

  @override
  String get questionFromImage => 'Question from the image';

  @override
  String get recognitionSendImage => 'Send image to model';

  @override
  String get recognitionSendImageUnavailable =>
      'The selected model does not support images.';

  @override
  String get recognitionGetAnswer => 'Get answer';

  @override
  String get recognitionAnalyzing => 'Asking the model…';

  @override
  String get recognitionCancelRequest => 'Cancel request';

  @override
  String get recognitionRequestCancelled => 'Request cancelled.';

  @override
  String get modelProvider => 'Provider';

  @override
  String get modelModel => 'Model';

  @override
  String get modelVisionBadge => 'Images';

  @override
  String get modelTextOnlyBadge => 'Text only';

  @override
  String get modelLoading => 'Loading models…';

  @override
  String get modelLoadFailed => 'Could not load the model list.';

  @override
  String get modelSearch => 'Search models';

  @override
  String get modelPickerTitle => 'Choose model';

  @override
  String get modelNoneAvailable => 'No models available.';

  @override
  String get resultTitle => 'Answer';

  @override
  String get resultOptions => 'Answer options';

  @override
  String get resultCorrectOptions => 'Correct answer';

  @override
  String get resultExplanation => 'Explanation';

  @override
  String get resultDetails => 'Details';

  @override
  String get resultWarnings => 'Warnings';

  @override
  String resultConfidence(String level) {
    return 'Confidence: $level';
  }

  @override
  String get confidenceHigh => 'High';

  @override
  String get confidenceMedium => 'Medium';

  @override
  String get confidenceLow => 'Low';

  @override
  String get resultUncertain => 'No reliable answer was found.';

  @override
  String get resultCopied => 'Copied to clipboard.';

  @override
  String get resultDeleteConfirm => 'Delete this entry from history?';

  @override
  String resultProviderModel(String provider, String model) {
    return '$provider · $model';
  }

  @override
  String get resultShareQuestion => 'Question';

  @override
  String get resultShareAnswer => 'Answer';

  @override
  String get resultShareExplanation => 'Explanation';

  @override
  String get resultImageMissing => 'The image is no longer available.';

  @override
  String get resultDeleteFromHistory => 'Delete from history';

  @override
  String get historyTitle => 'History';

  @override
  String get historyEmpty => 'No questions yet.';

  @override
  String get historyClearAll => 'Clear history';

  @override
  String get historyClearConfirm =>
      'Delete all history entries and their images?';

  @override
  String get historyDeleteConfirm => 'Delete this entry and its image?';

  @override
  String get historyNoAnswer => 'No reliable answer';

  @override
  String get settingsTitle => 'Settings';

  @override
  String get settingsAnswerMode => 'Answer';

  @override
  String get settingsModeOptionOnly => 'Correct option only';

  @override
  String get settingsModeShort => 'Answer + short explanation';

  @override
  String get settingsModeDetailed => 'Detailed explanation';

  @override
  String get settingsDeleteImages => 'Delete images after analysis';

  @override
  String get settingsDeleteImagesHint =>
      'Keeps the text of each answer but removes the photo once the answer is saved.';

  @override
  String get settingsServer => 'Server';

  @override
  String get settingsLanguageNote =>
      'The explanation language follows the app language.';
}
