import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../questions/data/question_json.dart';
import '../domain/history_entry.dart';

class DriftHistoryRepository implements HistoryRepository {
  DriftHistoryRepository(this._db, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final AppDatabase _db;
  final DateTime Function() _clock;

  /// Newest first; the id breaks ties between entries saved in the same
  /// instant.
  SimpleSelectStatement<$QuestionsTable, Question> get _newestFirst =>
      _db.select(_db.questions)..orderBy([
        (t) => OrderingTerm.desc(t.createdAt),
        (t) => OrderingTerm.desc(t.id),
      ]);

  @override
  Future<HistoryEntry> insert(NewHistoryEntry entry) async {
    final result = entry.result;
    final id = await _db
        .into(_db.questions)
        .insert(
          QuestionsCompanion.insert(
            serverRef: Value(entry.serverRef),
            imagePath: Value(entry.imagePath),
            ocrText: entry.ocrText,
            questionText: entry.questionText,
            optionsJson: encodeOptions(entry.options),
            answerJson: encodeAnswer(result),
            provider: result.provider,
            model: result.model,
            confidence: result.confidence,
            confidenceLevel: result.confidenceLevel.name,
            requestId: Value(result.requestId),
            createdAt: _clock(),
          ),
        );
    final row = await (_db.select(
      _db.questions,
    )..where((t) => t.id.equals(id))).getSingle();
    return _map(row);
  }

  @override
  Stream<List<HistoryEntry>> watchAll() =>
      _newestFirst.watch().map((rows) => rows.map(_map).toList());

  @override
  Future<List<HistoryEntry>> list() async =>
      (await _newestFirst.get()).map(_map).toList();

  @override
  Future<HistoryEntry?> get(int id) async {
    final row = await (_db.select(
      _db.questions,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    return row == null ? null : _map(row);
  }

  @override
  Future<void> delete(int id) =>
      (_db.delete(_db.questions)..where((t) => t.id.equals(id))).go();

  @override
  Future<void> clear() => _db.delete(_db.questions).go();

  HistoryEntry _map(Question row) => HistoryEntry(
    id: row.id,
    createdAt: row.createdAt,
    imagePath: row.imagePath,
    ocrText: row.ocrText,
    questionText: row.questionText,
    options: decodeOptions(row.optionsJson),
    result: decodeAnswer(
      row.answerJson,
      confidence: row.confidence,
      confidenceLevel: row.confidenceLevel,
      provider: row.provider,
      model: row.model,
      requestId: row.requestId,
    ),
    serverRef: row.serverRef,
  );
}
