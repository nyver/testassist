import 'package:flutter/foundation.dart';

import 'server_record.dart';

/// The configured server together with its secrets, as loaded from the
/// database and secure storage.
@immutable
class ServerSession {
  const ServerSession({
    required this.record,
    required this.token,
    required this.pinnedFingerprint,
  });

  final ServerRecord record;

  /// The Bearer token, or null if it was lost from secure storage.
  final String? token;

  /// The trusted certificate fingerprint, or null when the certificate is
  /// publicly trusted (or trust was reset).
  final String? pinnedFingerprint;
}
