import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/di/providers.dart';
import '../../../shared/dialogs.dart';
import '../../../shared/l10n.dart';
import '../../../shared/snack.dart';
import '../../history/domain/history_entry.dart';
import '../../history/domain/history_providers.dart';
import '../../settings/domain/app_settings.dart';
import '../../settings/domain/settings_controller.dart';
import '../domain/analyze_controller.dart';
import '../domain/model_selection_controller.dart';
import '../domain/models.dart';
import '../domain/result_text.dart';
import 'analyze_ui.dart';
import 'model_picker.dart';

/// Shares plain text with other apps. Replaced in tests.
final shareTextProvider = Provider<Future<void> Function(String text)>(
  (ref) =>
      (text) => SharePlus.instance.share(ShareParams(text: text)),
);

/// The answer to one history entry.
class ResultScreen extends ConsumerStatefulWidget {
  const ResultScreen({super.key, required this.entryId});

  final int entryId;

  @override
  ConsumerState<ResultScreen> createState() => _ResultScreenState();
}

class _ResultScreenState extends ConsumerState<ResultScreen> {
  bool _showMore = false;

  Future<void> _retry(
    HistoryEntry entry, {
    String? provider,
    String? model,
    bool? supportsVision,
  }) async {
    final language = Localizations.localeOf(context).languageCode;
    final p = provider ?? entry.result.provider;
    final m = model ?? entry.result.model;
    final vision =
        supportsVision ??
        await ref.read(
          modelSupportsVisionProvider((provider: p, model: m)).future,
        );
    if (!mounted) return;
    await ref
        .read(analyzeControllerProvider.notifier)
        .analyzeEntry(
          entry,
          provider: p,
          model: m,
          modelSupportsVision: vision ?? false,
          language: language,
        );
  }

  Future<void> _changeModel(HistoryEntry entry) async {
    final l10n = context.l10n;
    // Make sure the picker starts at the entry's own provider and model.
    final chosen = await showModelPickerSheet(
      context,
      confirmLabel: l10n.actionChangeModel,
    );
    if (!chosen || !mounted) return;
    final selection = ref.read(modelSelectionProvider).value;
    if (selection == null || selection.modelId == null) return;
    await _retry(
      entry,
      provider: selection.providerId,
      model: selection.modelId,
      supportsVision: selection.supportsVision,
    );
  }

  Future<void> _copy(HistoryEntry entry) async {
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    await Clipboard.setData(ClipboardData(text: composeShareText(l10n, entry)));
    showMessage(messenger, l10n.resultCopied);
  }

  Future<void> _delete(HistoryEntry entry) async {
    final l10n = context.l10n;
    final confirmed = await confirmDialog(
      context,
      message: l10n.resultDeleteConfirm,
      confirmLabel: l10n.actionDelete,
    );
    if (!confirmed) return;
    await ref.read(historyServiceProvider).deleteEntry(entry.id);
    if (mounted) context.go('/');
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final entryAsync = ref.watch(historyEntryProvider(widget.entryId));

    listenToAnalysis(
      context,
      ref,
      onRetry: () {
        final entry = entryAsync.value;
        if (entry != null) _retry(entry);
      },
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.resultTitle),
        leading: BackButton(
          onPressed: () => context.canPop() ? context.pop() : context.go('/'),
        ),
      ),
      body: SafeArea(
        child: Stack(
          children: [
            entryAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, _) => Center(child: Text(l10n.errorGenericNoId)),
              data: (entry) => entry == null
                  ? Center(child: Text(l10n.errorGenericNoId))
                  : _ResultBody(
                      entry: entry,
                      showMore: _showMore,
                      onMore: () => setState(() => _showMore = true),
                      onRetry: () => _retry(entry),
                      onChangeModel: () => _changeModel(entry),
                      onCopy: () => _copy(entry),
                      onShare: () => ref.read(shareTextProvider)(
                        composeShareText(l10n, entry),
                      ),
                      onDelete: () => _delete(entry),
                    ),
            ),
            const AnalyzeProgressOverlay(),
          ],
        ),
      ),
    );
  }
}

class _ResultBody extends ConsumerWidget {
  const _ResultBody({
    required this.entry,
    required this.showMore,
    required this.onMore,
    required this.onRetry,
    required this.onChangeModel,
    required this.onCopy,
    required this.onShare,
    required this.onDelete,
  });

