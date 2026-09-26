import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import '../domain/ocr_service.dart';

/// ML Kit's bundled on-device recognizer for Latin script. It works offline.
///
/// NOTE: the Latin recognizer is not designed for Cyrillic. See
/// docs/architecture/ocr.md for the findings and the fallbacks (manual editing
/// and sending the image to a vision model).
class MlKitOcrService implements OcrService {
  MlKitOcrService()
    : _recognizer = TextRecognizer(script: TextRecognitionScript.latin);

  final TextRecognizer _recognizer;

  @override
  Future<String> recognize(String imagePath) async {
    final result = await _recognizer.processImage(
      InputImage.fromFilePath(imagePath),
    );
    return result.text;
  }

  @override
  Future<void> dispose() => _recognizer.close();
}
