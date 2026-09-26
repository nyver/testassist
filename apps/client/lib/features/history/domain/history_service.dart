import '../../../core/storage/image_store.dart';
import '../../questions/domain/draft_repository.dart';
import 'history_entry.dart';

/// Deletion of history together with its image files.
class HistoryService {
  HistoryService(this._history, this._images);

  final HistoryRepository _history;
  final ImageStore _images;

  /// Deletes one entry and its image file.
  Future<void> deleteEntry(int id) async {
    final entry = await _history.get(id);
    await _history.delete(id);
    await _images.delete(entry?.imagePath);
  }

  /// Deletes every entry and every image file they referenced.
  Future<void> clearAll() async {
    final paths = [for (final e in await _history.list()) e.imagePath];
    await _history.clear();
    for (final path in paths) {
      await _images.delete(path);
    }
  }
}

/// Removes image files that no history entry and no draft refers to, for
/// example after a crash between writing an image and saving its entry.
Future<int> sweepOrphanImages({
  required HistoryRepository history,
  required DraftRepository drafts,
  required ImageStore images,
}) async {
  final referenced = <String>{
    for (final e in await history.list())
      if (e.imagePath != null) e.imagePath!,
  };
  final draftImage = (await drafts.load())?.imagePath;
  if (draftImage != null) referenced.add(draftImage);
  return images.sweepOrphans(referenced);
}
