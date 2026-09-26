// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Russian (`ru`).
class AppLocalizationsRu extends AppLocalizations {
  AppLocalizationsRu([String locale = 'ru']) : super(locale);

  @override
  String get appTitle => 'Помощник по тестам';

  @override
  String get actionCancel => 'Отмена';

  @override
  String get actionClose => 'Закрыть';

  @override
  String get actionDelete => 'Удалить';

  @override
  String get actionRemove => 'Убрать';

  @override
  String get actionSave => 'Сохранить';

  @override
  String get actionRetry => 'Повторить';

  @override
  String get actionConfirm => 'Подтвердить';

  @override
  String get actionContinue => 'Продолжить';

  @override
  String get actionCopy => 'Копировать';

  @override
  String get actionShare => 'Поделиться';

  @override
  String get actionOpenSettings => 'Открыть настройки';

  @override
  String get actionMore => 'Подробнее';

  @override
  String get actionChangeModel => 'Сменить модель';

  @override
  String get actionSendTextOnly => 'Отправить только текст';

  @override
  String get mainTakePhoto => 'Сфотографировать';

  @override
  String get mainChooseImage => 'Выбрать изображение';

  @override
  String get mainHistory => 'История';

  @override
  String get mainSettings => 'Настройки';

  @override
  String get setupTitle => 'Подключение к серверу';

  @override
  String get setupIntro =>
      'Введите адрес и токен вашего сервера Test Assistant.';

  @override
  String get setupUrlLabel => 'Адрес сервера';

  @override
  String get setupUrlHint => 'https://192.168.1.10:8447';

  @override
  String get setupNameLabel => 'Название';

  @override
  String get setupTokenLabel => 'Токен';

  @override
  String get setupConnect => 'Подключиться';

  @override
  String get setupConnecting => 'Подключение…';

  @override
  String get setupUrlInvalid =>
      'Введите корректный адрес, начинающийся с https://';

  @override
  String get setupUrlNotHttps => 'Поддерживаются только адреса https://.';

  @override
  String get setupNameRequired => 'Введите название.';

  @override
  String get setupTokenRequired => 'Введите токен.';

  @override
  String get setupTokenInvalid =>
      'Токен недействителен. Проверьте его в выводе сервера или командой \"server token show\".';

  @override
  String get setupServerMismatch => 'По этому адресу ответил другой сервер.';

  @override
  String get trustDialogTitle => 'Доверять этому сертификату?';

  @override
  String trustDialogBody(String url) {
    return 'Сертификат сервера $url выдан не публичным центром сертификации. Сравните отпечаток с тем, который выводит сервер (\"server certificate fingerprint\"), и доверяйте, только если они совпадают.';
  }

  @override
  String get trustDialogFingerprint => 'Отпечаток SHA-256';

  @override
  String get trustActionTrust => 'Доверять';

  @override
  String get serverSettingsTitle => 'Сервер';

  @override
  String get serverFieldName => 'Название';

  @override
  String get serverFieldUrl => 'Адрес';

  @override
  String get serverFieldId => 'ID сервера';

  @override
  String get serverFieldFingerprint => 'Отпечаток доверенного сертификата';

  @override
  String get serverFingerprintNone => 'Нет (сертификат публичного центра)';

  @override
  String get serverEditName => 'Изменить название';

  @override
  String get serverReplaceToken => 'Заменить токен';

  @override
  String get serverNewTokenLabel => 'Новый токен';

  @override
  String get serverTokenReplaced => 'Токен обновлён.';

  @override
  String get serverResetTrust => 'Сбросить доверенный сертификат';

  @override
  String get serverResetTrustConfirm =>
      'Сохранённый отпечаток будет удалён. Сертификат сервера нужно будет подтвердить заново.';

  @override
  String get serverResetTrustDone => 'Доверенный сертификат сброшен.';

  @override
  String get serverRemove => 'Удалить сервер';

