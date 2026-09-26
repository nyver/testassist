import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../shared/l10n.dart';
import '../domain/device_services.dart';

/// Takes a photo. Camera access is requested here, when the user opens the
/// camera, and both denial and "don't ask again" are handled.
class CameraScreen extends ConsumerStatefulWidget {
  const CameraScreen({super.key});

  @override
  ConsumerState<CameraScreen> createState() => _CameraScreenState();
}

enum _Phase { requesting, ready, denied, permanentlyDenied, unavailable }

class _CameraScreenState extends ConsumerState<CameraScreen>
    with WidgetsBindingObserver {
  _Phase _phase = _Phase.requesting;
  CameraController? _controller;
  bool _capturing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _start();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    if (state == AppLifecycleState.inactive) {
      controller.dispose();
      _controller = null;
    } else if (state == AppLifecycleState.resumed &&
        _phase == _Phase.ready &&
        _controller == null) {
      _initCamera();
    }
  }

  Future<void> _start() async {
    setState(() => _phase = _Phase.requesting);
    final access = await ref.read(cameraPermissionServiceProvider).request();
    if (!mounted) return;
    switch (access) {
      case CameraAccess.granted:
        await _initCamera();
      case CameraAccess.denied:
        setState(() => _phase = _Phase.denied);
      case CameraAccess.permanentlyDenied:
        setState(() => _phase = _Phase.permanentlyDenied);
    }
  }

  Future<void> _initCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) throw CameraException('none', 'no camera');
      final back = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      final controller = CameraController(
        back,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _controller = controller;
        _phase = _Phase.ready;
      });
    } on CameraException catch (e) {
      if (!mounted) return;
      setState(() {
        _phase = switch (e.code) {
          'CameraAccessDenied' => _Phase.denied,
          'CameraAccessDeniedWithoutPrompt' ||
          'CameraAccessRestricted' => _Phase.permanentlyDenied,
          _ => _Phase.unavailable,
        };
      });
    }
  }

  Future<void> _capture() async {
    final controller = _controller;
    if (controller == null || _capturing) return;
    setState(() => _capturing = true);
    try {
      final file = await controller.takePicture();
      if (!mounted) return;
      context.pushReplacement('/crop', extra: file.path);
    } on CameraException {
      if (mounted) setState(() => _capturing = false);
    }
  }

  Future<void> _chooseImage() async {
    final path = await ref.read(imageSourcePickerProvider).pickFromGallery();
    if (path != null && mounted) {
      context.pushReplacement('/crop', extra: path);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.cameraTitle)),
      body: SafeArea(child: _body(context)),
    );
  }

  Widget _body(BuildContext context) {
    final l10n = context.l10n;
    switch (_phase) {
      case _Phase.requesting:
        return const Center(child: CircularProgressIndicator());
      case _Phase.ready:
        final controller = _controller;
        if (controller == null || !controller.value.isInitialized) {
          return const Center(child: CircularProgressIndicator());
        }
        return Column(
          children: [
            Expanded(child: Center(child: CameraPreview(controller))),
            Padding(
              padding: const EdgeInsets.all(16),
              child: FloatingActionButton.large(
                key: const Key('camera-capture'),
                tooltip: l10n.cameraCapture,
                onPressed: _capturing ? null : _capture,
                child: const Icon(Icons.camera_alt),
              ),
            ),
          ],
        );
      case _Phase.denied:
        return _Explanation(
          key: const Key('camera-denied'),
          message: l10n.cameraPermissionDenied,
          actions: [
            FilledButton(onPressed: _start, child: Text(l10n.actionRetry)),
            OutlinedButton(
              key: const Key('camera-choose-image'),
              onPressed: _chooseImage,
              child: Text(l10n.mainChooseImage),
            ),
          ],
        );
      case _Phase.permanentlyDenied:
        return _Explanation(
          key: const Key('camera-permanently-denied'),
          message: l10n.cameraPermissionPermanent,
          actions: [
            FilledButton(
              key: const Key('camera-open-settings'),
              onPressed: () =>
                  ref.read(cameraPermissionServiceProvider).openSettings(),
              child: Text(l10n.actionOpenSettings),
            ),
            OutlinedButton(
              key: const Key('camera-choose-image'),
              onPressed: _chooseImage,
              child: Text(l10n.mainChooseImage),
            ),
          ],
        );
      case _Phase.unavailable:
        return _Explanation(
          key: const Key('camera-unavailable'),
          message: l10n.cameraUnavailable,
          actions: [
            OutlinedButton(
              key: const Key('camera-choose-image'),
              onPressed: _chooseImage,
              child: Text(l10n.mainChooseImage),
            ),
          ],
        );
    }
  }
}

class _Explanation extends StatelessWidget {
  const _Explanation({super.key, required this.message, required this.actions});

  final String message;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.no_photography_outlined, size: 56),
              const SizedBox(height: 16),
              Text(
                context.l10n.cameraPermissionTitle,
                style: Theme.of(context).textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(message, textAlign: TextAlign.center),
              const SizedBox(height: 24),
              Wrap(spacing: 12, runSpacing: 12, children: actions),
            ],
          ),
        ),
      ),
    );
  }
}
