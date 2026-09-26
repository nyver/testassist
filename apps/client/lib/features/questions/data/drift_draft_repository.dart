import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../domain/draft_repository.dart';
import '../domain/models.dart';
import 'question_json.dart';

class DriftDraftRepository implements DraftRepository {
  DriftDraftRepository(this._db, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final AppDatabase _db;
  final DateTime Function() _clock;

  @override
  Future<QuestionDraft?> load() async {
    final row = await (_db.select(
      _db.drafts,
    )..where((t) => t.id.equals(1))).getSingleOrNull();
    if (row == null) return null;
    return QuestionDraft(
      imagePath: row.imagePath,
      ocrText: row.ocrText,
      questionText: row.questionText,
      options: decodeOptions(row.optionsJson),
      sendImage: row.sendImage,
    );
  }

  @override
  Future<void> save(QuestionDraft draft) => _db
      .into(_db.drafts)
      .insertOnConflictUpdate(
        DraftsCompanion.insert(
          id: const Value(1),
          imagePath: Value(draft.imagePath),
          ocrText: draft.ocrText,
          questionText: draft.questionText,
          optionsJson: encodeOptions(draft.options),
          sendImage: Value(draft.sendImage),
          updatedAt: _clock(),
        ),
      );

  @override
  Future<void> clear() => _db.delete(_db.drafts).go();
}
