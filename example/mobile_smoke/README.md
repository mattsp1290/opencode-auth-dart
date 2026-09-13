# Mobile smoke fixture

This fixture is the Rook-shaped native `IOClient` conformance gate. Generate
or refresh its Android and iOS runners with Flutter 3.47.1, then keep the
generated toolchain metadata under review before running it.

Required target tuple:

- Flutter 3.47.1 / Dart 3.13.1 / `http` 1.6.0
- physical iPhone 12 with privately recorded OS/device identifier
- physical AYN Thor with privately recorded firmware/device identifier

From this directory:

```sh
flutter create --platforms=android,ios .
flutter pub get
flutter analyze
flutter test
flutter test integration_test/opencode_auth_smoke_test.dart -d <iphone-12-id>
flutter test integration_test/opencode_auth_smoke_test.dart -d <ayn-thor-id>
flutter build ios --no-codesign
flutter build apk --debug
```

Retain only date, device model, OS/firmware, Flutter/Dart/http versions,
`IOClient`, and per-case pass/fail. Do not retain credentials, session values,
device IDs, request/response bodies, or headers. Builds do not replace both
physical-device test runs.
