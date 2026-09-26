// Draft restoration after process death (task 13.8), run on a device.
//
//   flutter run -t tool/restore_check.dart -d <device> --dart-define=RESTORE_PHASE=create
//   adb shell am force-stop com.nyver.testassistant      # the process dies
//   flutter run -t tool/restore_check.dart -d <device> --dart-define=RESTORE_PHASE=verify
//   adb logcat -s flutter | findstr RESTORE
//
// "create" stores a server and an edited draft in the real on-device database.
// "verify" starts a fresh process on the same files and reports whether the app
// opens the recognition screen with the edited content and the image.
import 'dart:async';
import 'dart:io';

import 'package:drift_flutter/drift_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:test_assistant/app/app.dart';
import 'package:test_assistant/app/router.dart';
import 'package:test_assistant/core/database/app_database.dart';
import 'package:test_assistant/core/di/providers.dart';
import 'package:test_assistant/features/questions/domain/draft_controller.dart';
import 'package:test_assistant/features/questions/domain/models.dart';

const _phase = String.fromEnvironment('RESTORE_PHASE');

void _log(String message) => debugPrint('RESTORE: $message');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final database = AppDatabase(driftDatabase(name: 'restore_check'));
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
    ],
  );

  if (_phase == 'create') {
    final record = await container
        .read(serverRepositoryProvider)
        .add(
          serverId: '019d2f6e-8a3c-7c1e-9b41-5d2a6f0e1c77',
          name: 'Restore server',
          baseUrl: Uri.parse('https://10.0.2.2:8443'),
        );
    await container.read(serverSecretsProvider).writeToken(record.id, 'token');

    final stored = await container.read(imageStoreProvider).create();
    await stored.file.writeAsBytes([1, 2, 3]);
    await container.read(draftControllerProvider.future);
    final draft = container.read(draftControllerProvider.notifier);
    await draft.startNew(
      imagePath: stored.relativePath,
      ocrText: 'Which protocol?\nA. HTTP\nB. HTTPS',
    );
    draft.updateQuestion('EDITED before the process was killed?');
    draft.updateOption(1, const OptionItem(id: 'B', text: 'EDITED HTTPS'));
    await draft.flush();
    _log('created draft; now kill the process');
    return;
  }

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const TestAssistantApp(),
    ),
  );
  // Give the router time to load the session and restore the draft.
  await Future<void>.delayed(const Duration(seconds: 6));

  final location = container
      .read(routerProvider)
      .routerDelegate
      .currentConfiguration
      .uri
      .path;
  final draft = container.read(draftControllerProvider).value;
  final imageOk =
      draft?.imagePath != null &&
      File(
        '${(await getApplicationDocumentsDirectory()).path}/${draft!.imagePath}',
      ).existsSync();
  final ok =
      location == Routes.recognition &&
      draft?.questionText == 'EDITED before the process was killed?' &&
      draft?.options[1].text == 'EDITED HTTPS' &&
      imageOk;
  _log(
    'location=$location question=${draft?.questionText} '
    'option=${draft?.options.elementAtOrNull(1)?.text} image=$imageOk',
  );
  _log(
    ok ? 'PASS: the draft was restored' : 'FAIL: the draft was not restored',
  );

  // Clean up so the next run starts from scratch.
  final session = container.read(serverSessionProvider).value;
  if (session != null) {
    await container.read(serverSecretsProvider).deleteAll(session.record.id);
    await container.read(serverRepositoryProvider).remove(session.record.id);
  }
  await container.read(draftControllerProvider.notifier).discard();
}
