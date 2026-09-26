import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/di/providers.dart';
import '../../../shared/dialogs.dart';
import '../../../shared/l10n.dart';
import '../../questions/domain/models.dart';
import '../../questions/domain/result_text.dart';
import '../domain/history_entry.dart';
import '../domain/history_providers.dart';

/// Past analyses, newest first.
class HistoryScreen extends ConsumerWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final entries = ref.watch(historyEntriesProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.historyTitle),
        actions: [
          if (entries.value?.isNotEmpty ?? false)
            IconButton(
              key: const Key('history-clear'),
              tooltip: l10n.historyClearAll,
              icon: const Icon(Icons.delete_sweep_outlined),
              onPressed: () => _clearAll(context, ref),
            ),
        ],
      ),
      body: SafeArea(
        child: entries.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => Center(child: Text(l10n.errorGenericNoId)),
          data: (list) => list.isEmpty
              ? Center(
                  child: Text(
                    l10n.historyEmpty,
                    key: const Key('history-empty'),
                  ),
                )
              : ListView.separated(
                  itemCount: list.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, i) => _HistoryTile(entry: list[i]),
                ),
        ),
      ),
    );
  }

  Future<void> _clearAll(BuildContext context, WidgetRef ref) async {
    final l10n = context.l10n;
    final confirmed = await confirmDialog(
      context,
      message: l10n.historyClearConfirm,
      confirmLabel: l10n.actionDelete,
    );
    if (confirmed) await ref.read(historyServiceProvider).clearAll();
  }
}

class _HistoryTile extends ConsumerWidget {
  const _HistoryTile({required this.entry});

  final HistoryEntry entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final locale = Localizations.localeOf(context).toString();
    final result = entry.result;
    final answer = result.isUncertain
        ? l10n.historyNoAnswer
        : correctOptions(entry.options, result).map(optionLabel).join('; ');
    final level = switch (result.confidenceLevel) {
      ConfidenceLevel.high => l10n.confidenceHigh,
      ConfidenceLevel.medium => l10n.confidenceMedium,
      ConfidenceLevel.low => l10n.confidenceLow,
    };
    final date = DateFormat.yMMMd(locale).add_Hm().format(entry.createdAt);

    return ListTile(
      key: Key('history-entry-${entry.id}'),
      minVerticalPadding: 12,
      title: Text(
        entry.questionText,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              answer,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            Text('$level · $date'),
          ],
        ),
      ),
      trailing: PopupMenuButton<String>(
        key: Key('history-menu-${entry.id}'),
        onSelected: (_) => _delete(context, ref),
        itemBuilder: (context) => [
          PopupMenuItem(
            key: Key('history-delete-${entry.id}'),
            value: 'delete',
            child: Text(l10n.actionDelete),
          ),
        ],
      ),
      onTap: () => context.push('/result/${entry.id}'),
    );
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final l10n = context.l10n;
    final confirmed = await confirmDialog(
      context,
      message: l10n.historyDeleteConfirm,
      confirmLabel: l10n.actionDelete,
    );
    if (confirmed) {
      await ref.read(historyServiceProvider).deleteEntry(entry.id);
    }
  }
}
