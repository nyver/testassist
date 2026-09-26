import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../shared/l10n.dart';
import '../domain/app_settings.dart';
import '../domain/settings_controller.dart';

/// Display mode, image retention and the link to the server settings.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final settings = ref.watch(settingsControllerProvider);
    final controller = ref.read(settingsControllerProvider.notifier);

    String label(AnswerDisplayMode mode) => switch (mode) {
      AnswerDisplayMode.optionOnly => l10n.settingsModeOptionOnly,
      AnswerDisplayMode.short => l10n.settingsModeShort,
      AnswerDisplayMode.detailed => l10n.settingsModeDetailed,
    };

    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsTitle)),
      body: SafeArea(
        child: ListView(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: Text(
                l10n.settingsAnswerMode,
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
            RadioGroup<AnswerDisplayMode>(
              groupValue: settings.displayMode,
              onChanged: (mode) {
                if (mode != null) controller.setDisplayMode(mode);
              },
              child: Column(
                children: [
                  for (final mode in AnswerDisplayMode.values)
                    RadioListTile<AnswerDisplayMode>(
                      key: Key('mode-${mode.name}'),
                      value: mode,
                      title: Text(label(mode)),
                    ),
                ],
              ),
            ),
            const Divider(),
            SwitchListTile(
              key: const Key('delete-images-switch'),
              title: Text(l10n.settingsDeleteImages),
              subtitle: Text(l10n.settingsDeleteImagesHint),
              value: settings.deleteImagesAfterAnalysis,
              onChanged: (value) =>
                  controller.setDeleteImagesAfterAnalysis(value: value),
            ),
            const Divider(),
            ListTile(
              key: const Key('settings-server'),
              leading: const Icon(Icons.dns_outlined),
              title: Text(l10n.settingsServer),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/settings/server'),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                l10n.settingsLanguageNote,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
