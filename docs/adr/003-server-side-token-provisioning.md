# 003. Server-side Bearer token provisioning

## Status

Accepted.

## Context

Anyone who can reach the API can spend the operator's LLM budget, so the API needs authentication. The system has a single operator and a few personal devices. User accounts, OAuth and multiple tokens would be disproportionate.

## Decision

- The server generates a token on first start: 32 bytes from `crypto/rand`, encoded as base64url. It stores the token in `<data_dir>/auth.json` (`{"version":1,"token":"..."}`) with mode `0600`.
- `AUTH_TOKEN` overrides the file for deployments that manage secrets externally. In that case the server does not create or read `auth.json`.
- The operator reads the token with `server token show` and replaces it with `server token rotate`. The token is never logged.
- The API requires `Authorization: Bearer <token>` on every `/api/v1/` endpoint. Comparison is constant-time. Health endpoints stay unauthenticated so the container health check works.
- The token is stored in plaintext on the server because the operator must be able to read it again. It lives on the same protected volume as the TLS private key, so hashing it would add little. Storing only a hash was rejected because a lost token would force a rotation.
- The client stores the token only in `flutter_secure_storage`, scoped per server.
- `security.auth_enabled: false` disables the check for trusted private networks. The server logs a startup warning when it is off.

## Consequences

- Provisioning needs one copy-and-paste step per device, done at the same time as the fingerprint check.
- All clients share one token, so revoking a single device means rotating the token for all.
- Anyone with read access to the data volume can read the token. This is the same trust boundary as the TLS private key.
