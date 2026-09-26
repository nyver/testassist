import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/errors/app_failure.dart';
import '../../../shared/failure_messages.dart';
import '../../../shared/l10n.dart';
import '../domain/analyze_controller.dart';

/// Reacts to analysis results for the screen that started them: opens the
/// result on success and shows an actionable message on failure. Call from
/// `build`.
///
/// [onRetry] repeats the request. [onSendTextOnly] is offered when the server
/// refused an image for a text-only model.
void listenToAnalysis(
  BuildContext context,
  WidgetRef ref, {
  required VoidCallback onRetry,
  VoidCallback? onSendTextOnly,
}) {
  ref.listen<AnalyzeState>(analyzeControllerProvider, (previous, next) {
    final controller = ref.read(analyzeControllerProvider.notifier);
    final messenger = ScaffoldMessenger.of(context);
    final l10n = context.l10n;

    switch (next) {
      case AnalyzeSucceeded(:final entryId):
        // The state is left as it is: screens that lost their draft to this
        // success must not mistake it for "nothing to do" and go home.
        context.go('/result/$entryId');
      case AnalyzeFailed(:final failure):
        controller.reset();
        messenger.hideCurrentSnackBar();
        final hint = failureHint(l10n, failure);
        final message = hint == null
            ? failureMessage(l10n, failure)
            : '${failureMessage(l10n, failure)}\n$hint';

        SnackBarAction? action;
        if (failure is ApiFailure &&
            failure.code == ApiErrorCodes.modelNoVision &&
            onSendTextOnly != null) {
          action = SnackBarAction(
            label: l10n.actionSendTextOnly,
            onPressed: onSendTextOnly,
          );
        } else if (failure is! CancelledFailure &&
            failureIsRetryable(failure)) {
          action = SnackBarAction(label: l10n.actionRetry, onPressed: onRetry);
        }
        messenger.showSnackBar(
          SnackBar(
            key: const Key('analyze-error'),
            content: Text(message),
            action: action,
            duration: const Duration(seconds: 8),
          ),
        );
      case AnalyzeIdle():
      case AnalyzeRunning():
        break;
    }
  });
}

/// A blocking progress layer with a cancel action, shown while a request runs.
/// Place it on top of the screen content in a [Stack].
class AnalyzeProgressOverlay extends ConsumerWidget {
  const AnalyzeProgressOverlay({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final running = ref.watch(
      analyzeControllerProvider.select((s) => s is AnalyzeRunning),
    );
    if (!running) return const SizedBox.shrink();

    final l10n = context.l10n;
    return Positioned.fill(
      child: Stack(
        children: [
          const ModalBarrier(dismissible: false, color: Colors.black54),
          Center(
            child: Card(
              key: const Key('analyze-progress'),
              margin: const EdgeInsets.all(24),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(),
                    const SizedBox(height: 16),
                    Text(l10n.recognitionAnalyzing),
                    const SizedBox(height: 16),
                    OutlinedButton(
                      key: const Key('analyze-cancel'),
                      onPressed: () =>
                          ref.read(analyzeControllerProvider.notifier).cancel(),
                      child: Text(l10n.recognitionCancelRequest),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
