import 'dart:developer' as developer;

import 'package:drift_flutter/drift_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app/app.dart';
import 'core/database/app_database.dart';
import 'core/di/providers.dart';
import 'core/storage/image_store.dart';
import 'features/history/data/drift_history_repository.dart';
import 'features/history/domain/history_service.dart';
import 'features/questions/data/drift_draft_repository.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final database = AppDatabase(driftDatabase(name: 'test_assistant'));
  final prefs = await SharedPreferences.getInstance();
  final documents = await getApplicationDocumentsDirectory();
  final cache = await getTemporaryDirectory();

  // Remove image files that nothing refers to (crashes, abandoned drafts). A
  // failure here must never keep the app from starting.
  try {
    await sweepOrphanImages(
      history: DriftHistoryRepository(database),
      drafts: DriftDraftRepository(database),
      images: ImageStore(documents),
    );
  } on Object catch (e, stack) {
    developer.log(
      'orphan image sweep failed',
      name: 'startup',
      error: e.runtimeType,
      stackTrace: stack,
    );
  }

  runApp(
    ProviderScope(
      // Failed requests are retried by the user, never automatically.
      retry: (retryCount, error) => null,
      overrides: [
        appDatabaseProvider.overrideWithValue(database),
        sharedPreferencesProvider.overrideWithValue(prefs),
        storageRootProvider.overrideWithValue(documents),
        tempDirectoryProvider.overrideWithValue(cache),
      ],
      child: const TestAssistantApp(),
    ),
  );
}