  @override
  String get serverRemoveConfirm =>
      'Сервер, его токен и доверенный сертификат будут удалены с этого устройства. История сохранится.';

  @override
  String get serverMismatchBlocked =>
      'По этому адресу ответил другой сервер. Запросы заблокированы. Проверьте адрес или удалите сервер и настройте его заново.';

  @override
  String get errorNetwork =>
      'Не удалось подключиться к серверу. Проверьте сеть и адрес сервера.';

  @override
  String get errorCertificateChanged =>
      'Сертификат сервера изменился. Соединение заблокировано.';

  @override
  String get errorCertificateChangedHint =>
      'Если вы намеренно сменили сертификат, сбросьте доверенный сертификат в настройках сервера.';

  @override
  String get errorLlmTimeout =>
      'Модель не ответила вовремя. Попробуйте ещё раз.';

  @override
  String get errorUnauthorized =>
      'Сервер отклонил токен. Обновите токен в настройках сервера.';

  @override
  String get errorRateLimited =>
      'Слишком много запросов. Подождите немного и повторите.';

  @override
  String get errorModelNoVision =>
      'Выбранная модель не поддерживает изображения. Будет отправлен только распознанный текст.';

  @override
  String errorGeneric(String requestId) {
    return 'Что-то пошло не так. ID запроса: $requestId';
  }

  @override
  String get errorGenericNoId => 'Что-то пошло не так. Попробуйте ещё раз.';

  @override
  String get errorModelNotFound =>
      'Выбранная модель недоступна на сервере. Выберите другую модель.';

  @override
  String get errorProviderUnavailable =>
      'Провайдер модели недоступен. Попробуйте позже или выберите другую модель.';

  @override
  String get errorInvalidModelResponse =>
      'Модель вернула нечитаемый ответ. Повторите запрос или выберите другую модель.';

  @override
  String get errorOcrFailed =>
      'Не удалось распознать текст. Вы можете ввести вопрос вручную.';

  @override
  String get errorImageFailed =>
      'Не удалось обработать изображение. Попробуйте другое.';

  @override
  String get cameraTitle => 'Фото';

  @override
  String get cameraPermissionTitle => 'Нужен доступ к камере';

  @override
  String get cameraPermissionDenied =>
      'Приложению нужна камера, чтобы сфотографировать вопрос. Можно также выбрать готовое изображение.';

  @override
  String get cameraPermissionPermanent =>
      'Доступ к камере для приложения отключён. Откройте настройки приложения, чтобы разрешить его, или выберите изображение.';

  @override
  String get cameraUnavailable => 'Камера на этом устройстве недоступна.';

  @override
  String get cameraCapture => 'Снять';

  @override
  String get cropTitle => 'Обрезка';

  @override
  String get cropHint => 'Потяните за углы, чтобы выделить вопрос.';

  @override
  String get cropConfirm => 'Использовать выделение';

  @override
  String get cropWholeImage => 'Всё изображение';

  @override
  String get cropProcessing => 'Подготовка изображения…';

  @override
  String get recognitionTitle => 'Вопрос';

  @override
  String get recognitionOcrRunning => 'Распознавание текста…';

  @override
  String get recognitionRawText => 'Распознанный текст';

  @override
  String get recognitionReparse => 'Разобрать заново';

  @override
  String get recognitionQuestion => 'Вопрос';

  @override
  String get recognitionOptions => 'Варианты ответа';

  @override
  String get recognitionOptionId => 'ID';

  @override
  String get recognitionOptionText => 'Текст варианта';

  @override
  String get recognitionAddOption => 'Добавить вариант';

  @override
  String get recognitionRemoveOption => 'Удалить вариант';

  @override
  String get recognitionMoveUp => 'Выше';

  @override
  String get recognitionMoveDown => 'Ниже';

  @override
  String get recognitionDuplicateId => 'ID варианта повторяется';

  @override
  String get recognitionEmptyId => 'Введите ID';

