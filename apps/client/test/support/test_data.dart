import 'package:drift/native.dart';
import 'package:test_assistant/core/database/app_database.dart';
import 'package:test_assistant/features/questions/domain/models.dart';

/// A fresh in-memory database.
AppDatabase openTestDatabase() => AppDatabase(NativeDatabase.memory());

const optionsAbcd = [
  OptionItem(id: 'A', text: 'HTTP'),
  OptionItem(id: 'B', text: 'HTTPS'),
  OptionItem(id: 'C', text: 'TLS'),
  OptionItem(id: 'D', text: 'SSH'),
];

AnalysisResult answeredResult({
  List<String> ids = const ['B'],
  String? answerText = 'HTTPS',
  String? explanation = 'HTTPS wraps HTTP in TLS.',
  String? details,
  double confidence = 0.96,
  ConfidenceLevel level = ConfidenceLevel.high,
  List<String> warnings = const [],
  String provider = 'openrouter',
  String model = 'openai/gpt-4o-mini',
  String? requestId = 'req-1',
}) => AnalysisResult(
  status: AnswerStatus.answered,
  correctOptionIds: ids,
  answerText: answerText,
  explanation: explanation,
  details: details,
  confidence: confidence,
  confidenceLevel: level,
  warnings: warnings,
  provider: provider,
  model: model,
  requestId: requestId,
);

AnalysisResult uncertainResult({
  List<String> warnings = const ['Option C is not readable'],
}) => AnalysisResult(
  status: AnswerStatus.uncertain,
  correctOptionIds: const [],
  answerText: null,
  explanation: null,
  details: null,
  confidence: 0.31,
  confidenceLevel: ConfidenceLevel.low,
  warnings: warnings,
  provider: 'routerai',
  model: 'openai/gpt-4o-mini',
  requestId: 'req-2',
);
