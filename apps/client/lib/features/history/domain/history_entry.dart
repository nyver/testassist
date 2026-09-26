import 'package:flutter/foundation.dart';

import '../../questions/domain/models.dart';

/// A saved analysis.
@immutable
class HistoryEntry {
  const HistoryEntry({
    required this.id,
    required this.createdAt,
    required this.imagePath,
    required this.ocrText,
    required this.questionText,
    required this.options,
    required this.result,
    required this.serverRef,
  });

  final int id;
  final DateTime createdAt;

  /// Path relative to the app-private image directory, or null when there was
  /// no image or it was deleted.
  final String? imagePath;
  final String ocrText;
  final String questionText;
  final List<OptionItem> options;
  final AnalysisResult result;

  /// Local id of the server that answered, or null once it was removed.
  final int? serverRef;
}

/// The data of a history entry that is not known before it is inserted.
@immutable
class NewHistoryEntry {
  const NewHistoryEntry({
    required this.imagePath,
    required this.ocrText,
    required this.questionText,
    required this.options,
    required this.result,
    required this.serverRef,
  });

  final String? imagePath;
  final String ocrText;
  final String questionText;
  final List<OptionItem> options;
  final AnalysisResult result;
  final int? serverRef;
}

abstract interface class HistoryRepository {
  Future<HistoryEntry> insert(NewHistoryEntry entry);

  /// All entries, newest first.
  Stream<List<HistoryEntry>> watchAll();

  Future<List<HistoryEntry>> list();

  Future<HistoryEntry?> get(int id);

  Future<void> delete(int id);

  Future<void> clear();
}
