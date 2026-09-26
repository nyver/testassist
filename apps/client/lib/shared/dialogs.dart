import 'package:flutter/material.dart';

import 'l10n.dart';

/// Asks the user to confirm an action. Returns true only on confirmation.
Future<bool> confirmDialog(
  BuildContext context, {
  required String message,
  required String confirmLabel,
  String? title,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: title == null ? null : Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(context.l10n.actionCancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return result ?? false;
}

/// Asks for one line of text. Returns null when cancelled.
Future<String?> textInputDialog(
  BuildContext context, {
  required String title,
  required String label,
  String initialValue = '',
  bool obscure = false,
}) {
  return showDialog<String>(
    context: context,
    builder: (context) => _TextInputDialog(
      title: title,
      label: label,
      initialValue: initialValue,
      obscure: obscure,
    ),
  );
}

class _TextInputDialog extends StatefulWidget {
  const _TextInputDialog({
    required this.title,
    required this.label,
    required this.initialValue,
    required this.obscure,
  });

  final String title;
  final String label;
  final String initialValue;
  final bool obscure;

  @override
  State<_TextInputDialog> createState() => _TextInputDialogState();
}

class _TextInputDialogState extends State<_TextInputDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialValue,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        obscureText: widget.obscure,
        autocorrect: false,
        enableSuggestions: !widget.obscure,
        decoration: InputDecoration(labelText: widget.label),
        onSubmitted: (value) => Navigator.of(context).pop(value.trim()),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.l10n.actionCancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_controller.text.trim()),
          child: Text(context.l10n.actionSave),
        ),
      ],
    );
  }
}
