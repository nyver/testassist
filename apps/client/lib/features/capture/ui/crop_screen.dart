import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../shared/l10n.dart';
import '../data/image_processor.dart';
import '../domain/capture_service.dart';
import 'crop_overlay.dart';

/// Shows the oriented photo, lets the user crop it, then runs OCR and opens the
/// recognition screen. Processing runs in an isolate; the UI stays responsive.
class CropScreen extends ConsumerStatefulWidget {
  const CropScreen({super.key, required this.sourcePath});

  final String sourcePath;

  @override
  ConsumerState<CropScreen> createState() => _CropScreenState();
}

class _CropScreenState extends ConsumerState<CropScreen> {
  final _overlayKey = GlobalKey<CropOverlayState>();

  // Read once: `ref` must not be used while the widget is being disposed.
  late final CaptureService _capture = ref.read(captureServiceProvider);

  PreparedImage? _prepared;
  Rect _selection = const Rect.fromLTRB(0, 0, 1, 1);
  bool _working = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _prepare();
  }

  @override
  void dispose() {
    // A confirmed crop already consumed the file; this is then a no-op. When
    // the user leaves without confirming, it removes the leftover cache copy.
    final prepared = _prepared;
    if (prepared != null) unawaited(_capture.discard(prepared));
    super.dispose();
  }

  Future<void> _prepare() async {
    try {
      final prepared = await _capture.prepare(widget.sourcePath);
      if (!mounted) {
        // Left before the processing finished: nobody will use the result.
        unawaited(_capture.discard(prepared));
        return;
      }
      setState(() => _prepared = prepared);
    } on Object {
      if (!mounted) return;
      setState(() => _failed = true);
    }
  }

  Future<void> _confirm(Rect crop) async {
    final prepared = _prepared;
    if (prepared == null || _working) return;
    setState(() => _working = true);
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);

    try {
      final ocrOk = await _capture.complete(prepared: prepared, crop: crop);
      if (!mounted) return;
      if (!ocrOk) {
        messenger.showSnackBar(SnackBar(content: Text(l10n.errorOcrFailed)));
      }
      router.go('/recognition');
    } on Object {
      if (!mounted) return;
      setState(() => _working = false);
      messenger.showSnackBar(SnackBar(content: Text(l10n.errorImageFailed)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final prepared = _prepared;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.cropTitle)),
      body: SafeArea(
        child: _failed
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    l10n.errorImageFailed,
                    textAlign: TextAlign.center,
                  ),
                ),
              )
            : prepared == null
            ? _Busy(label: l10n.cropProcessing)
            : Stack(
                children: [
                  Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(l10n.cropHint),
                      ),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: CropOverlay(
                            key: _overlayKey,
                            image: FileImage(File(prepared.path)),
                            imageAspectRatio: prepared.width / prepared.height,
                            onChanged: (rect) => _selection = rect,
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          alignment: WrapAlignment.center,
                          children: [
                            OutlinedButton(
                              key: const Key('crop-whole'),
                              onPressed: _working
                                  ? null
                                  : () => _overlayKey.currentState?.reset(),
                              child: Text(l10n.cropWholeImage),
                            ),
                            FilledButton(
                              key: const Key('crop-confirm'),
                              onPressed: _working
                                  ? null
                                  : () => _confirm(_selection),
                              child: Text(l10n.cropConfirm),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  if (_working) _Busy(label: l10n.recognitionOcrRunning),
                ],
              ),
      ),
    );
  }
}

class _Busy extends StatelessWidget {
  const _Busy({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.85),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(label),
          ],
        ),
      ),
    );
  }
}
