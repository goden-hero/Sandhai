import 'package:flutter/material.dart';

/// Keep failures visible even when a long form's inline error is above the fold.
void showOperationError(BuildContext context, String message) {
  final messenger = ScaffoldMessenger.of(context);
  messenger.clearSnackBars();
  messenger.showSnackBar(
    SnackBar(content: Text(message), duration: const Duration(seconds: 8)),
  );
}
