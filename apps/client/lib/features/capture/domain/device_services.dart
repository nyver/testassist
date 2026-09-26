import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';

/// Result of asking for camera access.
enum CameraAccess { granted, denied, permanentlyDenied }

/// Camera permission handling behind an interface, so screens can be tested.
abstract interface class CameraPermissionService {
  /// Requests camera access. Call only when the user opens the camera.
  Future<CameraAccess> request();

  /// Opens the system settings of this app.
  Future<void> openSettings();
}

class PermissionHandlerCameraService implements CameraPermissionService {
  const PermissionHandlerCameraService();

  @override
  Future<CameraAccess> request() async {
    final status = await Permission.camera.request();
    if (status.isGranted) return CameraAccess.granted;
    if (status.isPermanentlyDenied || status.isRestricted) {
      return CameraAccess.permanentlyDenied;
    }
    return CameraAccess.denied;
  }

  @override
  Future<void> openSettings() async {
    await openAppSettings();
  }
}

/// Picks one image from the device through the system photo picker, which
/// needs no storage permission.
abstract interface class ImageSourcePicker {
  /// Returns the picked file's path, or null when the user cancelled.
  Future<String?> pickFromGallery();
}

class SystemImageSourcePicker implements ImageSourcePicker {
  SystemImageSourcePicker([ImagePicker? picker])
    : _picker = picker ?? ImagePicker();

  final ImagePicker _picker;

  @override
  Future<String?> pickFromGallery() async {
    // Bounding the size and asking for a quality re-encodes the pick as a
    // JPEG, which also converts formats the image package cannot read.
    final file = await _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 4096,
      maxHeight: 4096,
      imageQuality: 92,
    );
    return file?.path;
  }
}

final cameraPermissionServiceProvider = Provider<CameraPermissionService>(
  (ref) => const PermissionHandlerCameraService(),
);

final imageSourcePickerProvider = Provider<ImageSourcePicker>(
  (ref) => SystemImageSourcePicker(),
);
