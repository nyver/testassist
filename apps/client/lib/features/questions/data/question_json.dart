import 'dart:convert';

import '../domain/models.dart';

/// Version of the JSON layouts stored in `options_json` and `answer_json`.
const storedJsonVersion = 1;

String encodeOptions(List<OptionItem> options) => jsonEncode({
  'v': storedJsonVersion,
  'options': [
    for (final o in options) {'id': o.id, 'text': o.text},
  ],
});

List<OptionItem> decodeOptions(String source) {
  final map = _decodeVersioned(source);
  final list = map['options'];
  if (list is! List<Object?>) {
    throw const FormatException('options_json has no options list');
  }
  return [
    for (final item in list)
      if (item is Map<String, Object?>)
        OptionItem(id: item['id']! as String, text: item['text']! as String),
  ];
}

/// The parts of a result that are stored in `answer_json`. Confidence,
/// provider, model and request id have their own columns.
String encodeAnswer(AnalysisResult r) => jsonEncode({
  'v': storedJsonVersion,
  'status': r.status.name,
  'correctOptionIds': r.correctOptionIds,
  'answerText': r.answerText,
  'explanation': r.explanation,
  'details': r.details,
  'warnings': r.warnings,
});

AnalysisResult decodeAnswer(
  String source, {
  required double confidence,
  required String confidenceLevel,
  required String provider,
  required String model,
  required String? requestId,
}) {
  final map = _decodeVersioned(source);
  return AnalysisResult(
    status: AnswerStatus.parse(map['status']! as String),
    correctOptionIds: _stringList(map['correctOptionIds']),
    answerText: map['answerText'] as String?,
    explanation: map['explanation'] as String?,
    details: map['details'] as String?,
    confidence: confidence,
    confidenceLevel: ConfidenceLevel.parse(confidenceLevel),
    warnings: _stringList(map['warnings']),
    provider: provider,
    model: model,
    requestId: requestId,
  );
}

/// Parses the `POST /api/v1/questions/analyze` response body.
AnalysisResult analysisResultFromApi(Map<String, Object?> json) {
  return AnalysisResult(
    status: AnswerStatus.parse(json['status']! as String),
    correctOptionIds: _stringList(json['correctOptionIds']),
    answerText: json['answerText'] as String?,
    explanation: json['explanation'] as String?,
    details: json['details'] as String?,
    confidence: (json['confidence']! as num).toDouble(),
    confidenceLevel: ConfidenceLevel.parse(json['confidenceLevel']! as String),
    warnings: _stringList(json['warnings']),
    provider: json['provider']! as String,
    model: json['model']! as String,
    requestId: json['requestId'] as String?,
    recognizedQuestion: json['recognizedQuestion'] as String?,
    recognizedOptions: _optionList(json['recognizedOptions']),
  );
}

Map<String, Object?> _decodeVersioned(String source) {
  final decoded = jsonDecode(source);
  if (decoded is! Map<String, Object?>) {
    throw const FormatException('Stored JSON is not an object');
  }
  final version = decoded['v'];
  if (version != storedJsonVersion) {
    // A newer app wrote this: refuse instead of misreading it.
    throw FormatException('Unsupported stored JSON version: $version');
  }
  return decoded;
}

List<OptionItem>? _optionList(Object? value) {
  if (value is! List<Object?>) return null;
  return [
    for (final item in value)
      if (item is Map<String, Object?>)
        OptionItem(id: item['id']! as String, text: item['text']! as String),
  ];
}

List<String> _stringList(Object? value) {
  if (value is! List<Object?>) return const [];
  return [for (final v in value) v! as String];
}
