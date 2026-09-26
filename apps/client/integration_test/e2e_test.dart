// End-to-end check of the real app against a real server (task 16.4).
//
// What is real: the TLS probe and pinning, the Dio client, secure storage, the
// Drift database, image processing, ML Kit OCR, the Go server and its provider
// adapter. What is faked: the system image picker (returns a sample image) and
// the LLM behind the server (tool/fake_llm.dart), so no API key is needed.
//
// See docs/testing/e2e-android.md for the full setup and the command line.
import 'dart:convert';
import 'dart:io';

import 'package:drift_flutter/drift_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:image/image.dart' as img;
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:test_assistant/app/app.dart';
import 'package:test_assistant/core/database/app_database.dart';
import 'package:test_assistant/core/di/providers.dart';
import 'package:test_assistant/features/capture/domain/device_services.dart';
import 'package:test_assistant/features/questions/domain/draft_controller.dart';

const _url = String.fromEnvironment('E2E_URL');
const _url2 = String.fromEnvironment('E2E_URL2');
const _token = String.fromEnvironment('E2E_TOKEN');
const _fingerprint = String.fromEnvironment('E2E_FINGERPRINT');
const _fingerprint2 = String.fromEnvironment('E2E_FINGERPRINT2');
const _llmStats = String.fromEnvironment('E2E_LLM_STATS');

/// Renders the sample question into a PNG, so no file has to be pushed to the
/// device. The bitmap font covers Latin script only, which is what the bundled
/// recognizer reads reliably.
String _writeSampleImage(Directory dir) {
  final image = img.Image(width: 1400, height: 700);
  img.fill(image, color: img.ColorRgb8(255, 255, 255));
  const lines = [
    'Which protocol encrypts HTTP?',
    'A. FTP',
    'B. HTTPS',
    'C. SMTP',
    'D. Telnet',
  ];
  for (var i = 0; i < lines.length; i++) {
    img.drawString(
      image,
      lines[i],
      font: img.arial48,
      x: 40,
      y: 40 + i * 110,
      color: img.ColorRgb8(0, 0, 0),
    );
  }
  final file = File('${dir.path}/e2e_sample.png')
    ..writeAsBytesSync(img.encodePng(image));
  return file.path;
}

class _SampleImagePicker implements ImageSourcePicker {
  _SampleImagePicker(this.path);

  final String path;

  @override
  Future<String?> pickFromGallery() async => path;
}

Future<List<Map<String, Object?>>> _llmRequests() async {
  final client = HttpClient();
  try {
    final request = await client.getUrl(Uri.parse('$_llmStats/__stats'));
    final response = await request.close();
    final body = await utf8.decoder.bind(response).join();
    return (jsonDecode(body) as List<Object?>).cast<Map<String, Object?>>();
  } finally {
    client.close();
  }
}

/// Pumps real time until [finder] matches or [timeout] passes.
Future<void> _waitFor(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 60),
}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 250));
    if (finder.evaluate().isNotEmpty) return;
  }
  final texts = tester
      .widgetList<Text>(find.byType(Text))
      .map((t) => t.data)
      .join(' | ');
  throw TestFailure('Timed out waiting for $finder. On screen: $texts');
}

/// Finds [finder], scrolling the current list down when it is not built yet.
Future<void> _reveal(WidgetTester tester, Finder finder) async {
  final end = DateTime.now().add(const Duration(seconds: 30));
  while (finder.evaluate().isEmpty) {
    if (DateTime.now().isAfter(end)) {
      throw TestFailure('Timed out waiting for $finder');
    }
    await tester.pump(const Duration(milliseconds: 250));
    if (finder.evaluate().isEmpty &&
        find.byType(Scrollable).evaluate().isNotEmpty) {
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -300));
    }
  }
  await tester.ensureVisible(finder);
  await tester.pump(const Duration(milliseconds: 100));
}

