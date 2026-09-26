import 'dart:io';
import 'dart:ui' show Rect;

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:test_assistant/features/capture/data/image_processor.dart';

void main() {
  late Directory tmp;
  const processor = ImageProcessor();

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('image_processor_');
  });

  tearDown(() async {
    await tmp.delete(recursive: true);
  });

  String path(String name) => '${tmp.path}${Platform.pathSeparator}$name';

  /// Writes a JPEG whose left half is red and right half is blue, so cropping
  /// and rotation are visible in the pixels.
  String writeSource(
    String name,
    int width,
    int height, {
    int? exifOrientation,
    bool withGps = false,
  }) {
    final image = img.Image(width: width, height: height);
    for (final p in image) {
      p
        ..r = p.x < width / 2 ? 255 : 0
        ..g = 0
        ..b = p.x < width / 2 ? 0 : 255;
    }
    if (exifOrientation != null) {
      image.exif.imageIfd.orientation = exifOrientation;
    }
    if (withGps) {
      image.exif.imageIfd.make = 'TestPhone';
      image.exif.gpsIfd.gpsLatitude = 55.75;
      image.exif.gpsIfd.gpsLongitude = 37.62;
    }
    final file = File(path(name))
      ..writeAsBytesSync(img.encodeJpg(image, quality: 95));
    return file.path;
  }

  img.Image read(String p) => img.decodeJpg(File(p).readAsBytesSync())!;

  test('a 4000x3000 image becomes 2048x1536', () async {
    final source = writeSource('big.jpg', 4000, 3000);

    final prepared = await processor.prepare(
      sourcePath: source,
      outputPath: path('prepared.jpg'),
    );

    expect(prepared.width, 2048);
    expect(prepared.height, 1536);
    final decoded = read(prepared.path);
    expect((decoded.width, decoded.height), (2048, 1536));
  });

  test('a small image is never upscaled', () async {
    final source = writeSource('small.jpg', 800, 600);
    final prepared = await processor.prepare(
      sourcePath: source,
      outputPath: path('prepared.jpg'),
    );
    expect((prepared.width, prepared.height), (800, 600));
  });

  test('a portrait image is limited by its height', () async {
    final source = writeSource('tall.jpg', 3000, 4000);
    final prepared = await processor.prepare(
      sourcePath: source,
      outputPath: path('prepared.jpg'),
    );
    expect((prepared.width, prepared.height), (1536, 2048));
  });

  test('EXIF orientation "rotate 90" produces an upright image', () async {
    // Stored as 400x200 with orientation 6 (rotate 90 degrees clockwise):
    // the upright image is 200x400.
    final source = writeSource('rotated.jpg', 400, 200, exifOrientation: 6);

    final prepared = await processor.prepare(
      sourcePath: source,
      outputPath: path('prepared.jpg'),
    );

    expect((prepared.width, prepared.height), (200, 400));
    final decoded = read(prepared.path);
    expect((decoded.width, decoded.height), (200, 400));
    // Upright means no pending orientation is left in the output.
    final orientation = decoded.exif.imageIfd.orientation;
    expect(orientation == null || orientation == 1, isTrue);
    // The red left half of the original is now the top half.
    final top = decoded.getPixel(100, 20);
    final bottom = decoded.getPixel(100, 380);
    expect(top.r > 200 && top.b < 60, isTrue, reason: 'top should be red');
    expect(bottom.b > 200 && bottom.r < 60, isTrue, reason: 'bottom is blue');
  });

  test('no EXIF metadata such as GPS survives in any output', () async {
    final source = writeSource(
      'gps.jpg',
      600,
      400,
      exifOrientation: 6,
      withGps: true,
    );
    // Guard the premise: the source really carries the metadata.
    expect(read(source).exif.gpsIfd.gpsLatitude, isNotNull);

    final prepared = await processor.prepare(
      sourcePath: source,
      outputPath: path('prepared.jpg'),
    );
    final processed = await processor.finalize(
      preparedPath: prepared.path,
      crop: const Rect.fromLTRB(0, 0, 1, 1),
      outputPath: path('final.jpg'),
      ocrOutputPath: path('ocr.jpg'),
    );

    for (final output in [prepared.path, processed.path, processed.ocrPath]) {
      expect(read(output).exif.isEmpty, isTrue, reason: '$output has EXIF');
    }
  });

  test('cropping keeps only the selected area', () async {
    final source = writeSource('img.jpg', 1000, 500);
    final prepared = await processor.prepare(
      sourcePath: source,
      outputPath: path('prepared.jpg'),
    );

    // The right half of the image (blue).
    final processed = await processor.finalize(
      preparedPath: prepared.path,
      crop: const Rect.fromLTRB(0.5, 0.0, 1.0, 1.0),
      outputPath: path('final.jpg'),
      ocrOutputPath: path('ocr.jpg'),
    );

    expect((processed.width, processed.height), (500, 500));
    final decoded = read(processed.path);
    final center = decoded.getPixel(250, 250);
    expect(center.b > 200 && center.r < 60, isTrue);
  });

  test('the OCR copy is a separate grayscale image', () async {
    final source = writeSource('img.jpg', 600, 400);
    final prepared = await processor.prepare(
      sourcePath: source,
      outputPath: path('prepared.jpg'),
    );
    final processed = await processor.finalize(
      preparedPath: prepared.path,
      crop: const Rect.fromLTRB(0, 0, 1, 1),
      outputPath: path('final.jpg'),
      ocrOutputPath: path('ocr.jpg'),
    );

    expect(processed.ocrPath, isNot(processed.path));
    final color = read(processed.path).getPixel(100, 100);
    expect(
      (color.r - color.b).abs() > 100,
      isTrue,
      reason: 'the stored image keeps its colors',
    );
    final gray = read(processed.ocrPath).getPixel(100, 100);
    expect(
      (gray.r - gray.g).abs() < 8 && (gray.g - gray.b).abs() < 8,
      isTrue,
      reason: 'the OCR copy is grayscale',
    );
  });

  test('cropping a large image still respects the size limit', () async {
    final source = writeSource('huge.jpg', 5000, 3000);
    final prepared = await processor.prepare(
      sourcePath: source,
      outputPath: path('prepared.jpg'),
    );
    final processed = await processor.finalize(
      preparedPath: prepared.path,
      crop: const Rect.fromLTRB(0, 0, 1, 1),
      outputPath: path('final.jpg'),
      ocrOutputPath: path('ocr.jpg'),
    );
    expect(processed.width <= maxImageSide, isTrue);
    expect(processed.height <= maxImageSide, isTrue);
  });

  test('degenerate and out-of-range crops do not crash', () async {
    final source = writeSource('img.jpg', 300, 200);
    final prepared = await processor.prepare(
      sourcePath: source,
      outputPath: path('prepared.jpg'),
    );
    for (final crop in const [
      Rect.fromLTRB(0.5, 0.5, 0.5, 0.5),
      Rect.fromLTRB(-1, -1, 2, 2),
      Rect.fromLTRB(0.99, 0.99, 1, 1),
    ]) {
      final processed = await processor.finalize(
        preparedPath: prepared.path,
        crop: crop,
        outputPath: path('final.jpg'),
        ocrOutputPath: path('ocr.jpg'),
      );
      expect(processed.width >= 1 && processed.height >= 1, isTrue);
    }
  });

  test('an undecodable file is reported, not swallowed', () async {
    final bad = File(path('bad.jpg'))..writeAsStringSync('not an image');
    await expectLater(
      processor.prepare(sourcePath: bad.path, outputPath: path('out.jpg')),
      throwsA(isA<ImageProcessingException>()),
    );
  });
}
