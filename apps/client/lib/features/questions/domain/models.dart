import 'package:flutter/foundation.dart';

/// One answer option of a question.
@immutable
class OptionItem {
  const OptionItem({required this.id, required this.text});

  final String id;
  final String text;

  OptionItem copyWith({String? id, String? text}) =>
      OptionItem(id: id ?? this.id, text: text ?? this.text);

  @override
  bool operator ==(Object other) =>
      other is OptionItem && other.id == id && other.text == text;

  @override
  int get hashCode => Object.hash(id, text);

  @override
  String toString() => 'OptionItem($id, $text)';
}

/// Whether the model found a reliable answer.
enum AnswerStatus {
  answered,
  uncertain;

  static AnswerStatus parse(String value) => AnswerStatus.values.firstWhere(
    (s) => s.name == value,
    orElse: () => throw FormatException('Unknown status: $value'),
  );
}

/// Coarse confidence, normalized by the server from a numeric value.
enum ConfidenceLevel {
  high,
  medium,
  low;

  static ConfidenceLevel parse(String value) =>
      ConfidenceLevel.values.firstWhere(
        (l) => l.name == value,
        orElse: () => throw FormatException('Unknown confidence: $value'),
      );
}

/// The validated answer the server returns.
@immutable
class AnalysisResult {
  const AnalysisResult({
    required this.status,
    required this.correctOptionIds,
    required this.answerText,
    required this.explanation,
    required this.details,
    required this.confidence,
    required this.confidenceLevel,
    required this.warnings,
    required this.provider,
    required this.model,
    this.requestId,
  });

  final AnswerStatus status;
  final List<String> correctOptionIds;
  final String? answerText;
  final String? explanation;
  final String? details;
  final double confidence;
  final ConfidenceLevel confidenceLevel;
  final List<String> warnings;
  final String provider;
  final String model;

  /// The server request id, for support and logs.
  final String? requestId;

  bool get isUncertain => status == AnswerStatus.uncertain;
}

/// The question being prepared: what the user sees and edits on the
/// recognition screen. It is persisted so it survives process death.
@immutable
class QuestionDraft {
  const QuestionDraft({
    required this.imagePath,
    required this.ocrText,
    required this.questionText,
    required this.options,
    required this.sendImage,
  });

  /// Path relative to the app-private image directory, or null.
  final String? imagePath;
  final String ocrText;
  final String questionText;
  final List<OptionItem> options;
  final bool sendImage;

  QuestionDraft copyWith({
    String? Function()? imagePath,
    String? ocrText,
    String? questionText,
    List<OptionItem>? options,
    bool? sendImage,
  }) => QuestionDraft(
    imagePath: imagePath != null ? imagePath() : this.imagePath,
    ocrText: ocrText ?? this.ocrText,
    questionText: questionText ?? this.questionText,
    options: options ?? this.options,
    sendImage: sendImage ?? this.sendImage,
  );
}

/// Whether a draft can be sent: a question, at least two options, and option
/// ids that are non-empty and unique.
@immutable
class DraftValidation {
  const DraftValidation({
    required this.hasQuestion,
    required this.enoughOptions,
    required this.emptyIdIndexes,
    required this.duplicateIdIndexes,
    required this.emptyTextIndexes,
  });

  factory DraftValidation.of(String question, List<OptionItem> options) {
    final ids = options.map((o) => o.id.trim()).toList();
    final counts = <String, int>{};
    for (final id in ids.where((id) => id.isNotEmpty)) {
      counts[id] = (counts[id] ?? 0) + 1;
    }
    return DraftValidation(
      hasQuestion: question.trim().isNotEmpty,
      enoughOptions: options.length >= 2,
      emptyIdIndexes: {
        for (var i = 0; i < ids.length; i++)
          if (ids[i].isEmpty) i,
      },
      duplicateIdIndexes: {
        for (var i = 0; i < ids.length; i++)
          if (ids[i].isNotEmpty && counts[ids[i]]! > 1) i,
      },
      emptyTextIndexes: {
        for (var i = 0; i < options.length; i++)
          if (options[i].text.trim().isEmpty) i,
      },
    );
  }

  final bool hasQuestion;
  final bool enoughOptions;
  final Set<int> emptyIdIndexes;
  final Set<int> duplicateIdIndexes;
  final Set<int> emptyTextIndexes;

  bool get canSend =>
      hasQuestion &&
      enoughOptions &&
      emptyIdIndexes.isEmpty &&
      duplicateIdIndexes.isEmpty &&
      emptyTextIndexes.isEmpty;
}

/// An LLM provider the server has enabled.
@immutable
class ProviderInfo {
  const ProviderInfo({
    required this.id,
    required this.name,
    required this.isDefault,
  });

  final String id;
  final String name;
  final bool isDefault;
}

/// A model of a provider with its input capabilities.
@immutable
class ModelInfo {
  const ModelInfo({
    required this.id,
    required this.name,
    required this.supportsText,
    required this.supportsVision,
    required this.isDefault,
  });

  final String id;
  final String name;
  final bool supportsText;
  final bool supportsVision;
  final bool isDefault;
}

/// What the client sends to `POST /api/v1/questions/analyze`.
@immutable
class AnalyzeRequest {
  const AnalyzeRequest({
    required this.question,
    required this.options,
    required this.language,
    required this.provider,
    required this.model,
    this.imagePath,
  });

  final String question;
  final List<OptionItem> options;

  /// Language code of the app, used for the explanation.
  final String language;
  final String provider;
  final String model;

  /// Absolute path of the JPEG to upload, or null to send text only.
  final String? imagePath;
}
