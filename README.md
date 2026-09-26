# Test Assistant

Take a photo of a multiple-choice question and get the correct answer with a short explanation. The phone recognizes the text on the device, sends the question to **your own server**, and the server asks an LLM of your choice (OpenRouter, RouterAI or any OpenAI-compatible API). Answers are kept only on the phone.

```text
photo -> on-device OCR -> editable question -> your Go server (HTTPS) -> LLM -> answer + history on the phone
```

## Contents

- [Requirements](#requirements)
- [Server: quick start with Docker Compose](#server-quick-start-with-docker-compose)
- [Pair the phone](#pair-the-phone)
- [Configuration](#configuration)
- [Building](#building)
- [Tests](#tests)
- [Repository structure](#repository-structure)
- [Security and privacy](#security-and-privacy)
- [Troubleshooting](#troubleshooting)
- [Limitations](#limitations)

## Requirements

| Part | Needs |
|---|---|
| Server | Docker with Compose v2, or Go 1.25+ to build and run it directly; an API key of at least one LLM provider |
| Android client | Android 10 (API 29) or newer; Flutter stable 3.47+ and the Android SDK to build it |
| Development | `gofumpt`, `golangci-lint`, `openssl` (only to regenerate test certificates) |

## Server: quick start with Docker Compose

```text
cd docker
cp .env.example .env                    # put your provider key(s) into .env
cp ../config.example.yaml config.yaml   # server settings, see below
sh ../scripts/init-volumes.sh           # creates ./data and ./certs for the container's user (UID 65532)
docker compose up -d --build
docker compose logs                     # shows the listen address and the certificate fingerprint
```

Before starting, edit two files in `docker/`:

- **`.env`**: the provider API key(s), `OPENROUTER_API_KEY` and/or `ROUTERAI_API_KEY`. A provider without a key is disabled, and the server reports "not ready" if none has one.
- **`config.yaml`**: a copy of [`config.example.yaml`](config.example.yaml); compose mounts it into the container read-only. Every key is optional and the defaults work as they are, except one: under `tls.self_signed_hosts` list the address your phone connects to (for example `192.168.1.10`), otherwise the generated certificate does not cover it. Compose requires the file to exist, so do not skip the `cp`.

`init-volumes.sh` is run with `sh` so that it works even if the executable bit was lost on checkout. It calls `sudo chown`, so it may ask for your password.

On the first start the server:

1. creates its identity (`data/server.json`, a stable UUID) and an API token (`data/auth.json`, mode 0600);
2. generates a self-signed ECDSA P-256 certificate in `certs/` (valid for `localhost`, `127.0.0.1` and the hosts in `tls.self_signed_hosts`), unless you put your own `server.crt` and `server.key` there;
3. prints `HTTPS listening on ...` and `Certificate SHA-256 fingerprint: ...`.

The certificate, the token and the server id survive `docker compose up --force-recreate` because they live in the mounted `./data` and `./certs`.

Get the pairing values at any time (the image has no shell, but the binary has these commands):

```text
docker compose exec test-assistant /server certificate fingerprint
docker compose exec test-assistant /server token show
```

To rotate the token: `docker compose exec test-assistant /server token rotate`, then `docker compose restart`. Phones must then enter the new token.

**Put your phone's address into the certificate.** If the phone connects by IP or a private name (for example `192.168.1.10`), set `tls.self_signed_hosts` in `config.yaml` before the first start (see [Configuration](#configuration)); a generated certificate is not regenerated later. To change it afterwards, delete `docker/certs/server.crt` and `server.key`, then `docker compose restart`, and pair the phones again. Publicly trusted certificates (for example from Let's Encrypt behind your own domain) also work: put `server.crt` and `server.key` in `certs/`.

Run without Docker:

```text
cp config.example.yaml config.yaml      # from the repository root; edit tls.self_signed_hosts
cd server
go build -o test-assistant-server ./cmd/server
OPENROUTER_API_KEY=... DATA_DIR=./data TLS_CERT_FILE=./certs/server.crt TLS_KEY_FILE=./certs/server.key \
  ./test-assistant-server serve -config ../config.yaml
```

Server commands: `serve` (default), `certificate fingerprint`, `token show`, `token rotate`, `healthcheck`. All take `-config FILE` (or `APP_CONFIG`).

## Pair the phone

1. Install the app (see [Building](#building)) and open it. It asks for the server.
2. Enter the address (`https://192.168.1.10:8447`), a name and the token from `token show`. Only `https://` is accepted.
3. If the certificate is not issued by a public authority, the app shows its SHA-256 fingerprint. **Compare it with the fingerprint printed by the server**, then tap **Trust**. From then on the app accepts only that certificate for that address, even if another certificate would be valid for a public CA.
4. The main screen opens. Use **Take photo** or **Choose image**, crop the question, correct the recognized text if needed, choose a model and tap **Get answer**.

**Send image to model** is off by default and works only with models that support images (marked "Images" in the list). Without it only the recognized text is sent.

With the switch on, the text is optional: when nothing was recognized, or the question or the options are incomplete, **Get answer** stays available and only the image is sent. The model reads the question and options from the picture and reports them back, so the result and the history show what it read. This is the way to handle Russian questions, which the on-device OCR cannot read.

If the certificate changes later, the app blocks the connection with "Server certificate has changed" and sends nothing. If you changed it on purpose, open **Server settings** and choose **Reset trusted certificate**.

## Configuration

Precedence: built-in defaults, then an optional YAML file, then environment variables. See [`config.example.yaml`](config.example.yaml) for every key with its default; copy it to `config.yaml` (git-ignored) and keep only the keys you change, or leave it whole. With Docker Compose the file is `docker/config.yaml`, already wired up through `APP_CONFIG`; without Docker pass it with `-config` or `APP_CONFIG`. Inside the container the paths in the file (`/data`, `/certs`) must stay as they are, because compose mounts the volumes there. Unknown keys and invalid values stop the server at startup with a message naming the key.

| Environment variable | Meaning |
|---|---|
| `OPENROUTER_API_KEY`, `ROUTERAI_API_KEY` | Provider keys. Each can also be given as `<NAME>_FILE` (path of a Docker secret). A provider without a key is disabled. |
| `APP_CONFIG` | Path of the YAML file |
| `APP_LISTEN_ADDR` | Listen address, default `:8447` |
| `DATA_DIR` | Directory for `server.json` and `auth.json` |
| `TLS_CERT_FILE`, `TLS_KEY_FILE` | Certificate and key paths |
| `SERVER_NAME` | Name shown in the app |
| `AUTH_TOKEN` (or `AUTH_TOKEN_FILE`) | Use this token instead of the generated one |

Add another OpenAI-compatible provider (Ollama, vLLM, LM Studio, OpenAI, ...) in YAML only:

```yaml
llm:
  providers:
    - id: local
      name: Local Ollama
      type: openai-compatible
      base_url: http://ollama:11434/v1
      default_model: llama3.2-vision
```

Default model ids for OpenRouter and RouterAI are set in the defaults; check them against your provider's catalog and override `default_model` if needed. RouterAI's model listing format has not been verified against the live API: declare models statically under `models:` if capabilities are missing.

## Building

### Server

```text
cd server
go build ./...
# Windows binary
GOOS=windows GOARCH=amd64 go build -trimpath -ldflags "-s -w -X main.version=0.1.0" -o test-assistant-server.exe ./cmd/server
# Docker image
docker build -f ../docker/Dockerfile --build-arg VERSION=0.1.0 -t test-assistant-server:0.1.0 .
```

### Android app

```text
cd apps/client
flutter pub get
flutter gen-l10n                          # only after changing lib/l10n/*.arb
dart run build_runner build               # only after changing the Drift schema
flutter build apk --debug
flutter build apk --release --split-per-abi
```

- Requirements: `minSdk 29`, the latest `targetSdk` and `compileSdk` supported by the installed Flutter.
- Release signing: create `apps/client/android/key.properties` (`storeFile`, `storePassword`, `keyAlias`, `keyPassword`) next to a keystore **outside version control**. Without it the release build is signed with the debug key and must not be distributed.
- Release builds use R8; the rules are in `android/app/proguard-rules.pro`.
- On Windows with the pub cache and the project on different drives, `kotlin.incremental=false` (already set) avoids Kotlin cache errors.
- The Windows desktop client is not part of this version.

## Tests

```text
# server (from /server)
gofumpt -l .                     # must print nothing
go vet ./...
golangci-lint run
go test ./... -count=1
go test ./... -race -count=1     # needs cgo; see below

# client (from /apps/client)
dart format --set-exit-if-changed .
flutter analyze
flutter test
```

- **Race detector.** `-race` needs a C compiler. Where none is installed, run it in a container: `docker run --rm -v "$PWD:/repo" -w /repo/server golang:1.25 go test ./... -race -count=1`.
- **Shared fixtures.** `protocol/fixtures/` holds API responses and raw model outputs that both the Go and the Dart tests use, and a certificate whose fingerprint was computed independently with `openssl`.
- **TLS test certificates** for the client live in `apps/client/test/fixtures/tls/` (test-only, including the keys). Regenerate them with `scripts/gen-test-certs.sh`.
- **End-to-end on an emulator or device** (real app, real server, fake LLM): [`docs/testing/e2e-android.md`](docs/testing/e2e-android.md).

## Repository structure

```text
apps/client/            Flutter app (lib/{app,core,features,shared}, test/, integration_test/, tool/)
server/                 Go module (cmd/server, internal/...)
protocol/               openapi.yaml and cross-language fixtures
docker/                 Dockerfile, compose.yaml, .env.example
docs/architecture/      overview, OCR findings, dependency review
docs/security/          threat model
docs/adr/               architecture decision records
docs/testing/           end-to-end procedure
scripts/                init-volumes.sh, gen-test-certs.sh
config.example.yaml     every server setting with its default
```

## Security and privacy

- HTTPS only (TLS 1.2+). The app never accepts a certificate unconditionally: publicly trusted certificates are validated normally; self-signed ones only after you confirm the fingerprint, and are pinned afterwards.
- The Bearer token and the pinned fingerprint are stored only in Android Keystore-backed storage. Provider keys exist only on the server.
- The server keeps no photos, question text, prompts or answers, and its logs contain none of them either. The question, the options and (if you switch it on) the image are sent to the LLM provider you configured.
- The full analysis is in [`docs/security/threat-model.md`](docs/security/threat-model.md).

## Troubleshooting

| Symptom | Cause and fix |
|---|---|
| `mkdir /data ... permission denied` or `create temporary file ... is the directory writable` at startup | The bind mounts are not writable by the container user (UID 65532). Run `sh scripts/init-volumes.sh`, or `sudo chown -R 65532:65532 docker/data docker/certs`. |
| `docker compose up` fails with "not a directory", or the server reports a configuration error on `/etc/test-assistant/config.yaml` | `docker/config.yaml` did not exist when compose first ran, so Docker created a directory with that name. Run `rm -r docker/config.yaml`, then `cp config.example.yaml docker/config.yaml` and start again. |
| Container is `unhealthy` | `docker compose logs`. The health check calls `/health/ready`, which needs a writable data directory, a loaded certificate and at least one provider with a key. Check that a key is set in `.env`. |
| `TLS_CONFIGURATION_ERROR: ... exists but ... does not` | Only one of `server.crt` and `server.key` exists. The server never regenerates over a partial pair. Provide both, or delete the remaining file to generate a new pair. |
| App: "Server certificate has changed. Connection blocked." | The server presents another certificate than the one you trusted (it was regenerated, replaced, or someone is intercepting). Verify the new fingerprint (`server certificate fingerprint`), then **Server settings -> Reset trusted certificate**. |
| App: "Could not connect to the server" | Wrong address or port, the phone is not on the same network, or the certificate does not cover the address you typed (add it to `tls.self_signed_hosts`, delete `certs/server.crt` and `certs/server.key`, restart, and pair again). |
| App: "A different server responded at this address" | Another server now answers at the stored address. Check the address, or remove the server in the app and set it up again. |
| "The token is invalid" | Use `token show` for the current token; it changes after `token rotate`. |
| "The selected model does not support images" | Pick a model marked "Images", or send only the text. |
| Russian text is recognized as gibberish | The bundled OCR reads Latin script only. Edit the text by hand or send the image to a vision model. Details in `docs/architecture/ocr.md`. |
| 429 "Too many requests" | Per-IP limits (30 requests and 10 analyses per minute by default). Wait, or raise `rate_limit` in the configuration. |
| `-race` fails with "requires cgo" | No C compiler. Use the Docker command in [Tests](#tests). |

## Limitations

One server per phone, one shared token, Latin-only OCR, no Test Session mode, history filters or export, and no provider failover yet. See [`docs/architecture/overview.md`](docs/architecture/overview.md).
