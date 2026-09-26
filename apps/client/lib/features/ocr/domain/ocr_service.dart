/// On-device text recognition. The image never leaves the device.
abstract interface class OcrService {
  /// Recognizes the text of the image at [imagePath]. The result is raw and
  /// unchanged, for later editing and history.
  Future<String> recognize(String imagePath);

  /// Releases the recognizer.
  Future<void> dispose();
}
