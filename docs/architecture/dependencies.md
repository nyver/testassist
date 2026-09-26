# Dependency review

Every dependency was reviewed for license, maintenance and footprint before it was added (AGENTS.md). "Why not the standard library?" is answered per row.

## Server (Go)

| Module | License | Why it is needed |
|---|---|---|
| `go.yaml.in/yaml/v3` | MIT / Apache-2.0 | YAML parsing with `KnownFields(true)`, so unknown configuration keys are rejected. The standard library has no YAML. |
| `golang.org/x/time` | BSD-3-Clause | Token-bucket rate limiter (`rate.Limiter`) maintained by the Go team. |
| `golang.org/x/sync` | BSD-3-Clause | `singleflight`, so concurrent model-list requests share one upstream call. |
| `github.com/google/uuid` | BSD-3-Clause | UUIDv7 server ids and UUIDv4 request ids. |

`x/time` and `x/sync` are pinned to versions that support Go 1.25 (the Docker build image). Newer releases need Go 1.26. The HTTP router, TLS, logging (`log/slog`), JSON and crypto all come from the standard library.

## Client (Flutter)

| Package | License | Why it is needed |
|---|---|---|
| `flutter_riverpod` | MIT | State management (AGENTS.md default). Notifiers are written by hand; no code generation. |
| `go_router` | BSD-3-Clause | Declarative routing with a redirect for "no server configured" and draft restoration. Maintained by the Flutter team. |
| `dio` | MIT | HTTP client with multipart upload, cancellation, timeouts and an adapter hook for the certificate-pinning callbacks. `dart:io` alone has none of the first three. |
| `crypto` | BSD-3-Clause | SHA-256 for certificate fingerprints. Dart team package. |
| `drift`, `drift_flutter`, `drift_dev`, `build_runner` | MIT / BSD-3-Clause | Typed SQLite with versioned schemas, exported schema snapshots and migration tests. `drift_flutter` bundles the SQLite library. Code generation is limited to Drift. |
| `flutter_secure_storage` | BSD-3-Clause | Token and pinned fingerprint in Android Keystore-backed storage (required by AGENTS.md). |
| `shared_preferences` | BSD-3-Clause | Non-secret preferences. Flutter team. |
| `path_provider`, `path` | BSD-3-Clause | App-private directories and path handling. Flutter/Dart team. |
| `camera` | BSD-3-Clause | Still capture with the CameraX backend. |
| `image_picker` | BSD-3-Clause | Gallery import through the Android Photo Picker, which needs no storage permission. |
| `image` | MIT | EXIF orientation, crop, resize and JPEG encoding in an isolate, without native code. |
| `google_mlkit_text_recognition` | MIT (plugin); ML Kit itself under Google's terms | On-device OCR. The Latin model is bundled in the APK, so OCR works offline. Its limits are recorded in `ocr.md`. |
| `permission_handler` | MIT | Needed to tell "denied" from "permanently denied" and to open the app settings, which the `camera` plugin cannot do. Version 12 is used because version 13 requires `compileSdk` 37, which the installed toolchain does not support. |
| `share_plus` | BSD-3-Clause | The system share sheet for the result text. |
| `intl`, `flutter_localizations` | BSD-3-Clause | ARB localization (English and Russian) and date formatting. |
| `integration_test` (dev, SDK) | BSD-3-Clause | End-to-end test on a device. |

All are actively released and used widely. `sqlcipher_flutter_libs` and `sqlite3_flutter_libs` appear only as end-of-life placeholders that `drift_flutter` still lists; they contain no code.

## Build and tooling notes

- `kotlin.incremental=false` in `apps/client/android/gradle.properties`: the pub cache and the project may be on different drive roots on Windows, which breaks Kotlin's incremental compilation.
- The release build enables R8 with `proguard-rules.pro` (ML Kit's optional script recognizers are referenced but not bundled).
