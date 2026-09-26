import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/di/providers.dart';
import '../../../shared/l10n.dart';
import '../../../shared/widgets/synced_text_field.dart';
import '../domain/analyze_controller.dart';
import '../domain/draft_controller.dart';
import '../domain/model_selection_controller.dart';
import '../domain/models.dart';
import 'analyze_ui.dart';
import 'model_picker.dart';

/// Edit the recognized question, choose a model and ask for the answer.
class RecognitionScreen extends ConsumerStatefulWidget {
  const RecognitionScreen({super.key});

  @override
  ConsumerState<RecognitionScreen> createState() => _RecognitionScreenState();
}

class _RecognitionScreenState extends ConsumerState<RecognitionScreen>
    with WidgetsBindingObserver {
  late final DraftController _draftController;

  @override
  void initState() {
    super.initState();
    _draftController = ref.read(draftControllerProvider.notifier);
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // Whenever the screen is left, the draft is written out.
    _draftController.flush();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // The process can be killed while the app is in the background.
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _draftController.flush();
    }
  }

  Future<void> _getAnswer() async {
    final selection = ref.read(modelSelectionProvider).value;
    if (selection == null || selection.modelId == null) return;
    final language = Localizations.localeOf(context).languageCode;
    await ref
        .read(analyzeControllerProvider.notifier)
        .analyzeDraft(
          provider: selection.providerId,
          model: selection.modelId!,
          modelSupportsVision: selection.supportsVision,
          language: language,
        );
  }

  void _sendTextOnly() {
    _draftController.setSendImage(value: false);
    _getAnswer();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final draftAsync = ref.watch(draftControllerProvider);

    listenToAnalysis(
      context,
      ref,
      onRetry: _getAnswer,
      onSendTextOnly: _sendTextOnly,
    );

    // Turn the image switch off when a model without vision gets selected.
    ref.listen<bool?>(
      modelSelectionProvider.select((s) => s.value?.supportsVision),
      (previous, next) {
        if (next == false) {
          final changed = _draftController.enforceVisionGate(
            modelSupportsVision: false,
          );
          if (changed) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                key: const Key('vision-notice'),
                content: Text(l10n.errorModelNoVision),
              ),
            );
          }
        }
      },
    );

    return Scaffold(
      appBar: AppBar(title: Text(l10n.recognitionTitle)),
      body: SafeArea(
        child: Stack(
          children: [
            draftAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, _) => Center(child: Text(l10n.errorGenericNoId)),
              data: (draft) {
                if (draft == null) {
                  // The draft is also cleared when an analysis was saved; that
                  // flow navigates to the result itself.
                  final analyzing =
                      ref.read(analyzeControllerProvider) is! AnalyzeIdle;
                  if (!analyzing) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) context.go('/');
                    });
                  }
                  return const SizedBox.shrink();
                }
                return _DraftForm(draft: draft, onGetAnswer: _getAnswer);
              },
            ),
            const AnalyzeProgressOverlay(),
          ],
        ),
      ),
    );
  }
}

class _DraftForm extends ConsumerWidget {
  const _DraftForm({required this.draft, required this.onGetAnswer});

  final QuestionDraft draft;
  final VoidCallback onGetAnswer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final controller = ref.read(draftControllerProvider.notifier);
    final validation = DraftValidation.of(draft.questionText, draft.options);
    final selection = ref.watch(modelSelectionProvider).value;
    final running = ref.watch(
      analyzeControllerProvider.select((s) => s is AnalyzeRunning),
    );

