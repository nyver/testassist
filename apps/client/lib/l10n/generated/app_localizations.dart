import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_ru.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'generated/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('ru'),
  ];

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'Test Assistant'**
  String get appTitle;

  /// No description provided for @actionCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get actionCancel;

  /// No description provided for @actionClose.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get actionClose;

  /// No description provided for @actionDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get actionDelete;

  /// No description provided for @actionRemove.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get actionRemove;

  /// No description provided for @actionSave.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get actionSave;

  /// No description provided for @actionRetry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get actionRetry;

  /// No description provided for @actionConfirm.
  ///
  /// In en, this message translates to:
  /// **'Confirm'**
  String get actionConfirm;

  /// No description provided for @actionContinue.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get actionContinue;

  /// No description provided for @actionCopy.
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get actionCopy;

  /// No description provided for @actionShare.
  ///
  /// In en, this message translates to:
  /// **'Share'**
  String get actionShare;

  /// No description provided for @actionOpenSettings.
  ///
  /// In en, this message translates to:
  /// **'Open settings'**
  String get actionOpenSettings;

  /// No description provided for @actionMore.
  ///
  /// In en, this message translates to:
  /// **'More'**
  String get actionMore;

  /// No description provided for @actionChangeModel.
  ///
  /// In en, this message translates to:
  /// **'Change model'**
  String get actionChangeModel;

  /// No description provided for @actionSendTextOnly.
  ///
  /// In en, this message translates to:
  /// **'Send text only'**
  String get actionSendTextOnly;

  /// No description provided for @mainTakePhoto.
  ///
  /// In en, this message translates to:
  /// **'Take photo'**
  String get mainTakePhoto;

  /// No description provided for @mainChooseImage.
  ///
  /// In en, this message translates to:
  /// **'Choose image'**
  String get mainChooseImage;

  /// No description provided for @mainHistory.
  ///
  /// In en, this message translates to:
  /// **'History'**
  String get mainHistory;

  /// No description provided for @mainSettings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get mainSettings;

  /// No description provided for @setupTitle.
  ///
  /// In en, this message translates to:
  /// **'Connect to server'**
  String get setupTitle;

  /// No description provided for @setupIntro.
  ///
  /// In en, this message translates to:
  /// **'Enter the address and token of your Test Assistant server.'**
  String get setupIntro;

  /// No description provided for @setupUrlLabel.
  ///
  /// In en, this message translates to:
  /// **'Server address'**
  String get setupUrlLabel;

  /// No description provided for @setupUrlHint.
  ///
  /// In en, this message translates to:
  /// **'https://192.168.1.10:8447'**
  String get setupUrlHint;

  /// No description provided for @setupNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get setupNameLabel;

  /// No description provided for @setupTokenLabel.
  ///
  /// In en, this message translates to:
  /// **'Token'**
  String get setupTokenLabel;

  /// No description provided for @setupConnect.
  ///
  /// In en, this message translates to:
  /// **'Connect'**
  String get setupConnect;

  /// No description provided for @setupConnecting.
  ///
  /// In en, this message translates to:
  /// **'Connecting…'**
  String get setupConnecting;

  /// No description provided for @setupUrlInvalid.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid address that starts with https://'**
  String get setupUrlInvalid;

  /// No description provided for @setupUrlNotHttps.
  ///
  /// In en, this message translates to:
  /// **'Only https:// addresses are supported.'**
  String get setupUrlNotHttps;

  /// No description provided for @setupNameRequired.
  ///
  /// In en, this message translates to:
  /// **'Enter a name.'**
  String get setupNameRequired;

  /// No description provided for @setupTokenRequired.
  ///
  /// In en, this message translates to:
  /// **'Enter the token.'**
  String get setupTokenRequired;

  /// No description provided for @setupTokenInvalid.
  ///
  /// In en, this message translates to:
  /// **'The token is invalid. Check it in the server output or with \"server token show\".'**
  String get setupTokenInvalid;

  /// No description provided for @setupServerMismatch.
  ///
  /// In en, this message translates to:
  /// **'A different server responded at this address.'**
  String get setupServerMismatch;

  /// No description provided for @trustDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Trust this certificate?'**
  String get trustDialogTitle;

  /// No description provided for @trustDialogBody.
  ///
  /// In en, this message translates to:
  /// **'The certificate of {url} is not issued by a public authority. Compare this fingerprint with the one printed by the server (\"server certificate fingerprint\") and trust it only if they are identical.'**
  String trustDialogBody(String url);

  /// No description provided for @trustDialogFingerprint.
  ///
  /// In en, this message translates to:
  /// **'SHA-256 fingerprint'**
  String get trustDialogFingerprint;

  /// No description provided for @trustActionTrust.
  ///
  /// In en, this message translates to:
  /// **'Trust'**
  String get trustActionTrust;

  /// No description provided for @serverSettingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Server'**
  String get serverSettingsTitle;

  /// No description provided for @serverFieldName.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get serverFieldName;

  /// No description provided for @serverFieldUrl.
  ///
  /// In en, this message translates to:
  /// **'Address'**
  String get serverFieldUrl;

  /// No description provided for @serverFieldId.
  ///
  /// In en, this message translates to:
  /// **'Server ID'**
  String get serverFieldId;

  /// No description provided for @serverFieldFingerprint.
  ///
  /// In en, this message translates to:
  /// **'Trusted certificate fingerprint'**
  String get serverFieldFingerprint;

  /// No description provided for @serverFingerprintNone.
  ///
  /// In en, this message translates to:
  /// **'None (publicly trusted certificate)'**
  String get serverFingerprintNone;

  /// No description provided for @serverEditName.
  ///
  /// In en, this message translates to:
  /// **'Edit name'**
  String get serverEditName;

  /// No description provided for @serverReplaceToken.
  ///
  /// In en, this message translates to:
  /// **'Replace token'**
  String get serverReplaceToken;

  /// No description provided for @serverNewTokenLabel.
  ///
  /// In en, this message translates to:
  /// **'New token'**
  String get serverNewTokenLabel;

  /// No description provided for @serverTokenReplaced.
  ///
  /// In en, this message translates to:
  /// **'Token updated.'**
  String get serverTokenReplaced;

  /// No description provided for @serverResetTrust.
  ///
  /// In en, this message translates to:
  /// **'Reset trusted certificate'**
  String get serverResetTrust;

  /// No description provided for @serverResetTrustConfirm.
  ///
  /// In en, this message translates to:
  /// **'The stored fingerprint will be deleted. You will be asked to confirm the server certificate again.'**
  String get serverResetTrustConfirm;

  /// No description provided for @serverResetTrustDone.
  ///
  /// In en, this message translates to:
  /// **'Trusted certificate reset.'**
  String get serverResetTrustDone;

  /// No description provided for @serverRemove.
  ///
  /// In en, this message translates to:
  /// **'Remove server'**
  String get serverRemove;

  /// No description provided for @serverRemoveConfirm.
  ///
  /// In en, this message translates to:
  /// **'The server, its token and its trusted certificate will be removed from this device. History is kept.'**
  String get serverRemoveConfirm;

  /// No description provided for @serverMismatchBlocked.
  ///
  /// In en, this message translates to:
  /// **'A different server responded at this address. Requests are blocked. Check the address or remove the server and set it up again.'**
  String get serverMismatchBlocked;

  /// No description provided for @errorNetwork.
  ///
  /// In en, this message translates to:
  /// **'Could not connect to the server. Check the network and server address.'**
  String get errorNetwork;

  /// No description provided for @errorCertificateChanged.
  ///
  /// In en, this message translates to:
  /// **'Server certificate has changed. Connection blocked.'**
  String get errorCertificateChanged;

  /// No description provided for @errorCertificateChangedHint.
  ///
  /// In en, this message translates to:
  /// **'If you changed the certificate on purpose, reset the trusted certificate in the server settings.'**
  String get errorCertificateChangedHint;

  /// No description provided for @errorLlmTimeout.
  ///
  /// In en, this message translates to:
  /// **'The model did not respond in time. Try again.'**
  String get errorLlmTimeout;

  /// No description provided for @errorUnauthorized.
  ///
  /// In en, this message translates to:
  /// **'The server rejected the token. Update the token in the server settings.'**
  String get errorUnauthorized;

  /// No description provided for @errorRateLimited.
  ///
  /// In en, this message translates to:
  /// **'Too many requests. Wait a moment before trying again.'**
  String get errorRateLimited;

  /// No description provided for @errorModelNoVision.
  ///
  /// In en, this message translates to:
  /// **'The selected model does not support images. Only the recognized text will be sent.'**
  String get errorModelNoVision;

  /// No description provided for @errorGeneric.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong. Request ID: {requestId}'**
  String errorGeneric(String requestId);

  /// No description provided for @errorGenericNoId.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong. Try again.'**
  String get errorGenericNoId;

  /// No description provided for @errorModelNotFound.
  ///
  /// In en, this message translates to:
  /// **'The selected model is not available on the server. Choose another model.'**
  String get errorModelNotFound;

  /// No description provided for @errorProviderUnavailable.
  ///
  /// In en, this message translates to:
  /// **'The model provider is unavailable. Try again later or choose another model.'**
  String get errorProviderUnavailable;

  /// No description provided for @errorInvalidModelResponse.
  ///
  /// In en, this message translates to:
  /// **'The model returned an unreadable answer. Try again or choose another model.'**
  String get errorInvalidModelResponse;

  /// No description provided for @errorOcrFailed.
  ///
  /// In en, this message translates to:
  /// **'Text recognition failed. You can type the question manually.'**
  String get errorOcrFailed;

  /// No description provided for @errorImageFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not process the image. Try another image.'**
  String get errorImageFailed;

  /// No description provided for @cameraTitle.
  ///
  /// In en, this message translates to:
  /// **'Take photo'**
  String get cameraTitle;

  /// No description provided for @cameraPermissionTitle.
  ///
  /// In en, this message translates to:
  /// **'Camera access is needed'**
  String get cameraPermissionTitle;

  /// No description provided for @cameraPermissionDenied.
  ///
  /// In en, this message translates to:
  /// **'The app needs the camera to photograph a question. You can also choose an existing image.'**
  String get cameraPermissionDenied;

  /// No description provided for @cameraPermissionPermanent.
  ///
  /// In en, this message translates to:
  /// **'Camera access is turned off for this app. Open the app settings to allow it, or choose an image instead.'**
  String get cameraPermissionPermanent;

  /// No description provided for @cameraUnavailable.
  ///
  /// In en, this message translates to:
  /// **'The camera is not available on this device.'**
  String get cameraUnavailable;

  /// No description provided for @cameraCapture.
  ///
  /// In en, this message translates to:
  /// **'Capture'**
  String get cameraCapture;

  /// No description provided for @cropTitle.
  ///
  /// In en, this message translates to:
  /// **'Crop'**
  String get cropTitle;

  /// No description provided for @cropHint.
  ///
  /// In en, this message translates to:
  /// **'Drag the corners to select the question.'**
  String get cropHint;

  /// No description provided for @cropConfirm.
  ///
  /// In en, this message translates to:
  /// **'Use selection'**
  String get cropConfirm;

  /// No description provided for @cropWholeImage.
  ///
  /// In en, this message translates to:
  /// **'Whole image'**
  String get cropWholeImage;

  /// No description provided for @cropProcessing.
  ///
  /// In en, this message translates to:
  /// **'Preparing image…'**
  String get cropProcessing;

  /// No description provided for @recognitionTitle.
  ///
  /// In en, this message translates to:
  /// **'Question'**
  String get recognitionTitle;

  /// No description provided for @recognitionOcrRunning.
  ///
  /// In en, this message translates to:
  /// **'Recognizing text…'**
  String get recognitionOcrRunning;

  /// No description provided for @recognitionRawText.
  ///
  /// In en, this message translates to:
  /// **'Recognized text'**
  String get recognitionRawText;

  /// No description provided for @recognitionReparse.
  ///
  /// In en, this message translates to:
  /// **'Parse again'**
  String get recognitionReparse;

  /// No description provided for @recognitionQuestion.
  ///
  /// In en, this message translates to:
  /// **'Question'**
  String get recognitionQuestion;

  /// No description provided for @recognitionOptions.
  ///
  /// In en, this message translates to:
  /// **'Options'**
  String get recognitionOptions;

  /// No description provided for @recognitionOptionId.
  ///
  /// In en, this message translates to:
  /// **'ID'**
  String get recognitionOptionId;

  /// No description provided for @recognitionOptionText.
  ///
  /// In en, this message translates to:
  /// **'Option text'**
  String get recognitionOptionText;

  /// No description provided for @recognitionAddOption.
  ///
  /// In en, this message translates to:
  /// **'Add option'**
  String get recognitionAddOption;

  /// No description provided for @recognitionRemoveOption.
  ///
  /// In en, this message translates to:
  /// **'Remove option'**
  String get recognitionRemoveOption;

  /// No description provided for @recognitionMoveUp.
  ///
  /// In en, this message translates to:
  /// **'Move up'**
  String get recognitionMoveUp;

  /// No description provided for @recognitionMoveDown.
  ///
  /// In en, this message translates to:
  /// **'Move down'**
  String get recognitionMoveDown;

  /// No description provided for @recognitionDuplicateId.
  ///
  /// In en, this message translates to:
  /// **'Duplicate option ID'**
  String get recognitionDuplicateId;

  /// No description provided for @recognitionEmptyId.
  ///
  /// In en, this message translates to:
  /// **'Enter an ID'**
  String get recognitionEmptyId;

  /// No description provided for @recognitionLowQuality.
  ///
  /// In en, this message translates to:
  /// **'Could not reliably recognize the question. Try taking the photo again.'**
  String get recognitionLowQuality;

  /// No description provided for @recognitionSendImage.
  ///
  /// In en, this message translates to:
  /// **'Send image to model'**
  String get recognitionSendImage;

  /// No description provided for @recognitionSendImageUnavailable.
  ///
  /// In en, this message translates to:
  /// **'The selected model does not support images.'**
  String get recognitionSendImageUnavailable;

  /// No description provided for @recognitionGetAnswer.
  ///
  /// In en, this message translates to:
  /// **'Get answer'**
  String get recognitionGetAnswer;

  /// No description provided for @recognitionAnalyzing.
  ///
  /// In en, this message translates to:
  /// **'Asking the model…'**
  String get recognitionAnalyzing;

  /// No description provided for @recognitionCancelRequest.
  ///
  /// In en, this message translates to:
  /// **'Cancel request'**
  String get recognitionCancelRequest;

  /// No description provided for @recognitionRequestCancelled.
  ///
  /// In en, this message translates to:
  /// **'Request cancelled.'**
  String get recognitionRequestCancelled;

  /// No description provided for @modelProvider.
  ///
  /// In en, this message translates to:
  /// **'Provider'**
  String get modelProvider;

  /// No description provided for @modelModel.
  ///
  /// In en, this message translates to:
  /// **'Model'**
  String get modelModel;

  /// No description provided for @modelVisionBadge.
  ///
  /// In en, this message translates to:
  /// **'Images'**
  String get modelVisionBadge;

  /// No description provided for @modelTextOnlyBadge.
  ///
  /// In en, this message translates to:
  /// **'Text only'**
  String get modelTextOnlyBadge;

  /// No description provided for @modelLoading.
  ///
  /// In en, this message translates to:
  /// **'Loading models…'**
  String get modelLoading;

  /// No description provided for @modelLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not load the model list.'**
  String get modelLoadFailed;

  /// No description provided for @modelSearch.
  ///
  /// In en, this message translates to:
  /// **'Search models'**
  String get modelSearch;

  /// No description provided for @modelPickerTitle.
  ///
  /// In en, this message translates to:
  /// **'Choose model'**
  String get modelPickerTitle;

  /// No description provided for @modelNoneAvailable.
  ///
  /// In en, this message translates to:
  /// **'No models available.'**
  String get modelNoneAvailable;

  /// No description provided for @resultTitle.
  ///
  /// In en, this message translates to:
  /// **'Answer'**
  String get resultTitle;

  /// No description provided for @resultCorrectOptions.
  ///
  /// In en, this message translates to:
  /// **'Correct answer'**
  String get resultCorrectOptions;

  /// No description provided for @resultExplanation.
  ///
  /// In en, this message translates to:
  /// **'Explanation'**
  String get resultExplanation;

  /// No description provided for @resultDetails.
  ///
  /// In en, this message translates to:
  /// **'Details'**
  String get resultDetails;

  /// No description provided for @resultWarnings.
  ///
  /// In en, this message translates to:
  /// **'Warnings'**
  String get resultWarnings;

  /// No description provided for @resultConfidence.
  ///
  /// In en, this message translates to:
  /// **'Confidence: {level}'**
  String resultConfidence(String level);

  /// No description provided for @confidenceHigh.
  ///
  /// In en, this message translates to:
  /// **'High'**
  String get confidenceHigh;

  /// No description provided for @confidenceMedium.
  ///
  /// In en, this message translates to:
  /// **'Medium'**
  String get confidenceMedium;

  /// No description provided for @confidenceLow.
  ///
  /// In en, this message translates to:
  /// **'Low'**
  String get confidenceLow;

  /// No description provided for @resultUncertain.
  ///
  /// In en, this message translates to:
  /// **'No reliable answer was found.'**
  String get resultUncertain;

  /// No description provided for @resultCopied.
  ///
  /// In en, this message translates to:
  /// **'Copied to clipboard.'**
  String get resultCopied;

  /// No description provided for @resultDeleteConfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete this entry from history?'**
  String get resultDeleteConfirm;

  /// No description provided for @resultProviderModel.
  ///
  /// In en, this message translates to:
  /// **'{provider} · {model}'**
  String resultProviderModel(String provider, String model);

  /// No description provided for @resultShareQuestion.
  ///
  /// In en, this message translates to:
  /// **'Question'**
  String get resultShareQuestion;

  /// No description provided for @resultShareAnswer.
  ///
  /// In en, this message translates to:
  /// **'Answer'**
  String get resultShareAnswer;

  /// No description provided for @resultShareExplanation.
  ///
  /// In en, this message translates to:
  /// **'Explanation'**
  String get resultShareExplanation;

  /// No description provided for @resultImageMissing.
  ///
  /// In en, this message translates to:
  /// **'The image is no longer available.'**
  String get resultImageMissing;

  /// No description provided for @resultDeleteFromHistory.
  ///
  /// In en, this message translates to:
  /// **'Delete from history'**
  String get resultDeleteFromHistory;

  /// No description provided for @historyTitle.
  ///
  /// In en, this message translates to:
  /// **'History'**
  String get historyTitle;

  /// No description provided for @historyEmpty.
  ///
  /// In en, this message translates to:
  /// **'No questions yet.'**
  String get historyEmpty;

  /// No description provided for @historyClearAll.
  ///
  /// In en, this message translates to:
  /// **'Clear history'**
  String get historyClearAll;

  /// No description provided for @historyClearConfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete all history entries and their images?'**
  String get historyClearConfirm;

  /// No description provided for @historyDeleteConfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete this entry and its image?'**
  String get historyDeleteConfirm;

  /// No description provided for @historyNoAnswer.
  ///
  /// In en, this message translates to:
  /// **'No reliable answer'**
  String get historyNoAnswer;

  /// No description provided for @settingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTitle;

  /// No description provided for @settingsAnswerMode.
  ///
  /// In en, this message translates to:
  /// **'Answer'**
  String get settingsAnswerMode;

  /// No description provided for @settingsModeOptionOnly.
  ///
  /// In en, this message translates to:
  /// **'Correct option only'**
  String get settingsModeOptionOnly;

  /// No description provided for @settingsModeShort.
  ///
  /// In en, this message translates to:
  /// **'Answer + short explanation'**
  String get settingsModeShort;

  /// No description provided for @settingsModeDetailed.
  ///
  /// In en, this message translates to:
  /// **'Detailed explanation'**
  String get settingsModeDetailed;

  /// No description provided for @settingsDeleteImages.
  ///
  /// In en, this message translates to:
  /// **'Delete images after analysis'**
  String get settingsDeleteImages;

  /// No description provided for @settingsDeleteImagesHint.
  ///
  /// In en, this message translates to:
  /// **'Keeps the text of each answer but removes the photo once the answer is saved.'**
  String get settingsDeleteImagesHint;

  /// No description provided for @settingsServer.
  ///
  /// In en, this message translates to:
  /// **'Server'**
  String get settingsServer;

  /// No description provided for @settingsLanguageNote.
  ///
  /// In en, this message translates to:
  /// **'The explanation language follows the app language.'**
  String get settingsLanguageNote;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'ru'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'ru':
      return AppLocalizationsRu();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
