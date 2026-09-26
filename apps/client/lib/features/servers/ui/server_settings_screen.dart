import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/di/providers.dart';
import '../../../core/errors/app_failure.dart';
import '../../../shared/dialogs.dart';
import '../../../shared/failure_messages.dart';
import '../../../shared/l10n.dart';
import '../../../shared/snack.dart';
import '../domain/server_service.dart';
import 'trust_dialog.dart';

/// Shows the configured server and offers the trust and token actions.
class ServerSettingsScreen extends ConsumerWidget {
  const ServerSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final session = ref.watch(serverSessionProvider).value;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.serverSettingsTitle)),
      body: SafeArea(
        child: session == null
            ? const SizedBox.shrink()
            : ListView(
                children: [
                  _Field(
                    label: l10n.serverFieldName,
                    value: session.record.name,
                    trailing: IconButton(
                      key: const Key('server-rename'),
                      tooltip: l10n.serverEditName,
                      icon: const Icon(Icons.edit),
                      onPressed: () =>
                          _rename(context, ref, session.record.name),
                    ),
                  ),
                  _Field(
                    label: l10n.serverFieldUrl,
                    value: session.record.baseUrl.toString(),
                  ),
                  _Field(
                    label: l10n.serverFieldId,
                    value: session.record.serverId,
                  ),
                  _Field(
                    label: l10n.serverFieldFingerprint,
                    value:
                        session.pinnedFingerprint ?? l10n.serverFingerprintNone,
                    monospace: session.pinnedFingerprint != null,
                  ),
                  const Divider(),
                  ListTile(
                    key: const Key('server-replace-token'),
                    leading: const Icon(Icons.key),
                    title: Text(l10n.serverReplaceToken),
                    onTap: () => _replaceToken(context, ref),
                  ),
                  ListTile(
                    key: const Key('server-reset-trust'),
                    leading: const Icon(Icons.verified_user_outlined),
                    title: Text(l10n.serverResetTrust),
                    onTap: () => _resetTrust(context, ref),
                  ),
                  ListTile(
                    key: const Key('server-remove'),
                    leading: Icon(
                      Icons.delete_outline,
                      color: Theme.of(context).colorScheme.error,
                    ),
                    title: Text(
                      l10n.serverRemove,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                    onTap: () => _remove(context, ref),
                  ),
                ],
              ),
      ),
    );
  }

  Future<void> _rename(
    BuildContext context,
    WidgetRef ref,
    String current,
  ) async {
    final l10n = context.l10n;
    final name = await textInputDialog(
      context,
      title: l10n.serverEditName,
      label: l10n.serverFieldName,
      initialValue: current,
    );
    if (name == null || name.isEmpty) return;
    await ref.read(serverServiceProvider).rename(name);
  }

  Future<void> _replaceToken(BuildContext context, WidgetRef ref) async {
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    final token = await textInputDialog(
      context,
      title: l10n.serverReplaceToken,
      label: l10n.serverNewTokenLabel,
      obscure: true,
    );
    if (token == null || token.isEmpty) return;

    final failure = await ref.read(serverServiceProvider).replaceToken(token);
    final String message;
    if (failure == null) {
      message = l10n.serverTokenReplaced;
    } else if (failure is ApiFailure &&
        failure.code == ApiErrorCodes.unauthorized) {
      message = l10n.setupTokenInvalid;
    } else {
      message = failureMessage(l10n, failure);
    }
    showMessage(messenger, message);
  }

  Future<void> _resetTrust(BuildContext context, WidgetRef ref) async {
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    final url = ref
        .read(serverSessionProvider)
        .value
        ?.record
        .baseUrl
        .toString();
    final confirmed = await confirmDialog(
      context,
      message: l10n.serverResetTrustConfirm,
      confirmLabel: l10n.actionContinue,
    );
    if (!confirmed || url == null || !context.mounted) return;

    final outcome = await ref.read(serverServiceProvider).resetTrust((
      fingerprint,
    ) async {
      if (!context.mounted) return false;
      return showTrustDialog(context, url: url, fingerprint: fingerprint);
    });
    switch (outcome) {
      case SetupSuccess():
        showMessage(messenger, l10n.serverResetTrustDone);
      case SetupCancelled():
        break;
      case SetupError(:final failure):
        showMessage(messenger, failureMessage(l10n, failure));
    }
  }

  Future<void> _remove(BuildContext context, WidgetRef ref) async {
    final l10n = context.l10n;
    final confirmed = await confirmDialog(
      context,
      message: l10n.serverRemoveConfirm,
      confirmLabel: l10n.actionRemove,
    );
    if (!confirmed) return;
    await ref.read(serverServiceProvider).remove();
    if (context.mounted) context.go('/setup');
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.label,
    required this.value,
    this.trailing,
    this.monospace = false,
  });

  final String label;
  final String value;
  final Widget? trailing;
  final bool monospace;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(label, style: Theme.of(context).textTheme.labelMedium),
      subtitle: SelectableText(
        value,
        style: monospace ? const TextStyle(fontFamily: 'monospace') : null,
      ),
      trailing: trailing,
    );
  }
}
