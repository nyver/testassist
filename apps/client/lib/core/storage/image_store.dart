import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;

/// An image file inside the app-private image directory.
class StoredImage {
  const StoredImage({required this.relativePath, required this.file});

  /// Path relative to the storage root, always `images/<name>.jpg`. This is
  /// what the database stores.
  final String relativePath;
  final File file;
}

/// Owns the app-private `images/` directory. Images are files referenced by
/// relative path from the database, never blobs and never in secure storage.
class ImageStore {
  ImageStore(this.root) : _random = Random.secure();

  /// The app-private base directory (application documents).
  final Directory root;
  final Random _random;

  static const _dirName = 'images';

  Directory get imagesDir => Directory(p.join(root.path, _dirName));

  /// Reserves a new, unused file name. The file itself is created by the
  /// caller.
  Future<StoredImage> create() async {
    await imagesDir.create(recursive: true);
    final name = '${_randomName()}.jpg';
    return StoredImage(
      relativePath: '$_dirName/$name',
      file: File(p.join(imagesDir.path, name)),
    );
  }

  /// Resolves a stored relative path to a file. Returns null for a path that
  /// does not point into the image directory, so a tampered database value
  /// cannot reach other files.
  File? resolve(String? relativePath) {
    if (relativePath == null) return null;
    final parts = p.posix.split(relativePath);
    if (parts.length != 2 ||
        parts[0] != _dirName ||
        parts[1].isEmpty ||
        parts[1] == '.' ||
        parts[1] == '..' ||
        parts[1].contains('\\')) {
      return null;
    }
    return File(p.join(imagesDir.path, parts[1]));
  }

  /// Whether the file of [relativePath] exists.
  Future<bool> exists(String? relativePath) async {
    final file = resolve(relativePath);
    if (file == null) return false;
    return file.exists();
  }

  /// Deletes the file if it exists. A missing file is not an error.
  Future<void> delete(String? relativePath) async {
    final file = resolve(relativePath);
    if (file == null) return;
    try {
      await file.delete();
    } on PathNotFoundException {
      // Already gone.
    }
  }

  /// Deletes every file in the image directory that is not in [referenced].
  /// Returns how many were removed. Run at startup to clean up after crashes
  /// and abandoned drafts.
  Future<int> sweepOrphans(Set<String> referenced) async {
    final dir = imagesDir;
    if (!await dir.exists()) return 0;
    var removed = 0;
    await for (final entity in dir.list(followLinks: false)) {
      if (entity is! File) continue;
      final relative = '$_dirName/${p.basename(entity.path)}';
      if (referenced.contains(relative)) continue;
      try {
        await entity.delete();
        removed++;
      } on FileSystemException {
        // Locked or already removed; the next sweep retries.
      }
    }
    return removed;
  }

  String _randomName() {
    final bytes = List<int>.generate(16, (_) => _random.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }
}
