import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/providers.dart';
import '../data/settings_repository.dart';

final settingsControllerProvider =
    NotifierProvider<SettingsController, AppSettings>(SettingsController.new);

/// The app's non-secret preferences as observable state.
class SettingsController extends Notifier<AppSettings> {
  SettingsRepository get _repo => ref.read(settingsRepositoryProvider);

  @override
  AppSettings build() => ref.watch(settingsRepositoryProvider).load();

  Future<void> setDisplayMode(AnswerDisplayMode mode) async {
    await _repo.setDisplayMode(mode);
    state = _repo.load();
  }

  Future<void> setDeleteImagesAfterAnalysis({required bool value}) async {
    await _repo.setDeleteImagesAfterAnalysis(value: value);
    state = _repo.load();
  }

  Future<void> rememberSelection({
    required String provider,
    required String model,
  }) async {
    await _repo.setLastSelection(provider: provider, model: model);
    state = _repo.load();
  }
}
