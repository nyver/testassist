import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' show Rect;

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// Longest side, in pixels, of the stored and uploaded image.
const maxImageSide = 2048;

/// JPEG quality of the stored and uploaded image.
const storedJpegQuality = 85;

/// Thrown when an image cannot be decoded or encoded. The UI shows a localized
/// message; the text here is for logs only.
class ImageProcessingException implements Exception {
  const ImageProcessingException(this.message);

  final String message;

  @override
  String toString() => 'ImageProcessingException: $message';
}

/// The result of [ImageProcessor.prepare].
@immutable
class PreparedImage {
  const PreparedImage({
    required this.path,
    required this.width,
    required this.height,
  });

  final String path;
  final int width;
  final int height;
}

/// The result of [ImageProcessor.finalize].
@immutable
class ProcessedImage {
  const ProcessedImage({
    required this.path,
    required this.ocrPath,
    required this.width,
    required this.height,
  });

  /// The oriented, cropped, downscaled JPEG that is stored and uploaded.
  final String path;

  /// A grayscale, contrast-normalized copy used only for OCR.
  final String ocrPath;
  final int width;
  final int height;
}

/// Image preparation. All decoding, resizing and encoding runs in a separate
/// isolate, so the UI thread is never blocked.
class ImageProcessor {
  const ImageProcessor();

  /// Applies the EXIF orientation and downscales so the longer side is at
  /// most [maxImageSide]. The result is what the crop screen shows.
  Future<PreparedImage> prepare({
    required String sourcePath,
    required String outputPath,
  }) => compute(_prepare, _PrepareArgs(sourcePath, outputPath));

  /// Crops the prepared image to [crop] (fractions of its width and height),
  /// keeps the longer side within [maxImageSide], writes the JPEG that is
  /// stored and uploaded to [outputPath], and writes a contrast-normalized
  /// grayscale copy for OCR to [ocrOutputPath].
  Future<ProcessedImage> finalize({
    required String preparedPath,
    required Rect crop,
    required String outputPath,
    required String ocrOutputPath,
  }) => compute(
    _finalize,
    _FinalizeArgs(preparedPath, crop, outputPath, ocrOutputPath),
  );
}

class _PrepareArgs {
  const _PrepareArgs(this.source, this.output);

  final String source;
  final String output;
}

class _FinalizeArgs {
  const _FinalizeArgs(this.prepared, this.crop, this.output, this.ocrOutput);

  final String prepared;
  final Rect crop;
  final String output;
  final String ocrOutput;
}

img.Image _decode(String path) {
  final bytes = File(path).readAsBytesSync();
  final image = img.decodeImage(bytes);
  if (image == null) {
    throw const ImageProcessingException('unsupported or corrupt image');
  }
  return image;
}

img.Image _downscale(img.Image image) {
  final longest = math.max(image.width, image.height);
  if (longest <= maxImageSide) return image;
  final scale = maxImageSide / longest;
  return img.copyResize(
    image,
    width: math.max(1, (image.width * scale).round()),
    height: math.max(1, (image.height * scale).round()),
    interpolation: img.Interpolation.average,
  );
}

void _writeJpeg(
  String path,
  img.Image image, {
  int quality = storedJpegQuality,
}) {
  // Camera photos carry GPS position, timestamps and the device model in EXIF.
  // The orientation is already baked into the pixels, and the file is uploaded
  // to a third-party model, so nothing of that metadata is written out.
  image.exif = img.ExifData();
  File(path).writeAsBytesSync(img.encodeJpg(image, quality: quality));
}

PreparedImage _prepare(_PrepareArgs args) {
  // bakeOrientation rotates the pixels and clears the EXIF orientation, so the
  // preview, the OCR input and the uploaded image are all upright.
  final upright = img.bakeOrientation(_decode(args.source));
  final scaled = _downscale(upright);
  _writeJpeg(args.output, scaled);
  return PreparedImage(
    path: args.output,
    width: scaled.width,
    height: scaled.height,
  );
}

ProcessedImage _finalize(_FinalizeArgs args) {
  final source = _decode(args.prepared);

  final left = (args.crop.left.clamp(0.0, 1.0) * source.width).round();
  final top = (args.crop.top.clamp(0.0, 1.0) * source.height).round();
  final right = (args.crop.right.clamp(0.0, 1.0) * source.width).round();
  final bottom = (args.crop.bottom.clamp(0.0, 1.0) * source.height).round();
  final width = math.max(1, right - left);
  final height = math.max(1, bottom - top);

  final cropped = img.copyCrop(
    source,
    x: math.min(left, source.width - 1),
    y: math.min(top, source.height - 1),
    width: math.min(width, source.width - math.min(left, source.width - 1)),
    height: math.min(height, source.height - math.min(top, source.height - 1)),
  );
  final result = _downscale(cropped);
  _writeJpeg(args.output, result);

  // OCR copy: grayscale with the tonal range stretched to the full scale.
  final ocr = img.normalize(img.grayscale(result.clone()), min: 0, max: 255);
  _writeJpeg(args.ocrOutput, ocr, quality: 90);

  return ProcessedImage(
    path: args.output,
    ocrPath: args.ocrOutput,
    width: result.width,
    height: result.height,
  );
}