  final HistoryEntry entry;
  final bool showMore;
  final VoidCallback onMore;
  final VoidCallback onRetry;
  final VoidCallback onChangeModel;
  final VoidCallback onCopy;
  final VoidCallback onShare;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final result = entry.result;
    final mode = ref.watch(
      settingsControllerProvider.select((s) => s.displayMode),
    );

    final hasExplanation = (result.explanation ?? '').trim().isNotEmpty;
    final hasDetails = (result.details ?? '').trim().isNotEmpty;
    final explanationVisible =
        hasExplanation && (mode != AnswerDisplayMode.optionOnly || showMore);
    final detailsVisible =
        hasDetails && (mode == AnswerDisplayMode.detailed || showMore);
    final canShowMore =
        !showMore &&
        ((hasExplanation && !explanationVisible) ||
            (hasDetails && !detailsVisible));

    final image = ref.watch(imageStoreProvider).resolve(entry.imagePath);
    final options = correctOptions(entry.options, result);

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(entry.questionText, style: theme.textTheme.titleMedium),
            if (image != null && image.existsSync()) ...[
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 200),
                  child: Image.file(File(image.path), fit: BoxFit.contain),
                ),
              ),
            ],
            const SizedBox(height: 16),
            Card(
              key: const Key('answer-card'),
              color: result.isUncertain
                  ? theme.colorScheme.tertiaryContainer
                  : theme.colorScheme.primaryContainer,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (result.isUncertain)
                      Text(
                        l10n.resultUncertain,
                        key: const Key('uncertain-text'),
                        style: theme.textTheme.titleMedium,
                      )
                    else ...[
                      Text(
                        l10n.resultCorrectOptions,
                        style: theme.textTheme.labelMedium,
                      ),
                      const SizedBox(height: 4),
                      for (final option in options)
                        Text(
                          optionLabel(option),
                          key: Key('correct-${option.$1}'),
                          style: theme.textTheme.titleLarge,
                        ),
                    ],
                    const SizedBox(height: 8),
                    Text(
                      l10n.resultConfidence(_levelName(l10n, result)),
                      key: const Key('confidence'),
                    ),
                  ],
                ),
              ),
            ),
            if (result.warnings.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(l10n.resultWarnings, style: theme.textTheme.labelLarge),
              for (final warning in result.warnings)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.warning_amber_rounded, size: 18),
                      const SizedBox(width: 8),
                      Expanded(child: Text(warning, key: const Key('warning'))),
                    ],
                  ),
                ),
            ],
            if (explanationVisible) ...[
              const SizedBox(height: 16),
              Text(l10n.resultExplanation, style: theme.textTheme.labelLarge),
              const SizedBox(height: 4),
              Text(result.explanation!, key: const Key('explanation')),
            ],
            if (detailsVisible) ...[
              const SizedBox(height: 16),
              Text(l10n.resultDetails, style: theme.textTheme.labelLarge),
              const SizedBox(height: 4),
              Text(result.details!, key: const Key('details')),
            ],
            const SizedBox(height: 12),
            Text(
              l10n.resultProviderModel(result.provider, result.model),
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (canShowMore)
                  OutlinedButton.icon(
                    key: const Key('action-more'),
                    onPressed: onMore,
                    icon: const Icon(Icons.expand_more),
                    label: Text(l10n.actionMore),
                  ),
                OutlinedButton.icon(
                  key: const Key('action-retry'),
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh),
                  label: Text(l10n.actionRetry),
                ),
                OutlinedButton.icon(
                  key: const Key('action-change-model'),
                  onPressed: onChangeModel,
                  icon: const Icon(Icons.swap_horiz),
                  label: Text(l10n.actionChangeModel),
                ),
                OutlinedButton.icon(
                  key: const Key('action-copy'),
                  onPressed: onCopy,
                  icon: const Icon(Icons.copy),
                  label: Text(l10n.actionCopy),
                ),
                OutlinedButton.icon(
                  key: const Key('action-share'),
                  onPressed: onShare,
                  icon: const Icon(Icons.share),
                  label: Text(l10n.actionShare),
                ),
                OutlinedButton.icon(
                  key: const Key('action-delete'),
                  onPressed: onDelete,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: theme.colorScheme.error,
                  ),
                  icon: const Icon(Icons.delete_outline),
                  label: Text(l10n.resultDeleteFromHistory),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _levelName(AppLocalizations l10n, AnalysisResult result) {
    switch (result.confidenceLevel) {
      case ConfidenceLevel.high:
        return l10n.confidenceHigh;
      case ConfidenceLevel.medium:
        return l10n.confidenceMedium;
      case ConfidenceLevel.low:
        return l10n.confidenceLow;
    }
  }
}
