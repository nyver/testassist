import 'dart:io';
import 'dart:ui' show Rect;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../../core/di/providers.dart';
import '../../ocr/data/mlkit_ocr_service.dart';
import '../../ocr/domain/ocr_service.dart';
import '../../questions/domain/draft_controller.dart';
import '../data/image_processor.dart';

/// Creates the OCR engine for one recognition. The engine is closed right
/// after use, so it never outlives the capture that needed it.
final ocrServiceFactoryProvider = Provider<OcrService Function()>(
  (ref) => MlKitOcrService.new,
);

final imageProcessorProvider = Provider<ImageProcessor>(
  (ref) => const ImageProcessor(),
);

final captureServiceProvider = Provider<CaptureService>(CaptureService.new);

/// Turns a photo or a gallery image into a draft: orientation and downscale,
/// crop, on-device OCR and parsing.
class CaptureService {
  CaptureService(this._ref);

  final Ref _ref;

  /// Applies the orientation and downscales, for the crop screen. The result
  /// lives in the cache directory.
  ///
  /// The original is deleted afterwards: the camera and the image picker leave
  /// a full-resolution copy, with its EXIF metadata, in the cache, and it would
  /// otherwise outlive "Delete images after analysis". Only files inside the
  /// cache are touched, never an image the user owns elsewhere.
  Future<PreparedImage> prepare(String sourcePath) async {
    final tmp = _ref.read(tempDirectoryProvider);
    try {
      return await _ref
          .read(imageProcessorProvider)
          .prepare(
            sourcePath: sourcePath,
            outputPath: p.join(tmp.path, 'prepared_${_stamp()}.jpg'),
          );
    } finally {
      if (p.isWithin(tmp.path, sourcePath)) {
        await _deleteQuietly(File(sourcePath));
      }
    }
  }

  /// Deletes the cache file of a prepared image that will not be used, for
  /// example when the user leaves the crop screen.
  Future<void> discard(PreparedImage prepared) =>
      _deleteQuietly(File(prepared.path));

  /// Crops, stores the final image, runs OCR on the contrast-normalized copy
  /// and starts a new draft with the result. Returns false when OCR failed, in
  /// which case the draft still exists with empty text for manual entry.
  Future<bool> complete({
    required PreparedImage prepared,
    required Rect crop,
  }) async {
    final images = _ref.read(imageStoreProvider);
    final tmp = _ref.read(tempDirectoryProvider);
    final stored = await images.create();
    final ocrCopy = File(p.join(tmp.path, 'ocr_${_stamp()}.jpg'));

    try {
      final processed = await _ref
          .read(imageProcessorProvider)
          .finalize(
            preparedPath: prepared.path,
            crop: crop,
            outputPath: stored.file.path,
            ocrOutputPath: ocrCopy.path,
          );

      var ocrOk = true;
      var text = '';
      final ocr = _ref.read(ocrServiceFactoryProvider)();
      try {
        text = await ocr.recognize(processed.ocrPath);
      } on Object {
        ocrOk = false; // Let the user type the question instead.
      } finally {
        await ocr.dispose();
      }

      await _ref
          .read(draftControllerProvider.notifier)
          .startNew(imagePath: stored.relativePath, ocrText: text);
      return ocrOk;
    } on Object {
      await images.delete(stored.relativePath);
      rethrow;
    } finally {
      await _deleteQuietly(File(prepared.path));
      await _deleteQuietly(ocrCopy);
    }
  }

  Future<void> _deleteQuietly(File file) async {
    try {
      await file.delete();
    } on FileSystemException {
      // Best effort: it is a cache file.
    }
  }

  String _stamp() => DateTime.now().microsecondsSinceEpoch.toString();
}
