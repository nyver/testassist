import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/di/providers.dart';
import '../features/capture/ui/camera_screen.dart';
import '../features/capture/ui/crop_screen.dart';
import '../features/capture/ui/main_screen.dart';
import '../features/history/ui/history_screen.dart';
import '../features/questions/ui/recognition_screen.dart';
import '../features/questions/ui/result_screen.dart';
import '../features/servers/ui/server_settings_screen.dart';
import '../features/servers/ui/server_setup_screen.dart';
import '../features/settings/ui/settings_screen.dart';

/// Locations of the app's screens.
abstract final class Routes {
  static const setup = '/setup';
  static const home = '/';
  static const recognition = '/recognition';
}

final routerProvider = Provider<GoRouter>((ref) {
  // Re-evaluate the redirect whenever the configured server changes.
  final refresh = ValueNotifier<int>(0);
  ref.listen(serverSessionProvider, (_, _) => refresh.value++);
  ref.onDispose(refresh.dispose);

  var draftRestoreChecked = false;

  final router = GoRouter(
    refreshListenable: refresh,
    redirect: (context, state) async {
      final session = ref.read(serverSessionProvider);
      if (session.isLoading) return null;

      final configured = session.value != null;
      final location = state.matchedLocation;
      if (!configured) {
        return location == Routes.setup ? null : Routes.setup;
      }
      if (location == Routes.setup) return Routes.home;

      // After a cold start, return to an unfinished question (also after the
      // system killed the process while the user was editing).
      if (!draftRestoreChecked && location == Routes.home) {
        draftRestoreChecked = true;
        final draft = await ref.read(draftRepositoryProvider).load();
        if (draft != null) return Routes.recognition;
      }
      return null;
    },
    routes: [
      GoRoute(
        path: Routes.setup,
        builder: (context, state) => const ServerSetupScreen(),
      ),
      GoRoute(
        path: Routes.home,
        builder: (context, state) => const MainScreen(),
        routes: [
          GoRoute(
            path: 'camera',
            builder: (context, state) => const CameraScreen(),
          ),
          GoRoute(
            path: 'crop',
            builder: (context, state) =>
                CropScreen(sourcePath: state.extra! as String),
          ),
          GoRoute(
            path: 'recognition',
            builder: (context, state) => const RecognitionScreen(),
          ),
          GoRoute(
            path: 'result/:id',
            builder: (context, state) =>
                ResultScreen(entryId: int.parse(state.pathParameters['id']!)),
          ),
          GoRoute(
            path: 'history',
            builder: (context, state) => const HistoryScreen(),
          ),
          GoRoute(
            path: 'settings',
            builder: (context, state) => const SettingsScreen(),
            routes: [
              GoRoute(
                path: 'server',
                builder: (context, state) => const ServerSettingsScreen(),
              ),
            ],
          ),
        ],
      ),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
});
