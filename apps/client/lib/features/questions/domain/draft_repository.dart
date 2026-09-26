import 'models.dart';

/// Storage of the single draft.
abstract interface class DraftRepository {
  Future<QuestionDraft?> load();

  Future<void> save(QuestionDraft draft);

  Future<void> clear();
}
