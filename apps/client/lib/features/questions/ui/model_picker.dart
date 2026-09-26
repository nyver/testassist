import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/app_failure.dart';
import '../../../shared/failure_messages.dart';
import '../../../shared/l10n.dart';
import '../domain/model_selection_controller.dart';
import '../domain/models.dart';

/// Provider and model choice. The provider is a dropdown; the model opens a
/// searchable list that shows which models accept images.
class ModelPickerSection extends ConsumerWidget {
  const ModelPickerSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final selection = ref.watch(modelSelectionProvider);

    return selection.when(
      loading: () => ListTile(
        key: const Key('model-loading'),
        leading: const SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        title: Text(l10n.modelLoading),
      ),
      error: (error, _) => Card(
        key: const Key('model-error'),
        child: ListTile(
          leading: const Icon(Icons.error_outline),
          title: Text(l10n.modelLoadFailed),
          // Say why, for example that the server certificate has changed.
          subtitle: error is AppFailure ? Text(_reason(l10n, error)) : null,
          trailing: TextButton(
            onPressed: () => ref.invalidate(modelSelectionProvider),
            child: Text(l10n.actionRetry),
          ),
        ),
      ),
      data: (data) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (data.providers.length > 1) ...[
            DropdownButtonFormField<String>(
              key: const Key('provider-dropdown'),
              initialValue: data.providerId,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: l10n.modelProvider,
                border: const OutlineInputBorder(),
              ),
              items: [
                for (final p in data.providers)
                  DropdownMenuItem(value: p.id, child: Text(p.name)),
              ],
              onChanged: (id) {
                if (id != null) {
                  ref.read(modelSelectionProvider.notifier).selectProvider(id);
                }
              },
            ),
            const SizedBox(height: 12),
          ],
          _ModelTile(selection: data),
        ],
      ),
    );
  }
}

class _ModelTile extends ConsumerWidget {
  const _ModelTile({required this.selection});

  final ModelSelection selection;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final model = selection.selectedModel;

    return OutlinedButton(
      key: const Key('model-button'),
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(56),
        alignment: Alignment.centerLeft,
      ),
      onPressed: selection.loadingModels
          ? null
          : () => showModelPickerSheet(context),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  l10n.modelModel,
                  style: Theme.of(context).textTheme.labelSmall,
                ),
                Text(
                  selection.loadingModels
                      ? l10n.modelLoading
                      : selection.modelsFailed
                      ? l10n.modelLoadFailed
                      : (model?.name ?? l10n.modelNoneAvailable),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          if (model != null) VisionBadge(supportsVision: model.supportsVision),
          const Icon(Icons.arrow_drop_down),
        ],
      ),
    );
  }
}

String _reason(AppLocalizations l10n, AppFailure failure) {
  final hint = failureHint(l10n, failure);
  final message = failureMessage(l10n, failure);
  return hint == null ? message : '$message\n$hint';
}

/// Small label telling whether a model accepts images.
class VisionBadge extends StatelessWidget {
  const VisionBadge({super.key, required this.supportsVision});

  final bool supportsVision;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    return Chip(
      key: Key(supportsVision ? 'badge-vision' : 'badge-text'),
      visualDensity: VisualDensity.compact,
      avatar: Icon(
        supportsVision ? Icons.image_outlined : Icons.text_fields,
        size: 16,
      ),
      label: Text(
        supportsVision ? l10n.modelVisionBadge : l10n.modelTextOnlyBadge,
      ),
      backgroundColor: supportsVision
          ? scheme.primaryContainer
          : scheme.surfaceContainerHighest,
    );
  }
}

/// Opens the model list. Returns true when the user confirmed a choice. With
/// [confirmLabel] the choice is applied by a button; without it, tapping a
/// model applies it and closes the sheet.
Future<bool> showModelPickerSheet(
  BuildContext context, {
  String? confirmLabel,
}) async {
  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => _ModelSheet(confirmLabel: confirmLabel),
  );
  return result ?? false;
}

class _ModelSheet extends ConsumerStatefulWidget {
  const _ModelSheet({this.confirmLabel});

  final String? confirmLabel;

  @override
  ConsumerState<_ModelSheet> createState() => _ModelSheetState();
}

class _ModelSheetState extends ConsumerState<_ModelSheet> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final selection = ref.watch(modelSelectionProvider).value;
    if (selection == null) return const SizedBox.shrink();

    final query = _query.trim().toLowerCase();
    final models = [
      for (final m in selection.models)
        if (query.isEmpty ||
            m.name.toLowerCase().contains(query) ||
            m.id.toLowerCase().contains(query))
          m,
    ];

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.75,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Column(
                  children: [
                    Text(
                      l10n.modelPickerTitle,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    if (selection.providers.length > 1) ...[
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        key: const Key('sheet-provider-dropdown'),
                        initialValue: selection.providerId,
                        isExpanded: true,
                        decoration: InputDecoration(
                          labelText: l10n.modelProvider,
                          border: const OutlineInputBorder(),
                        ),
                        items: [
                          for (final p in selection.providers)
                            DropdownMenuItem(value: p.id, child: Text(p.name)),
                        ],
                        onChanged: (id) {
                          if (id != null) {
                            ref
                                .read(modelSelectionProvider.notifier)
                                .selectProvider(id);
                          }
                        },
                      ),
                    ],
                    const SizedBox(height: 12),
                    TextField(
                      key: const Key('model-search'),
                      decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.search),
                        labelText: l10n.modelSearch,
                        border: const OutlineInputBorder(),
                      ),
                      onChanged: (value) => setState(() => _query = value),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: selection.loadingModels
                    ? const Center(child: CircularProgressIndicator())
                    : models.isEmpty
                    ? Center(child: Text(l10n.modelNoneAvailable))
                    : ListView.builder(
                        itemCount: models.length,
                        itemBuilder: (context, i) => _ModelRow(
                          model: models[i],
                          selection: selection,
                          confirmMode: widget.confirmLabel != null,
                        ),
                      ),
              ),
              if (widget.confirmLabel != null)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: FilledButton(
                    key: const Key('model-confirm'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                    ),
                    onPressed: selection.canAnalyze
                        ? () => Navigator.of(context).pop(true)
                        : null,
                    child: Text(widget.confirmLabel!),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ModelRow extends ConsumerWidget {
  const _ModelRow({
    required this.model,
    required this.selection,
    required this.confirmMode,
  });

  final ModelInfo model;
  final ModelSelection selection;
  final bool confirmMode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = model.id == selection.modelId;
    return ListTile(
      key: Key('model-${model.id}'),
      selected: selected,
      title: Text(model.name, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: model.name == model.id ? null : Text(model.id),
      trailing: VisionBadge(supportsVision: model.supportsVision),
      leading: Icon(
        selected ? Icons.radio_button_checked : Icons.radio_button_off,
      ),
      onTap: () async {
        await ref.read(modelSelectionProvider.notifier).selectModel(model.id);
        if (!confirmMode && context.mounted) {
          Navigator.of(context).pop(true);
        }
      },
    );
  }
}
