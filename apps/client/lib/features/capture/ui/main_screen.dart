import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/di/providers.dart';
import '../../../core/errors/app_failure.dart';
import '../../../shared/failure_messages.dart';
import '../../../shared/l10n.dart';
import '../../servers/domain/server_status.dart';
import '../domain/device_services.dart';

/// The home screen: the four actions and the state of the server.
class MainScreen extends ConsumerWidget {
  const MainScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final session = ref.watch(serverSessionProvider).value;
    final status = ref.watch(serverStatusProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(session?.record.name ?? l10n.appTitle),
        actions: [
          IconButton(
            key: const Key('main-server-settings'),
            tooltip: l10n.settingsServer,
            icon: const Icon(Icons.dns_outlined),
            onPressed: () => context.push('/settings/server'),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: ListView(
              padding: const EdgeInsets.all(16),
              shrinkWrap: true,
              children: [
                if (status.value != null) _ServerBanner(failure: status.value!),
                _ActionButton(
                  key: const Key('main-take-photo'),
                  icon: Icons.photo_camera,
                  label: l10n.mainTakePhoto,
                  filled: true,
                  onPressed: () => context.push('/camera'),
                ),
                _ActionButton(
                  key: const Key('main-choose-image'),
                  icon: Icons.photo_library,
                  label: l10n.mainChooseImage,
                  onPressed: () => _chooseImage(context, ref),
                ),
                _ActionButton(
                  key: const Key('main-history'),
                  icon: Icons.history,
                  label: l10n.mainHistory,
                  onPressed: () => context.push('/history'),
                ),
                _ActionButton(
                  key: const Key('main-settings'),
                  icon: Icons.settings,
                  label: l10n.mainSettings,
                  onPressed: () => context.push('/settings'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _chooseImage(BuildContext context, WidgetRef ref) async {
    final path = await ref.read(imageSourcePickerProvider).pickFromGallery();
    if (path != null && context.mounted) {
      await context.push('/crop', extra: path);
    }
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.filled = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final style = ButtonStyle(
      minimumSize: const WidgetStatePropertyAll(Size.fromHeight(64)),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: filled
          ? FilledButton.icon(
              onPressed: onPressed,
              style: style,
              icon: Icon(icon),
              label: Text(label),
            )
          : FilledButton.tonalIcon(
              onPressed: onPressed,
              style: style,
              icon: Icon(icon),
              label: Text(label),
            ),
    );
  }
}

class _ServerBanner extends StatelessWidget {
  const _ServerBanner({required this.failure});

  final AppFailure failure;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final hint = failureHint(l10n, failure);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Card(
        key: const Key('server-banner'),
        color: Theme.of(context).colorScheme.errorContainer,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(failureMessage(l10n, failure)),
              if (hint != null) ...[const SizedBox(height: 4), Text(hint)],
            ],
          ),
        ),
      ),
    );
  }
}
