import 'package:flutter/material.dart';

import '../../../shared/l10n.dart';

/// Shows the certificate fingerprint of [url] and returns true only when the
/// user taps "Trust". The text tells the user to compare it with the one the
/// server prints.
Future<bool> showTrustDialog(
  BuildContext context, {
  required String url,
  required String fingerprint,
}) async {
  final trusted = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (context) {
      final l10n = context.l10n;
      return AlertDialog(
        title: Text(l10n.trustDialogTitle),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.trustDialogBody(url)),
              const SizedBox(height: 16),
              Text(
                l10n.trustDialogFingerprint,
                style: Theme.of(context).textTheme.labelLarge,
              ),
              const SizedBox(height: 4),
              SelectableText(
                fingerprint,
                key: const Key('trust-fingerprint'),
                style: const TextStyle(fontFamily: 'monospace', fontSize: 15),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.actionCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.trustActionTrust),
          ),
        ],
      );
    },
  );
  return trusted ?? false;
}
