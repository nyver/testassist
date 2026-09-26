import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/providers.dart';
import '../../../core/errors/app_failure.dart';
import '../../history/domain/history_entry.dart';
import '../../servers/domain/server_service.dart';
import '../../settings/domain/settings_controller.dart';
import 'draft_controller.dart';
import 'models.dart';

final analyzeControllerProvider =
    NotifierProvider<AnalyzeController, AnalyzeState>(AnalyzeController.new);

/// State of an analysis request.
@immutable
sealed class AnalyzeState {
  const AnalyzeState();
}

final class AnalyzeIdle extends AnalyzeState {
  const AnalyzeIdle();
}

final class AnalyzeRunning extends AnalyzeState {
  const AnalyzeRunning();
}

/// The request failed or was cancelled. The draft is untouched.
final class AnalyzeFailed extends AnalyzeState {
  const AnalyzeFailed(this.failure);

  final AppFailure failure;
}

/// The answer was saved to history as [entryId].
final class AnalyzeSucceeded extends AnalyzeState {
  const AnalyzeSucceeded(this.entryId);

  final int entryId;
}

/// Where the image of the new history entry comes from.
enum _ImageSource {
  /// The draft's image file moves into the history entry.
  draft,

  /// The image of an existing entry is copied, so both entries own a file.
  copyOfEntry,
}

/// Sends a question to the server and saves the answer.
///
/// Failures never touch the draft: it stays editable and is only removed after
/// the answer was saved to history.
class AnalyzeController extends Notifier<AnalyzeState> {
  CancelToken? _cancelToken;

  @override
  AnalyzeState build() {
    ref.onDispose(() => _cancelToken?.cancel('disposed'));
    return const AnalyzeIdle();
  }

  /// Analyzes the current draft with the chosen model.
  Future<void> analyzeDraft({
    required String provider,
    required String model,
    required bool modelSupportsVision,
    required String language,
  }) async {
    final draftController = ref.read(draftControllerProvider.notifier);
    await draftController.flush();
    final draft = ref.read(draftControllerProvider).value;
    if (draft == null) return;

    await _execute(
      question: draft.questionText,
      options: draft.options,
      ocrText: draft.ocrText,
      imagePath: draft.imagePath,
      attachImage: draft.sendImage && modelSupportsVision,
      source: _ImageSource.draft,
      provider: provider,
      model: model,
      language: language,
    );
  }

  /// Sends the question of a saved entry again, for "Retry" (same model) and
  /// "Change model". The result becomes a new history entry.
  Future<void> analyzeEntry(
    HistoryEntry entry, {
    required String provider,
    required String model,
    required bool modelSupportsVision,
    required String language,
  }) => _execute(
    question: entry.questionText,
    options: entry.options,
    ocrText: entry.ocrText,
    imagePath: entry.imagePath,
    // A retry resends the image only when the entry still has one and the
    // model can use it.
    attachImage: entry.imagePath != null && modelSupportsVision,
    source: _ImageSource.copyOfEntry,
    provider: provider,
    model: model,
    language: language,
  );

  /// Cancels the running request. The HTTP request is aborted.
  void cancel() => _cancelToken?.cancel('cancelled by the user');

  /// Returns to idle, for example after an error was shown.
  void reset() {
    if (state is! AnalyzeRunning) state = const AnalyzeIdle();
  }

  Future<void> _execute({
    required String question,
    required List<OptionItem> options,
    required String ocrText,
    required String? imagePath,
    required bool attachImage,
    required _ImageSource source,
    required String provider,
    required String model,
    required String language,
  }) async {
    if (state is AnalyzeRunning) return;
    state = const AnalyzeRunning();
    final token = _cancelToken = CancelToken();

    try {
      await ref.read(serverIdentityVerifierProvider)();

      final api = ref.read(questionsApiProvider);
      if (api == null) throw const NetworkFailure('no server configured');

      final images = ref.read(imageStoreProvider);
      String? uploadPath;
      if (attachImage) {
        final file = images.resolve(imagePath);
        if (file != null && await file.exists()) uploadPath = file.path;
      }

      final result = await api.analyze(
        AnalyzeRequest(
          question: question,
          options: options,
          language: language,
          provider: provider,
          model: model,
          imagePath: uploadPath,
        ),
        cancelToken: token,
      );

      final entryId = await _save(
        question: question,
        options: options,
        ocrText: ocrText,
        imagePath: imagePath,
        source: source,
        result: result,
      );
      await ref
          .read(settingsControllerProvider.notifier)
          .rememberSelection(provider: result.provider, model: result.model);
      state = AnalyzeSucceeded(entryId);
    } on AppFailure catch (failure) {
      state = AnalyzeFailed(failure);
    } on Object catch (e) {
      state = AnalyzeFailed(UnexpectedFailure(e.runtimeType.toString()));
    } finally {
      _cancelToken = null;
    }
  }

  /// Saves the answer, handling the image according to the settings, and
  /// clears the draft when it was the source.
  Future<int> _save({
    required String question,
    required List<OptionItem> options,
    required String ocrText,
    required String? imagePath,
    required _ImageSource source,
    required AnalysisResult result,
  }) async {
    final images = ref.read(imageStoreProvider);
    final deleteAfter = ref
        .read(settingsControllerProvider)
        .deleteImagesAfterAnalysis;

    String? historyImage;
    switch (source) {
      case _ImageSource.draft:
        if (deleteAfter) {
          await images.delete(imagePath);
        } else {
          historyImage = imagePath;
        }
      case _ImageSource.copyOfEntry:
        if (!deleteAfter) historyImage = await _copyImage(imagePath);
    }

    final server = ref.read(serverSessionProvider).value?.record;
    final entry = await ref
        .read(historyRepositoryProvider)
        .insert(
          NewHistoryEntry(
            imagePath: historyImage,
            ocrText: ocrText,
            questionText: question,
            options: options,
            result: result,
            serverRef: server?.id,
          ),
        );

    if (source == _ImageSource.draft) {
      await ref.read(draftControllerProvider.notifier).clearAfterSave();
    }
    return entry.id;
  }

  /// Copies an image file into a new file of its own. Returns the new relative
  /// path, or null when the source no longer exists.
  Future<String?> _copyImage(String? relativePath) async {
    final images = ref.read(imageStoreProvider);
    final source = images.resolve(relativePath);
    if (source == null || !await source.exists()) return null;
    final target = await images.create();
    try {
      await source.copy(target.file.path);
      return target.relativePath;
    } on FileSystemException {
      return null;
    }
  }
}
