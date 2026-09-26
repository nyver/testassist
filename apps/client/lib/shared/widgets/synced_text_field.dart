import 'package:flutter/material.dart';

/// A text field whose content is owned by external state.
///
/// It keeps its own controller (so the cursor does not jump while typing) and
/// adopts [value] when the state changes it from outside, for example after
/// "Parse again" or when options are reordered.
class SyncedTextField extends StatefulWidget {
  const SyncedTextField({
    super.key,
    required this.value,
    required this.onChanged,
    this.decoration,
    this.minLines,
    this.maxLines = 1,
    this.enabled = true,
    this.textInputAction,
  });

  final String value;
  final ValueChanged<String> onChanged;
  final InputDecoration? decoration;
  final int? minLines;
  final int? maxLines;
  final bool enabled;
  final TextInputAction? textInputAction;

  @override
  State<SyncedTextField> createState() => _SyncedTextFieldState();
}

class _SyncedTextFieldState extends State<SyncedTextField> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.value,
  );

  @override
  void didUpdateWidget(SyncedTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != _controller.text) {
      _controller.value = TextEditingValue(
        text: widget.value,
        selection: TextSelection.collapsed(offset: widget.value.length),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      enabled: widget.enabled,
      minLines: widget.minLines,
      maxLines: widget.maxLines,
      textInputAction: widget.textInputAction,
      decoration: widget.decoration,
      onChanged: widget.onChanged,
    );
  }
}
