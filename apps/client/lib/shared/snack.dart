import 'package:flutter/material.dart';

/// Shows a short message, replacing any message that is still visible or
/// queued, so an outdated notice never delays the current one.
void showMessage(ScaffoldMessengerState messenger, String text) {
  messenger
    ..clearSnackBars()
    ..showSnackBar(SnackBar(content: Text(text)));
}
