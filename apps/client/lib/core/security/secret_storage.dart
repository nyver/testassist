import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Minimal key-value interface over the platform's secure storage, so the
/// repositories can be tested with an in-memory fake.
abstract interface class SecretStorage {
  Future<String?> read(String key);

  Future<void> write(String key, String value);

  Future<void> delete(String key);
}

/// [SecretStorage] backed by `flutter_secure_storage` (Android Keystore).
class KeystoreSecretStorage implements SecretStorage {
  KeystoreSecretStorage([FlutterSecureStorage? storage])
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

/// Token and pinned fingerprint of one server, keyed by the local server
/// record id. The key layout is versioned (`v1/`) so it can change later
/// without guessing which format a stored value uses. These values are never
/// written to the database, preferences or logs.
class ServerSecretsRepository {
  ServerSecretsRepository(this._storage);

  final SecretStorage _storage;

  static String tokenKey(int serverRecordId) =>
      'v1/server/$serverRecordId/token';

  static String fingerprintKey(int serverRecordId) =>
      'v1/server/$serverRecordId/fingerprint';

  Future<String?> readToken(int serverRecordId) =>
      _storage.read(tokenKey(serverRecordId));

  Future<void> writeToken(int serverRecordId, String token) =>
      _storage.write(tokenKey(serverRecordId), token);

  Future<String?> readFingerprint(int serverRecordId) =>
      _storage.read(fingerprintKey(serverRecordId));

  Future<void> writeFingerprint(int serverRecordId, String fingerprint) =>
      _storage.write(fingerprintKey(serverRecordId), fingerprint);

  Future<void> deleteFingerprint(int serverRecordId) =>
      _storage.delete(fingerprintKey(serverRecordId));

  /// Removes everything stored for the server.
  Future<void> deleteAll(int serverRecordId) async {
    await _storage.delete(tokenKey(serverRecordId));
    await _storage.delete(fingerprintKey(serverRecordId));
  }
}
