import 'package:shared_preferences/shared_preferences.dart';

import '../domain/app_settings.dart';

export '../domain/app_settings.dart';

/// Preferences on `shared_preferences`: they are neither secrets nor relational
/// data.
class SettingsRepository {
  SettingsRepository(this._prefs);

  final SharedPreferences _prefs;

  static const displayModeKey = 'settings.v1.display_mode';
  static const deleteImagesKey = 'settings.v1.delete_images_after_analysis';
  static const lastProviderKey = 'settings.v1.last_provider';
  static const lastModelKey = 'settings.v1.last_model';

  AppSettings load() {
    final modeName = _prefs.getString(displayModeKey);
    return AppSettings(
      displayMode: AnswerDisplayMode.values.firstWhere(
        (m) => m.name == modeName,
        orElse: () => AnswerDisplayMode.short,
      ),
      deleteImagesAfterAnalysis: _prefs.getBool(deleteImagesKey) ?? false,
      lastProvider: _prefs.getString(lastProviderKey),
      lastModel: _prefs.getString(lastModelKey),
    );
  }

  Future<void> setDisplayMode(AnswerDisplayMode mode) =>
      _prefs.setString(displayModeKey, mode.name);

  Future<void> setDeleteImagesAfterAnalysis({required bool value}) =>
      _prefs.setBool(deleteImagesKey, value);

  Future<void> setLastSelection({
    required String provider,
    required String model,
  }) async {
    await _prefs.setString(lastProviderKey, provider);
    await _prefs.setString(lastModelKey, model);
  }
}
