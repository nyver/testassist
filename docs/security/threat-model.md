# Threat model

Scope: the Test Assistant server (Go, self-hosted) and the Android client. The server stores no user content. The trust anchors are the operator's server volume and the user's phone.

## Assets

| Asset | Where | Why it matters |
|---|---|---|
| Provider API keys | server environment or Docker secrets | Cost, and access to the operator's LLM account |
| API Bearer token | `data/auth.json` (server), Android Keystore (client) | Lets a holder spend the operator's LLM budget |
| TLS private key | `certs/server.key` | Impersonating the server |
| Pinned certificate fingerprint | Android Keystore | Detects impersonation after pairing |
| Questions, options, images, answers | phone (history and drafts); in transit; in memory on the server; sent to the LLM provider | Privacy of what the user studies or is tested on |

## Actors and threats

| # | Threat | Mitigation | Residual risk |
|---|---|---|---|
| T1 | A network attacker reads or alters traffic | HTTPS only, TLS 1.2 or newer, no plaintext listener; the client never uses cleartext (`usesCleartextTraffic=false`, `https://` enforced in the UI) | None for the transport itself |
| T2 | A man-in-the-middle at first pairing with a self-signed server | The certificate is probed with a handshake that sends nothing; the user must compare the SHA-256 fingerprint with the one printed by the server and tap "Trust" | A user who does not compare the fingerprints accepts whatever answers first (TOFU). The dialog says so explicitly |
| T3 | Certificate swap after pairing | Handshake-level pin: for a pinned server no system roots are trusted and only the pinned leaf fingerprint for the configured host and port is accepted, even if a public CA would accept another certificate. A mismatch aborts the handshake before any request or token is sent and shows `CERTIFICATE_CHANGED`. Re-trust only through "Reset trusted certificate" | A legitimate certificate rotation costs a manual reset on every phone |
| T4 | A global "accept bad certificates" override | None exists in the client. The bad-certificate callback is scoped to host, port and fingerprint. Test-only trust anchors are injected through parameters and used only in tests | None |
| T5 | An unauthorized caller spends the LLM budget | Bearer token on every `/api/v1/` endpoint, compared in constant time; rate limits per client IP (general and analyze); request and image size limits; bounded LLM timeout, retries and response size | One shared token: revoking one device means rotating the token for all. Behind NAT the per-IP limit is coarse |
| T6 | Token theft from the server | `auth.json` is written with mode 0600 on a private volume; `AUTH_TOKEN` or a Docker secret can replace it; `server token rotate` replaces it. It is stored in plaintext because the operator must read it back | Anyone who can read the data volume can read the token, which is the same boundary as the TLS private key |
| T7 | Token theft from the phone | Only in Android Keystore-backed secure storage, never in SQLite, preferences or logs; `allowBackup=false` | A rooted or compromised device |
| T8 | A malicious server presented as the configured one | The client stores the server's UUID and compares it on each info call; a different server blocks analysis | An attacker who also holds the pinned certificate's key |
| T9 | Prompt injection through question or image text | User content is delimited and kept out of the system prompt; delimiter tags inside it are neutralized; the model has no tools or side effects; its output is accepted only as validated JSON whose option ids must come from the request | The model can still be talked into a wrong answer. The consequence is a wrong answer, nothing else |
| T10 | Malformed or hostile model output | Strict JSON validation (types, confidence range, option ids, non-empty ids for `answered`); a failure is `LLM_INVALID_RESPONSE`; raw output is never shown or logged | None beyond wrong answers |
| T11 | Oversized or malicious uploads | Body limit (8 MiB), image limit (5 MiB), streaming multipart parsing into memory (no temp files), type decided by content sniffing (JPEG, PNG, WebP), 128 KiB limit per text field | Memory use is bounded by concurrency times the limits |
| T12 | Secrets in logs | Structured logs with an allow-list of fields (request id, method, path, status, duration, provider, model, error code). No headers, query strings, bodies, keys, tokens, question or option text, images or model output. Upstream errors carry a status only, never a body. Verified by tests | A future code change could add a field; the tests would catch the known cases |
| T13 | API keys leaking through configuration | Keys come only from the environment or `<NAME>_FILE`; the YAML holds only the variable's name and rejects unknown keys, so a pasted `api_key` fails to load; a pasted secret in `api_key_env` is rejected without echoing it | None |
| T14 | User content persisted on the server | The server writes only `server.json`, `auth.json` and the certificate files. Verified by a test that no file appears during an analysis | The LLM provider still receives the content and has its own retention policy |
| T15 | Container escape or abuse | Distroless static image as a non-root user, read-only root filesystem, all capabilities dropped, `no-new-privileges`, no shell in the image | Bind mounts must be writable by UID 65532 (`scripts/init-volumes.sh`) |
| T16 | Local data exposure on the phone | History and images live in the app-private directory, not in backups; images are removed with their entry; optional "Delete images after analysis". The full-resolution original from the camera or the picker is deleted from the cache as soon as the processed copy exists, and abandoned intermediate files are removed when the crop screen closes | A rooted device can read the app's files. If the app is killed mid-processing, an intermediate cache file can remain until Android clears the cache |
| T17 | Denial of service against the server | Read-header, read and idle timeouts, per-IP rate limits, bounded bodies, idle limiter eviction, graceful shutdown | A distributed flood needs infrastructure-level protection |

## Privacy

- OCR runs on the device. The image leaves the phone only when "Send image to model" is on and the selected model supports images. The switch is off by default and turns on by itself only when the app could not recognize the question and options, and the user can turn it off before sending; the server rejects an image for a text-only model before contacting the provider.
- Every JPEG the app writes is stripped of EXIF metadata (GPS position, timestamps, device model) after the orientation is applied to the pixels, so neither the stored image nor the uploaded one carries it.
- The question, options and the image (if any) are sent to the LLM provider chosen by the operator. Users should choose providers accordingly.
- Answers are saved only on the phone.

## Out of scope for this version

Multiple tokens or user accounts, certificate rotation without user action, proxy-aware client addresses, hot reload of certificates, and protection against a compromised phone or server host.