    final lowQuality =
        draft.ocrText.trim().isEmpty ||
        !validation.hasQuestion ||
        !validation.enoughOptions;
    final canAttachImage =
        draft.imagePath != null && (selection?.supportsVision ?? false);
    final canSend =
        validation.canSend && (selection?.canAnalyze ?? false) && !running;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (draft.imagePath != null) _ImagePreview(path: draft.imagePath!),
            if (lowQuality)
              Card(
                key: const Key('low-quality-warning'),
                color: Theme.of(context).colorScheme.tertiaryContainer,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      const Icon(Icons.warning_amber_rounded),
                      const SizedBox(width: 12),
                      Expanded(child: Text(l10n.recognitionLowQuality)),
                    ],
                  ),
                ),
              ),
            ExpansionTile(
              key: const Key('raw-text-tile'),
              title: Text(l10n.recognitionRawText),
              tilePadding: EdgeInsets.zero,
              children: [
                SyncedTextField(
                  key: const Key('raw-text'),
                  value: draft.ocrText,
                  minLines: 3,
                  maxLines: 10,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                  ),
                  onChanged: controller.updateOcrText,
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    key: const Key('reparse'),
                    onPressed: controller.reparse,
                    icon: const Icon(Icons.refresh),
                    label: Text(l10n.recognitionReparse),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SyncedTextField(
              key: const Key('question-field'),
              value: draft.questionText,
              minLines: 2,
              maxLines: 8,
              decoration: InputDecoration(
                labelText: l10n.recognitionQuestion,
                border: const OutlineInputBorder(),
              ),
              onChanged: controller.updateQuestion,
            ),
            const SizedBox(height: 16),
            Text(
              l10n.recognitionOptions,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            for (var i = 0; i < draft.options.length; i++)
              _OptionRow(
                key: ValueKey('option-row-$i'),
                index: i,
                option: draft.options[i],
                count: draft.options.length,
                duplicate: validation.duplicateIdIndexes.contains(i),
                emptyId: validation.emptyIdIndexes.contains(i),
              ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: const Key('add-option'),
                onPressed: controller.addOption,
                icon: const Icon(Icons.add),
                label: Text(l10n.recognitionAddOption),
              ),
            ),
            const Divider(height: 32),
            const ModelPickerSection(),
            const SizedBox(height: 8),
            SwitchListTile(
              key: const Key('send-image-switch'),
              contentPadding: EdgeInsets.zero,
              title: Text(l10n.recognitionSendImage),
              subtitle: canAttachImage || draft.imagePath == null
                  ? null
                  : Text(l10n.recognitionSendImageUnavailable),
              value: draft.sendImage && canAttachImage,
              onChanged: canAttachImage
                  ? (value) => controller.setSendImage(value: value)
                  : null,
            ),
            const SizedBox(height: 8),
            FilledButton(
              key: const Key('get-answer'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(56),
              ),
              onPressed: canSend ? onGetAnswer : null,
              child: Text(l10n.recognitionGetAnswer),
            ),
          ],
        ),
      ),
    );
  }
}

class _OptionRow extends ConsumerWidget {
  const _OptionRow({
    super.key,
    required this.index,
    required this.option,
    required this.count,
    required this.duplicate,
    required this.emptyId,
  });

  final int index;
  final OptionItem option;
  final int count;
  final bool duplicate;
  final bool emptyId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final controller = ref.read(draftControllerProvider.notifier);
    final scheme = Theme.of(context).colorScheme;
    final idError = duplicate
        ? l10n.recognitionDuplicateId
        : (emptyId ? l10n.recognitionEmptyId : null);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 84,
            child: SyncedTextField(
              key: Key('option-id-$index'),
              value: option.id,
              decoration: InputDecoration(
                labelText: l10n.recognitionOptionId,
                border: const OutlineInputBorder(),
                errorText: idError,
                errorMaxLines: 3,
                enabledBorder: duplicate
                    ? OutlineInputBorder(
                        borderSide: BorderSide(color: scheme.error, width: 2),
                      )
                    : null,
              ),
              onChanged: (value) =>
                  controller.updateOption(index, option.copyWith(id: value)),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: SyncedTextField(
              key: Key('option-text-$index'),
              value: option.text,
              minLines: 1,
              maxLines: 5,
              decoration: InputDecoration(
                labelText: l10n.recognitionOptionText,
                border: const OutlineInputBorder(),
              ),
              onChanged: (value) =>
                  controller.updateOption(index, option.copyWith(text: value)),
            ),
          ),
          PopupMenuButton<String>(
            key: Key('option-menu-$index'),
            onSelected: (action) {
              switch (action) {
                case 'up':
                  controller.moveOption(index, -1);
                case 'down':
                  controller.moveOption(index, 1);
                case 'remove':
                  controller.removeOption(index);
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'up',
                enabled: index > 0,
                child: Text(l10n.recognitionMoveUp),
              ),
              PopupMenuItem(
                value: 'down',
                enabled: index < count - 1,
                child: Text(l10n.recognitionMoveDown),
              ),
              PopupMenuItem(
                value: 'remove',
                child: Text(l10n.recognitionRemoveOption),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ImagePreview extends ConsumerWidget {
  const _ImagePreview({required this.path});

  final String path;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final file = ref.watch(imageStoreProvider).resolve(path);
    if (file == null || !file.existsSync()) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 220),
          child: Image.file(File(file.path), fit: BoxFit.contain),
        ),
      ),
    );
  }
}
