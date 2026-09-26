import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:test_assistant/features/capture/domain/device_services.dart';
import 'package:test_assistant/features/capture/ui/crop_overlay.dart';

import '../support/harness.dart';

class _FakePermission implements CameraPermissionService {
  _FakePermission(this.result);

  CameraAccess result;
  int requests = 0;
  int settingsOpened = 0;

  @override
  Future<CameraAccess> request() async {
    requests++;
    return result;
  }

  @override
  Future<void> openSettings() async => settingsOpened++;
}

class _FakePicker implements ImageSourcePicker {
  _FakePicker(this.path);

  final String? path;
  int picks = 0;

  @override
  Future<String?> pickFromGallery() async {
    picks++;
    return path;
  }
}

void main() {
  late Harness h;
  setUp(() async {
    h = await Harness.create();
    await h.seedServer();
  });
  tearDown(() => h.dispose());

  group('camera permission', () {
    testWidgets('is requested only when the camera is opened', (tester) async {
      final permission = _FakePermission(CameraAccess.denied);
      await pumpApp(
        tester,
        h,
        extra: [cameraPermissionServiceProvider.overrideWithValue(permission)],
      );
      expect(permission.requests, 0, reason: 'not at startup');

      await tester.tap(find.byKey(const Key('main-take-photo')));
      await tester.pumpAndSettle();
      expect(permission.requests, 1);
    });

    testWidgets('denied: explains and offers to choose an image', (
      tester,
    ) async {
      final permission = _FakePermission(CameraAccess.denied);
      await pumpApp(
        tester,
        h,
        extra: [
          cameraPermissionServiceProvider.overrideWithValue(permission),
          imageSourcePickerProvider.overrideWithValue(_FakePicker(null)),
        ],
      );
      await tester.tap(find.byKey(const Key('main-take-photo')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('camera-denied')), findsOneWidget);
      expect(find.text('Camera access is needed'), findsOneWidget);
      expect(find.byKey(const Key('camera-choose-image')), findsOneWidget);
      expect(find.byKey(const Key('camera-open-settings')), findsNothing);

      // Trying again asks again.
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(permission.requests, 2);
    });

    testWidgets('permanently denied: offers app settings and the gallery', (
      tester,
    ) async {
      final permission = _FakePermission(CameraAccess.permanentlyDenied);
      await pumpApp(
        tester,
        h,
        extra: [
          cameraPermissionServiceProvider.overrideWithValue(permission),
          imageSourcePickerProvider.overrideWithValue(_FakePicker(null)),
        ],
      );
      await tester.tap(find.byKey(const Key('main-take-photo')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('camera-permanently-denied')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('camera-choose-image')), findsOneWidget);

      await tester.tap(find.byKey(const Key('camera-open-settings')));
      await tester.pump();
      expect(permission.settingsOpened, 1);
    });

    testWidgets('choosing an image from the denied screen opens the crop', (
      tester,
    ) async {
      final picker = _FakePicker('missing-file.jpg');
      await pumpApp(
        tester,
        h,
        extra: [
          cameraPermissionServiceProvider.overrideWithValue(
            _FakePermission(CameraAccess.permanentlyDenied),
          ),
          imageSourcePickerProvider.overrideWithValue(picker),
        ],
      );
      await tester.tap(find.byKey(const Key('main-take-photo')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('camera-choose-image')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(picker.picks, 1);
      expect(
        find.text('Crop'),
        findsOneWidget,
        reason: 'the crop screen is open',
      );
    });
  });

  group('gallery import', () {
    testWidgets('the main screen picks through the system picker', (
      tester,
    ) async {
      final picker = _FakePicker('missing-file.jpg');
      await pumpApp(
        tester,
        h,
        extra: [imageSourcePickerProvider.overrideWithValue(picker)],
      );

      await tester.tap(find.byKey(const Key('main-choose-image')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(picker.picks, 1);
      expect(find.text('Crop'), findsOneWidget);
    });

    testWidgets('cancelling the picker stays on the main screen', (
      tester,
    ) async {
      final picker = _FakePicker(null);
      await pumpApp(
        tester,
        h,
        extra: [imageSourcePickerProvider.overrideWithValue(picker)],
      );

      await tester.tap(find.byKey(const Key('main-choose-image')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('main-take-photo')), findsOneWidget);
    });
  });

  group('crop overlay', () {
    Future<GlobalKey<CropOverlayState>> pumpOverlay(
      WidgetTester tester,
      List<Rect> changes,
    ) async {
      final key = GlobalKey<CropOverlayState>();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 400,
              child: CropOverlay(
                key: key,
                image: MemoryImage(_transparentPng),
                imageAspectRatio: 1,
                onChanged: changes.add,
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      return key;
    }

    testWidgets('starts with the whole image selected', (tester) async {
      final key = await pumpOverlay(tester, []);
      expect(key.currentState!.selection, const Rect.fromLTRB(0, 0, 1, 1));
    });

    testWidgets('dragging a corner resizes the selection', (tester) async {
      final changes = <Rect>[];
      final key = await pumpOverlay(tester, changes);
      final topLeft = tester.getTopLeft(find.byType(CropOverlay));

      // Grab the bottom-right corner and drag it up and to the left.
      final bottomRight = topLeft + const Offset(400, 400);
      await tester.dragFrom(
        bottomRight - const Offset(2, 2),
        const Offset(-200, -100),
      );
      await tester.pump();

      final rect = key.currentState!.selection;
      expect(rect.left, 0);
      expect(rect.top, 0);
      expect(rect.right, closeTo(0.5, 0.02));
      expect(rect.bottom, closeTo(0.75, 0.02));
      expect(changes, isNotEmpty);
    });

    testWidgets('dragging inside moves the selection without resizing', (
      tester,
    ) async {
      final key = await pumpOverlay(tester, []);
      final topLeft = tester.getTopLeft(find.byType(CropOverlay));
      // Shrink first: pull the bottom-right corner to the center.
      await tester.dragFrom(
        topLeft + const Offset(398, 398),
        const Offset(-200, -200),
      );
      await tester.pump();
      final before = key.currentState!.selection;

      await tester.dragFrom(
        topLeft + const Offset(100, 100),
        const Offset(80, 40),
      );
      await tester.pump();

      final after = key.currentState!.selection;
      expect(after.width, closeTo(before.width, 0.001));
      expect(after.height, closeTo(before.height, 0.001));
      expect(after.left, greaterThan(before.left));
      expect(after.top, greaterThan(before.top));
    });

    testWidgets('the selection cannot shrink to nothing or leave the image', (
      tester,
    ) async {
      final key = await pumpOverlay(tester, []);
      final topLeft = tester.getTopLeft(find.byType(CropOverlay));

      await tester.dragFrom(
        topLeft + const Offset(398, 398),
        const Offset(-600, -600),
      );
      await tester.pump();
      var rect = key.currentState!.selection;
      expect(rect.width, greaterThanOrEqualTo(0.08 - 1e-9));
      expect(rect.height, greaterThanOrEqualTo(0.08 - 1e-9));

      await tester.dragFrom(
        topLeft + const Offset(10, 10),
        const Offset(900, 900),
      );
      await tester.pump();
      rect = key.currentState!.selection;
      expect(rect.left, greaterThanOrEqualTo(0));
      expect(rect.right, lessThanOrEqualTo(1.0 + 1e-9));
      expect(rect.bottom, lessThanOrEqualTo(1.0 + 1e-9));
    });

    testWidgets('reset selects the whole image again', (tester) async {
      final changes = <Rect>[];
      final key = await pumpOverlay(tester, changes);
      final topLeft = tester.getTopLeft(find.byType(CropOverlay));
      await tester.dragFrom(
        topLeft + const Offset(398, 398),
        const Offset(-200, -200),
      );
      await tester.pump();
      expect(
        key.currentState!.selection,
        isNot(const Rect.fromLTRB(0, 0, 1, 1)),
      );

      key.currentState!.reset();
      await tester.pump();

      expect(key.currentState!.selection, const Rect.fromLTRB(0, 0, 1, 1));
      expect(changes.last, const Rect.fromLTRB(0, 0, 1, 1));
    });
  });
}

// A valid 1x1 transparent PNG.
final _transparentPng = Uint8List.fromList(const [
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, //
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
  0x0D, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0xF8, 0xFF, 0xFF, 0x3F,
  0x00, 0x05, 0xFE, 0x02, 0xFE, 0xA7, 0x35, 0x81, 0x84, 0x00, 0x00, 0x00,
  0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
]);
