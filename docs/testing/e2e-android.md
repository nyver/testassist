# End-to-end test on an Android emulator or device

`apps/client/integration_test/e2e_test.dart` drives the real app against a real server. What is **real**: the TLS probe and pinning, the Dio client, secure storage, the Drift database, image processing, ML Kit OCR, the Go server and its provider adapter. What is **faked**: the system image picker (the test renders a sample question into a PNG and "picks" it) and the LLM behind the server (`apps/client/tool/fake_llm.dart`), so no API key is needed.

## What it checks

1. First connection to a self-signed server: the fingerprint dialog shows exactly the fingerprint the server printed; after "Trust" the main screen opens.
2. Photo → crop → on-device OCR → an editable question with four options.
3. Answer with a **text-only** model: the LLM received no image, and the image switch is disabled.
4. Answer with a **vision** model and the image switch on: the LLM received the image.
5. **LLM timeout**: the timeout message appears and the draft is kept.
6. **Changed certificate**: the address now presents another certificate. The connection is blocked before any request is sent (the server only sees an aborted handshake), the certificate message is shown, and nothing reaches the LLM.
7. **Reset trusted certificate**: the new fingerprint is shown, "Trust" re-establishes access, and an answer is received again.

## Setup (Windows shell shown; adapt paths)

1. Start an Android emulator (API 29 or newer) or connect a device.
2. Start the fake LLM: `cd apps/client && dart run tool/fake_llm.dart` (port 9999).
3. Build the server: `cd server && go build -o <dir>/server.exe ./cmd/server`.
4. Create two configuration files in `<dir>`, `configA.yaml` (port 8443, certificates in `certsA`) and `configB.yaml` (port 8444, certificates in `certsB`), that share one `data_dir`:

   ```yaml
   server:
     name: "E2E server"
     listen: "127.0.0.1:8443"          # 8444 in configB.yaml
     data_dir: "<dir>/data"
   tls:
     cert_file: "<dir>/certsA/server.crt"   # certsB in configB.yaml
     key_file: "<dir>/certsA/server.key"
     self_signed_hosts: ["10.0.2.2"]    # the emulator's name for the host
   timeouts:
     llm: 5s
   llm:
     default_provider: fake
     providers:
       - id: fake
         name: Fake LLM
         type: openai-compatible
         base_url: http://127.0.0.1:9999/v1
         default_model: fake/text-model
   ```

5. Start both servers: `server.exe serve -config configA.yaml` and `server.exe serve -config configB.yaml`.
6. Read the values: `server.exe token show -config configA.yaml`, `server.exe certificate fingerprint -config configA.yaml` and the same for `configB.yaml`.

## Run

```text
cd apps/client
flutter test integration_test/e2e_test.dart -d <device-id> \
  --dart-define=E2E_URL=https://10.0.2.2:8443 \
  --dart-define=E2E_URL2=https://10.0.2.2:8444 \
  --dart-define=E2E_TOKEN=<token> \
  --dart-define=E2E_FINGERPRINT=<fingerprint of A> \
  --dart-define=E2E_FINGERPRINT2=<fingerprint of B> \
  --dart-define=E2E_LLM_STATS=http://10.0.2.2:9999
```

`10.0.2.2` is the emulator's alias for the host's loopback interface. On a physical device use the host's LAN address, add it to `tls.self_signed_hosts`, and listen on `0.0.0.0`.

## Other device checks

- **Draft restoration after process death** (`tool/restore_check.dart`): with "Don't keep activities" on (`adb shell settings put global always_finish_activities 1`), run the tool with `--dart-define=RESTORE_PHASE=create`, kill the process (`adb shell am force-stop com.nyver.testassistant`), run it again with `RESTORE_PHASE=verify` and read `RESTORE:` in `adb logcat -s flutter`. It reports whether the recognition screen was restored with the edited question, options and the image.
- **OCR spike** (`tool/ocr_spike.dart`): see `docs/architecture/ocr.md`.
