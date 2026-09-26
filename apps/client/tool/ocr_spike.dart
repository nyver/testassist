// OCR spike (task 9.5): runs the ML Kit Latin recognizer on sample photos on a
// device or emulator and prints what it reads, before and after the app's own
// preprocessing, plus what the question parser makes of it.
//
// Usage (see docs/architecture/ocr.md):
//   adb push <images> /data/local/tmp/spike/
//   adb shell run-as com.nyver.testassistant mkdir -p files/spike
//   adb shell run-as com.nyver.testassistant cp /data/local/tmp/spike/x.png files/spike/
//   flutter run -t tool/ocr_spike.dart -d <device>
//   adb logcat -s flutter
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:test_assistant/features/capture/data/image_processor.dart';
import 'package:test_assistant/features/ocr/data/mlkit_ocr_service.dart';
import 'package:test_assistant/features/ocr/domain/question_parser.dart';

const _dir = '/data/data/com.nyver.testassistant/files/spike';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    const MaterialApp(
      home: Scaffold(body: Center(child: Text('OCR spike'))),
    ),
  );

  final ocr = MlKitOcrService();
  const processor = ImageProcessor();
  const parser = QuestionParser();
  final out = Directory.systemTemp;

  final files =
      Directory(_dir)
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.png'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
  debugPrint('SPIKE: ${files.length} images');

  for (final file in files) {
    final name = p.basenameWithoutExtension(file.path);
    try {
      final prepared = await processor.prepare(
        sourcePath: file.path,
        outputPath: p.join(out.path, '$name.prepared.jpg'),
      );
      final processed = await processor.finalize(
        preparedPath: prepared.path,
        crop: const Rect.fromLTRB(0, 0, 1, 1),
        outputPath: p.join(out.path, '$name.final.jpg'),
        ocrOutputPath: p.join(out.path, '$name.ocr.jpg'),
      );
      final raw = await ocr.recognize(file.path);
      final pre = await ocr.recognize(processed.ocrPath);
      for (final (label, text) in [('raw', raw), ('preprocessed', pre)]) {
        final parsed = parser.parse(text);
        debugPrint('SPIKE[$name/$label] text=${text.replaceAll('\n', ' | ')}');
        debugPrint(
          'SPIKE[$name/$label] question="${parsed.question}" '
          'options=${parsed.options.map((o) => '${o.id}=${o.text}').join('; ')} '
          'lowQuality=${parsed.isLowQuality}',
        );
      }
    } on Object catch (e) {
      debugPrint('SPIKE[$name] failed: ${e.runtimeType}: $e');
    }
  }
  await ocr.dispose();
  debugPrint('SPIKE: done');
}
