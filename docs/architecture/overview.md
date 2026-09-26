# Architecture overview

Test Assistant answers a multiple-choice question from a photo:

```text
photo -> on-device OCR -> editable question and options
      -> your own Go server (HTTPS, Bearer token)
      -> LLM provider (OpenRouter, RouterAI, any OpenAI-compatible API)
      -> validated answer -> phone (result screen and local history)
```

## Components

```text
apps/client/   Flutter app (Android 10+): capture, OCR, editing, history, server trust
server/        Go module: HTTPS API, TLS certificate manager, LLM provider layer
protocol/      OpenAPI document and JSON fixtures shared by Go and Dart tests
docker/        Dockerfile and compose.yaml
docs/          architecture, security, ADRs, testing
```

### Server (`server/internal`)

| Package | Responsibility |
|---|---|
| `config` | Defaults, YAML (unknown keys rejected), environment overrides, secret files, validation |
| `tlscert` | Load or generate the certificate, fingerprint, partial-state protection |
| `identity` | `server.json` (stable `serverId`) and `auth.json` (Bearer token) |
| `llm`, `llm/openaicompat` | Provider interface, registry with cached model lists, the one OpenAI-compatible adapter with retries and error mapping |
| `analysis` | The use case: request validation, vision gating, prompt, strict answer validation, confidence levels |
| `apierr` | Stable error codes and their HTTP statuses |
| `transport/httpapi` | Routing, middleware (request id, access log, recover, rate limit, auth, limits), handlers, health |
| `app` | Wiring, startup output, graceful shutdown, the `healthcheck` command |

Request path: request id, access log, panic recovery, per-IP rate limit, Bearer authentication, body limit, request timeout, then the handler. The analyze handler streams the multipart body into memory, sniffs the image type, calls `analysis.Service`, and returns the validated result. Nothing user-related is written to disk.

### Client (`apps/client/lib`)

Feature folders follow `ui -> domain <- data`. Notifiers and use cases sit in `domain/` and use Riverpod; repositories and API clients sit in `data/`; `core/di/providers.dart` is the composition root.

| Area | Notes |
|---|---|
| `core/security`, `core/network` | Fingerprint, certificate probe (a handshake that sends nothing), the pinned Dio client, secure storage |
| `core/database` | Drift schema v1 (`servers`, `questions`, `drafts`), exported snapshot in `drift_schemas/` |
| `features/servers` | Setup, trust on first use, pin reset, token replacement, identity check |
| `features/capture`, `features/ocr` | Camera and gallery, isolate-based image processing, ML Kit OCR, `QuestionParser` |
| `features/questions` | Draft, provider and model selection, analysis request, result screen |
| `features/history`, `features/settings` | History list and deletion, display mode and image retention |

## Data and secrets

| What | Where |
|---|---|
| Bearer token, pinned fingerprint | Android Keystore (`v1/server/<id>/token` and `.../fingerprint`) |
| Server record, history, draft | SQLite (Drift), no secrets |
| Photos | Files under the app-private `images/` directory, referenced by relative path |
| Preferences | `shared_preferences` |
| Server state | `data/server.json`, `data/auth.json`, `certs/server.crt`, `certs/server.key` |

## Decisions

See `docs/adr/`: TLS trust model (001), LLM provider abstraction (002), server-side token provisioning (003). Security analysis: `docs/security/threat-model.md`. OCR findings and limits: `docs/architecture/ocr.md`.

## Known limits of this version

- One server per phone, one shared Bearer token.
- Cyrillic OCR is not usable with the bundled Latin recognizer; use manual editing or "Send image to model" (see `ocr.md`).
- Certificates are read at startup; a change needs a restart and a manual "Reset trusted certificate" on each phone.
- No Test Session mode, history filters or export, perspective correction, learning mode, metrics or provider failover.