  @override
  String get recognitionLowQuality =>
      'Не удалось надёжно распознать вопрос. Попробуйте сфотографировать ещё раз или включите «Отправить изображение модели»: модель прочитает вопрос с картинки.';

  @override
  String get recognitionImageOnlyHint =>
      'Текст неполный, поэтому модель прочитает вопрос с изображения.';

  @override
  String get questionFromImage => 'Вопрос с изображения';

  @override
  String get recognitionSendImage => 'Отправить изображение модели';

  @override
  String get recognitionSendImageUnavailable =>
      'Выбранная модель не поддерживает изображения.';

  @override
  String get recognitionGetAnswer => 'Получить ответ';

  @override
  String get recognitionAnalyzing => 'Запрос к модели…';

  @override
  String get recognitionCancelRequest => 'Отменить запрос';

  @override
  String get recognitionRequestCancelled => 'Запрос отменён.';

  @override
  String get modelProvider => 'Провайдер';

  @override
  String get modelModel => 'Модель';

  @override
  String get modelVisionBadge => 'Изображения';

  @override
  String get modelTextOnlyBadge => 'Только текст';

  @override
  String get modelLoading => 'Загрузка моделей…';

  @override
  String get modelLoadFailed => 'Не удалось загрузить список моделей.';

  @override
  String get modelSearch => 'Поиск моделей';

  @override
  String get modelPickerTitle => 'Выбор модели';

  @override
  String get modelNoneAvailable => 'Нет доступных моделей.';

  @override
  String get resultTitle => 'Ответ';

  @override
  String get resultCorrectOptions => 'Правильный ответ';

  @override
  String get resultExplanation => 'Пояснение';

  @override
  String get resultDetails => 'Подробности';

  @override
  String get resultWarnings => 'Предупреждения';

  @override
  String resultConfidence(String level) {
    return 'Уверенность: $level';
  }

  @override
  String get confidenceHigh => 'Высокая';

  @override
  String get confidenceMedium => 'Средняя';

  @override
  String get confidenceLow => 'Низкая';

  @override
  String get resultUncertain => 'Надёжный ответ не найден.';

  @override
  String get resultCopied => 'Скопировано в буфер обмена.';

  @override
  String get resultDeleteConfirm => 'Удалить эту запись из истории?';

  @override
  String resultProviderModel(String provider, String model) {
    return '$provider · $model';
  }

  @override
  String get resultShareQuestion => 'Вопрос';

  @override
  String get resultShareAnswer => 'Ответ';

  @override
  String get resultShareExplanation => 'Пояснение';

  @override
  String get resultImageMissing => 'Изображение больше недоступно.';

  @override
  String get resultDeleteFromHistory => 'Удалить из истории';

  @override
  String get historyTitle => 'История';

  @override
  String get historyEmpty => 'Вопросов пока нет.';

  @override
  String get historyClearAll => 'Очистить историю';

  @override
  String get historyClearConfirm =>
      'Удалить все записи истории и их изображения?';

  @override
  String get historyDeleteConfirm => 'Удалить эту запись и её изображение?';

  @override
  String get historyNoAnswer => 'Надёжного ответа нет';

  @override
  String get settingsTitle => 'Настройки';

  @override
  String get settingsAnswerMode => 'Ответ';

  @override
  String get settingsModeOptionOnly => 'Только правильный вариант';

  @override
  String get settingsModeShort => 'Ответ + краткое пояснение';

  @override
  String get settingsModeDetailed => 'Подробное пояснение';

  @override
  String get settingsDeleteImages => 'Удалять изображения после анализа';

  @override
  String get settingsDeleteImagesHint =>
      'Текст каждого ответа сохраняется, а фото удаляется после сохранения ответа.';

  @override
  String get settingsServer => 'Сервер';

  @override
  String get settingsLanguageNote =>
      'Язык пояснений совпадает с языком приложения.';
}
