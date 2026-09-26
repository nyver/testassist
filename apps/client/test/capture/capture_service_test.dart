import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:test_assistant/core/di/providers.dart';
import 'package:test_assistant/features/capture/domain/capture_service.dart';

void main() {
  late Directory cache;
  late Directory elsewhere;
  late ProviderContainer container;

  setUp(() {
    cache = Directory.systemTemp.createTempSync('capture_cache_');
    elsewhere = Directory.systemTemp.createTempSync('capture_user_');
    container = ProviderContainer(
      overrides: [tempDirectoryProvider.overrideWithValue(cache)],
    );
  });

  tearDown(() {
    container.dispose();
    cache.deleteSync(recursive: true);
    elsewhere.deleteSync(recursive: true);
  });

  File writeJpeg(Directory dir, String name) {
    final image = img.Image(width: 64, height: 48);
    return File('${dir.path}${Platform.pathSeparator}$name')
      ..writeAsBytesSync(img.encodeJpg(image));
  }

  CaptureService service() => container.read(captureServiceProvider);

  group('prepare', () {
    test('deletes the original photo left in the cache', () async {
      final source = writeJpeg(cache, 'camera_photo.jpg');

      final prepared = await service().prepare(source.path);

      expect(source.existsSync(), isFalse, reason: 'the original is removed');
      expect(File(prepared.path).existsSync(), isTrue);
    });

    test('deletes the original even when it cannot be decoded', () async {
      final source = File('${cache.path}${Platform.pathSeparator}broken.jpg')
        ..writeAsStringSync('not an image');

      await expectLater(service().prepare(source.path), throwsException);

      expect(source.existsSync(), isFalse);
    });

    test('never deletes a file outside the cache', () async {
      final source = writeJpeg(elsewhere, 'user_photo.jpg');

      await service().prepare(source.path);

      expect(source.existsSync(), isTrue, reason: 'not ours to delete');
    });
  });

  test(
    'discard removes the prepared copy and tolerates a missing file',
    () async {
      final source = writeJpeg(cache, 'camera_photo.jpg');
      final prepared = await service().prepare(source.path);

      await service().discard(prepared);
      expect(File(prepared.path).existsSync(), isFalse);

      await service().discard(prepared); // already gone: must not throw
    },
  );
}
