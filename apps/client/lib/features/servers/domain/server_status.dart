import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/providers.dart';
import '../../../core/errors/app_failure.dart';
import 'server_service.dart';

/// Checks that the configured server is reachable and is the one that was set
/// up. The value is null when everything is fine, otherwise the failure to
/// show. Re-evaluated whenever it is watched anew or the server changes.
final serverStatusProvider = FutureProvider.autoDispose<AppFailure?>((
  ref,
) async {
  // On a cold start the home screen opens while the stored server is still
  // being read. Checking before that would report a server that is not
  // configured yet as an error.
  final session = await ref.watch(serverSessionProvider.future);
  if (session == null) return null; // the router sends the user to the setup

  try {
    await ref.read(serverIdentityVerifierProvider)();
    return null;
  } on AppFailure catch (failure) {
    return failure;
  }
});
