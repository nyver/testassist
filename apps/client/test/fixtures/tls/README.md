# TEST-ONLY TLS fixtures

Everything in this directory, **including the private keys**, exists only for the
TLS tests (`HttpServer.bindSecure` in `flutter test`). The keys are public and
must never be used at runtime or anywhere else.

| File | Purpose |
|---|---|
| `ca.pem`, `ca.key.pem` | test certificate authority |
| `leaf.pem`, `leaf.key.pem` | server certificate signed by the test CA |
| `self1.pem`, `self1.key.pem` | self-signed server certificate |
| `self2.pem`, `self2.key.pem` | a different self-signed server certificate |

All certificates are valid for `localhost` and `127.0.0.1` for about 100 years.
Regenerate them with `scripts/gen-test-certs.sh` (requires `openssl`).
