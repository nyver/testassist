import 'package:flutter_test/flutter_test.dart';
import 'package:test_assistant/core/security/secret_storage.dart';

import '../support/fakes.dart';

void main() {
  test('secrets are stored under versioned per-server keys', () async {
    final storage = InMemorySecretStorage();
    final repo = ServerSecretsRepository(storage);

    await repo.writeToken(7, 'tok');
    await repo.writeFingerprint(7, 'AA:BB');

    expect(storage.values, {
      'v1/server/7/token': 'tok',
      'v1/server/7/fingerprint': 'AA:BB',
    });
    expect(await repo.readToken(7), 'tok');
    expect(await repo.readFingerprint(7), 'AA:BB');
  });

  test('servers do not see each other\'s secrets', () async {
    final repo = ServerSecretsRepository(InMemorySecretStorage());
    await repo.writeToken(1, 'one');
    await repo.writeToken(2, 'two');

    expect(await repo.readToken(1), 'one');
    expect(await repo.readToken(2), 'two');
    expect(await repo.readFingerprint(1), isNull);
  });

  test('deleting the fingerprint keeps the token', () async {
    final repo = ServerSecretsRepository(InMemorySecretStorage());
    await repo.writeToken(1, 'tok');
    await repo.writeFingerprint(1, 'AA');

    await repo.deleteFingerprint(1);

    expect(await repo.readFingerprint(1), isNull);
    expect(await repo.readToken(1), 'tok');
  });

  test('deleteAll removes the token and the fingerprint', () async {
    final storage = InMemorySecretStorage();
    final repo = ServerSecretsRepository(storage);
    await repo.writeToken(1, 'tok');
    await repo.writeFingerprint(1, 'AA');
    await repo.writeToken(2, 'other');

    await repo.deleteAll(1);

    expect(storage.values, {'v1/server/2/token': 'other'});
  });
}
