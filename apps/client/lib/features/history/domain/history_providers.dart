import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/providers.dart';
import '../../questions/domain/models.dart';
import 'history_entry.dart';

/// All history entries, newest first, kept up to date.
final historyEntriesProvider = StreamProvider.autoDispose<List<HistoryEntry>>(
  (ref) => ref.watch(historyRepositoryProvider).watchAll(),
);

/// One history entry, or null when it does not exist (any more).
final historyEntryProvider = FutureProvider.autoDispose
    .family<HistoryEntry?, int>(
      (ref, id) => ref.watch(historyRepositoryProvider).get(id),
    );

/// Whether a model accepts images, looked up on the server. False when the
/// model or provider cannot be found or the server is unreachable, so an image
/// is never sent by mistake.
final modelSupportsVisionProvider = FutureProvider.autoDispose
    .family<bool, ({String provider, String model})>((ref, key) async {
      final api = ref.watch(questionsApiProvider);
      if (api == null) return false;
      try {
        final models = await api.models(key.provider);
        return models.any(
          (ModelInfo m) => m.id == key.model && m.supportsVision,
        );
      } on Object {
        return false;
      }
    });