/// Taps "Get answer". A visible snackbar would cover the button, so it is
/// dismissed first.
Future<void> _getAnswer(WidgetTester tester) async {
  ScaffoldMessenger.of(tester.element(find.byType(Scaffold).first))
      .clearSnackBars();
  await tester.pump(const Duration(milliseconds: 500));
  await _tap(tester, find.byKey(const Key('get-answer')));
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await _reveal(tester, finder);
  await tester.tap(finder);
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('pair, answer with text and vision models, timeout, changed '
      'certificate', (tester) async {
    expect(_url, isNotEmpty, reason: 'pass --dart-define values, see the docs');

    SharedPreferences.setMockInitialValues({});
    final database = AppDatabase(
      driftDatabase(name: 'e2e_${DateTime.now().millisecondsSinceEpoch}'),
    );
    addTearDown(database.close);
    final container = ProviderContainer(
      retry: (count, error) => null,
      overrides: [
        appDatabaseProvider.overrideWithValue(database),
        sharedPreferencesProvider.overrideWithValue(
          await SharedPreferences.getInstance(),
        ),
        storageRootProvider.overrideWithValue(
          await getApplicationDocumentsDirectory(),
        ),
        tempDirectoryProvider.overrideWithValue(await getTemporaryDirectory()),
        imageSourcePickerProvider.overrideWithValue(
          _SampleImagePicker(_writeSampleImage(await getTemporaryDirectory())),
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const TestAssistantApp(),
      ),
    );

    // --- 1. First self-signed trust ------------------------------------------
    await _waitFor(tester, find.byKey(const Key('setup-url')));
    await tester.enterText(find.byKey(const Key('setup-url')), _url);
    await tester.enterText(find.byKey(const Key('setup-name')), 'E2E server');
    await tester.enterText(find.byKey(const Key('setup-token')), _token);
    await tester.tap(find.byKey(const Key('setup-connect')));
    await _waitFor(tester, find.byKey(const Key('trust-fingerprint')));
    expect(
      tester
          .widget<SelectableText>(find.byKey(const Key('trust-fingerprint')))
          .data,
      _fingerprint,
      reason: 'the dialog shows the fingerprint the server printed',
    );
    await tester.tap(find.text('Trust'));
    await _waitFor(tester, find.byKey(const Key('main-choose-image')));

    // --- 2. Photo -> OCR -> editable question ----------------------------------
    Future<void> captureSample() async {
      await _tap(tester, find.byKey(const Key('main-choose-image')));
      await _tap(tester, find.byKey(const Key('crop-confirm')));
      await _waitFor(tester, find.byKey(const Key('question-field')));
    }

    await captureSample();
    expect(find.text('Which protocol encrypts HTTP?'), findsOneWidget);
    expect(find.byKey(const Key('option-id-3')), findsOneWidget);
    expect(find.byKey(const Key('low-quality-warning')), findsNothing);

    // --- 3. Answer with the (default) text-only model --------------------------
    await _reveal(tester, find.byKey(const Key('model-button')));
    final switchTile = find.byKey(const Key('send-image-switch'));
    await _reveal(tester, switchTile);
    expect(tester.widget<SwitchListTile>(switchTile).onChanged, isNull);
    await _getAnswer(tester);
    await _waitFor(tester, find.byKey(const Key('answer-card')));
    expect(find.text('B. HTTPS'), findsOneWidget);
    var seen = await _llmRequests();
    expect(seen.last['model'], 'fake/text-model');
    expect(seen.last['hasImage'], false, reason: 'text-only model: no image');

    // --- 4. Answer with a vision model and the image ---------------------------
    await tester.pageBack();
    await tester.pump(const Duration(milliseconds: 500));
    await _tap(tester, find.byKey(const Key('main-choose-image')));
    await _tap(tester, find.byKey(const Key('crop-confirm')));
    await _waitFor(tester, find.byKey(const Key('question-field')));
    await _tap(tester, find.byKey(const Key('model-button')));
    await _tap(tester, find.byKey(const Key('model-fake/vision-model')));
    await _tap(tester, find.byKey(const Key('send-image-switch')));
    await _getAnswer(tester);
    await _waitFor(tester, find.byKey(const Key('answer-card')));
    seen = await _llmRequests();
    expect(seen.last['model'], 'fake/vision-model');
    expect(
      seen.last['hasImage'],
      true,
      reason: 'vision model with the switch on',
    );

    // --- 5. LLM timeout ---------------------------------------------------------
    context(tester).go('/');
    await tester.pump(const Duration(milliseconds: 500));
    await captureSample();
    await tester.enterText(
      find.byKey(const Key('question-field')),
      'TIMEOUT: which protocol encrypts HTTP?',
    );
    await tester.pump(const Duration(milliseconds: 300));
    await _getAnswer(tester);
    await _waitFor(
      tester,
      find.text('The model did not respond in time. Try again.'),
    );
    expect(
      container.read(draftControllerProvider).value?.questionText,
      contains('TIMEOUT'),
      reason: 'the draft is preserved',
    );

    // --- 6. Changed certificate is blocked --------------------------------------
    // The server now answers from another address with another certificate.
    await database.customStatement('UPDATE servers SET base_url = ?', [_url2]);
    await container.read(serverSessionProvider.notifier).reload();
    await _getAnswer(tester);
    await _waitFor(
      tester,
      find.textContaining(
        'Server certificate has changed. Connection blocked.',
      ),
    );
    final leaked = await _llmRequests();
    expect(
      leaked.length,
      seen.length + 1,
      reason:
          'only the timed-out request reached the LLM, none after the change',
    );

    // --- 7. Reset the trusted certificate ---------------------------------------
    context(tester).go('/settings/server');
    await tester.pump(const Duration(milliseconds: 500));
    await _tap(tester, find.byKey(const Key('server-reset-trust')));
    await _tap(tester, find.text('Continue'));
    await _waitFor(tester, find.byKey(const Key('trust-fingerprint')));
    expect(
      tester
          .widget<SelectableText>(find.byKey(const Key('trust-fingerprint')))
          .data,
      _fingerprint2,
    );
    await tester.tap(find.text('Trust'));
    await _waitFor(tester, find.text('Trusted certificate reset.'));

    context(tester).go('/recognition');
    await _waitFor(tester, find.byKey(const Key('question-field')));
    await tester.enterText(
      find.byKey(const Key('question-field')),
      'Which protocol encrypts HTTP?',
    );
    await tester.pump(const Duration(milliseconds: 300));
    await _reveal(tester, find.byKey(const Key('model-button')));
    await _getAnswer(tester);
    await _waitFor(tester, find.byKey(const Key('answer-card')));
    expect(find.text('B. HTTPS'), findsOneWidget);
  });
}

GoRouter context(WidgetTester tester) =>
    GoRouter.of(tester.element(find.byType(Scaffold).first));
