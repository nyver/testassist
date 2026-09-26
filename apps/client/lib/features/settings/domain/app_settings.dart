/// How much of the answer the result screen shows by default.
enum AnswerDisplayMode {
  /// Correct option only.
  optionOnly,

  /// Answer + short explanation (default).
  short,

  /// Answer, explanation and details.
  detailed,
}

/// Non-secret preferences. Secrets stay in secure storage.
class AppSettings {
  const AppSettings({
    this.displayMode = AnswerDisplayMode.short,
    this.deleteImagesAfterAnalysis = false,
    this.lastProvider,
    this.lastModel,
  });

  final AnswerDisplayMode displayMode;
  final bool deleteImagesAfterAnalysis;

  /// The last provider and model the user picked, if any.
  final String? lastProvider;
  final String? lastModel;
}
