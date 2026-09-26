import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/providers.dart';
import '../../../core/errors/app_failure.dart';
import '../../settings/domain/app_settings.dart';
import '../../settings/domain/settings_controller.dart';
import 'models.dart';

final modelSelectionProvider =
    AsyncNotifierProvider<ModelSelectionController, ModelSelection>(
      ModelSelectionController.new,
    );

/// The providers and models offered by the server and the current choice.
@immutable
class ModelSelection {
  const ModelSelection({
    required this.providers,
    required this.models,
    required this.providerId,
    required this.modelId,
    this.loadingModels = false,
    this.modelsFailed = false,
  });

  final List<ProviderInfo> providers;

  /// Models of [providerId].
  final List<ModelInfo> models;
  final String providerId;
  final String? modelId;
  final bool loadingModels;

  /// The model list of the selected provider could not be loaded.
  final bool modelsFailed;

  ModelInfo? get selectedModel {
    for (final m in models) {
      if (m.id == modelId) return m;
    }
    return null;
  }

  bool get supportsVision => selectedModel?.supportsVision ?? false;

  bool get canAnalyze => modelId != null && !loadingModels;

  ModelSelection copyWith({
    List<ModelInfo>? models,
    String? providerId,
    String? Function()? modelId,
    bool? loadingModels,
    bool? modelsFailed,
  }) => ModelSelection(
    providers: providers,
    models: models ?? this.models,
    providerId: providerId ?? this.providerId,
    modelId: modelId != null ? modelId() : this.modelId,
    loadingModels: loadingModels ?? this.loadingModels,
    modelsFailed: modelsFailed ?? this.modelsFailed,
  );
}

/// Loads providers and models and keeps the selection. The last selection is
/// remembered; the server defaults are used when there is none or it is no
/// longer available.
class ModelSelectionController extends AsyncNotifier<ModelSelection> {
  @override
  Future<ModelSelection> build() async {
    final api = ref.watch(questionsApiProvider);
    if (api == null) throw const NetworkFailure('no server configured');

    final settings = ref.read(settingsControllerProvider);
    final providers = await api.providers();
    if (providers.isEmpty) throw const UnexpectedFailure('no providers');

    final providerId = _pickProvider(providers, settings.lastProvider);
    final models = await api.models(providerId);
    return ModelSelection(
      providers: providers,
      models: models,
      providerId: providerId,
      modelId: _pickModel(models, providerId, settings),
    );
  }

  Future<void> selectProvider(String providerId) async {
    final current = state.value;
    final api = ref.read(questionsApiProvider);
    if (current == null || api == null || providerId == current.providerId) {
      return;
    }

    state = AsyncData(
      current.copyWith(
        providerId: providerId,
        models: const [],
        modelId: () => null,
        loadingModels: true,
        modelsFailed: false,
      ),
    );
    try {
      final models = await api.models(providerId);
      final settings = ref.read(settingsControllerProvider);
      final modelId = _pickModel(models, providerId, settings);
      state = AsyncData(
        current.copyWith(
          providerId: providerId,
          models: models,
          modelId: () => modelId,
          loadingModels: false,
        ),
      );
      await _remember();
    } on AppFailure {
      state = AsyncData(
        current.copyWith(
          providerId: providerId,
          models: const [],
          modelId: () => null,
          loadingModels: false,
          modelsFailed: true,
        ),
      );
    }
  }

  Future<void> selectModel(String modelId) async {
    final current = state.value;
    if (current == null || current.models.every((m) => m.id != modelId)) {
      return;
    }
    state = AsyncData(current.copyWith(modelId: () => modelId));
    await _remember();
  }

  Future<void> _remember() async {
    final s = state.value;
    final model = s?.modelId;
    if (s == null || model == null) return;
    await ref
        .read(settingsControllerProvider.notifier)
        .rememberSelection(provider: s.providerId, model: model);
  }

  String _pickProvider(List<ProviderInfo> providers, String? remembered) {
    if (remembered != null && providers.any((p) => p.id == remembered)) {
      return remembered;
    }
    return providers
        .firstWhere((p) => p.isDefault, orElse: () => providers.first)
        .id;
  }

  String? _pickModel(
    List<ModelInfo> models,
    String providerId,
    AppSettings settings,
  ) {
    if (models.isEmpty) return null;
    final remembered = settings.lastProvider == providerId
        ? settings.lastModel
        : null;
    if (remembered != null && models.any((m) => m.id == remembered)) {
      return remembered;
    }
    return models.firstWhere((m) => m.isDefault, orElse: () => models.first).id;
  }
}
