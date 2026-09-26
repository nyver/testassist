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

    Rect imageRect(WidgetTester tester) =>
        tester.getRect(find.byKey(const Key('crop-image')));

    testWidgets('dragging a corner resizes the selection', (tester) async {
      final changes = <Rect>[];
      final key = await pumpOverlay(tester, changes);
      final image = imageRect(tester);

      // Grab the bottom-right corner and drag it up and to the left.
      await tester.dragFrom(
        image.bottomRight - const Offset(2, 2),
        Offset(-image.width / 2, -image.height / 4),
      );
      await tester.pump();

      final rect = key.currentState!.selection;
      expect(rect.left, 0);
      expect(rect.top, 0);
      expect(rect.right, closeTo(0.5, 0.02));
      expect(rect.bottom, closeTo(0.75, 0.02));
      expect(changes, isNotEmpty);
    });

    // Each corner must follow the finger from the moment it goes down, however
    // far the finger travels before the drag is recognized.
    for (final corner in ['topLeft', 'topRight', 'bottomLeft', 'bottomRight']) {
      testWidgets('the $corner corner can be dragged inward', (tester) async {
        final key = await pumpOverlay(tester, []);
        final image = imageRect(tester);
        final (start, toward) = switch (corner) {
          'topLeft' => (image.topLeft, const Offset(1, 1)),
          'topRight' => (image.topRight, const Offset(-1, 1)),
          'bottomLeft' => (image.bottomLeft, const Offset(1, -1)),
          _ => (image.bottomRight, const Offset(-1, -1)),
        };

        // Sit exactly on the corner and pull it about a third of the way in,
        // in small steps like a finger does.
        final gesture = await tester.startGesture(start);
        for (var i = 0; i < 40; i++) {
          await gesture.moveBy(
            Offset(
              toward.dx * image.width / 120,
              toward.dy * image.height / 120,
            ),
          );
        }
        await gesture.up();
        await tester.pump();

        final rect = key.currentState!.selection;
        expect(rect.width, closeTo(2 / 3, 0.03), reason: '$rect');
        expect(rect.height, closeTo(2 / 3, 0.03), reason: '$rect');
        // The opposite corner stays where it was.
        switch (corner) {
          case 'topLeft':
            expect([rect.right, rect.bottom], [1.0, 1.0]);
          case 'topRight':
            expect([rect.left, rect.bottom], [0.0, 1.0]);
          case 'bottomLeft':
            expect([rect.right, rect.top], [1.0, 0.0]);
          default:
            expect([rect.left, rect.top], [0.0, 0.0]);
        }
      });
    }

    testWidgets('a handle just outside the image can be grabbed', (
      tester,
    ) async {
      final key = await pumpOverlay(tester, []);
      final image = imageRect(tester);

      // The outer half of the handle lies outside the picture.
      await tester.dragFrom(
        image.bottomRight + const Offset(8, 8),
        Offset(-image.width / 2, -image.height / 2),
      );
      await tester.pump();

      final rect = key.currentState!.selection;
      expect(rect.right, closeTo(0.5, 0.03));
      expect(rect.bottom, closeTo(0.5, 0.03));
    });

    testWidgets('dragging inside moves the selection without resizing', (
      tester,
    ) async {
      final key = await pumpOverlay(tester, []);
      final image = imageRect(tester);
      // Shrink first: pull the bottom-right corner to the center.
      await tester.dragFrom(
        image.bottomRight - const Offset(2, 2),
        Offset(-image.width / 2, -image.height / 2),
      );
      await tester.pump();
      final before = key.currentState!.selection;

      await tester.dragFrom(
        image.topLeft + Offset(image.width / 4, image.height / 4),
        const Offset(40, 20),
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
      final image = imageRect(tester);

      await tester.dragFrom(
        image.bottomRight - const Offset(2, 2),
        const Offset(-600, -600),
      );
      await tester.pump();
      var rect = key.currentState!.selection;
      expect(rect.width, greaterThanOrEqualTo(0.08 - 1e-9));
      expect(rect.height, greaterThanOrEqualTo(0.08 - 1e-9));

      await tester.dragFrom(
        image.topLeft + const Offset(10, 10),
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
      final image = imageRect(tester);
      await tester.dragFrom(
        image.bottomRight - const Offset(2, 2),
        const Offset(-150, -150),
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
