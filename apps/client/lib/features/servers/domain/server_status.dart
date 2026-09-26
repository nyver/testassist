import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/app_failure.dart';
import 'server_service.dart';

/// Checks that the configured server is reachable and is the one that was set
/// up. The value is null when everything is fine, otherwise the failure to
/// show. Re-evaluated whenever it is watched anew.
final serverStatusProvider = FutureProvider.autoDispose<AppFailure?>((
  ref,
) async {
  try {
    await ref.read(serverIdentityVerifierProvider)();
    return null;
  } on AppFailure catch (failure) {
    return failure;
  }
});
