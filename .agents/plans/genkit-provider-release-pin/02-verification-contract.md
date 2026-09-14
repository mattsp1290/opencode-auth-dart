# Verification and supported contract

Goal: prove the binding boundary, preserve transport behavior, and produce redacted evidence for the exact model/platform/toolchain contract. Prerequisite: the endpoint-binding API in [01-endpoint-binding-contract.md](01-endpoint-binding-contract.md) is integrated.

## Exact change surface

- Edit existing `test/options_test.dart`, `test/client_contract_test.dart`, `test/transport_test.dart`, `test/transport_stream_test.dart`, `test/real_io_transport_test.dart`, `test/catalog_test.dart`, and `test/support/recording_client.dart` for the shared auth library and explicit custom construction.
- Add **new** `test/endpoint_binding_test.dart` as specified in the endpoint-binding work package.
- Edit existing `test/live_test.dart` to count actual executor dispatches during the two-request tool exchange and retain redacted evidence.
- Add **new** `test/support/counting_client.dart` under existing `test/support/` for the live-only counting/barrier `http.BaseClient` wrapper.
- Edit existing `example/mobile_smoke/integration_test/opencode_auth_smoke_test.dart` so local TLS fixtures use `OpenCodeAuthOptions.custom` and assert custom binding before requests.
- Edit existing `example/mobile_smoke/README.md` with the exact tested tuple and evidence-retention rules.
- Add **new generated** `example/mobile_smoke/android/` and `example/mobile_smoke/ios/` platform trees under the existing fixture. Retain only reviewed source/toolchain metadata; existing ignore rules continue to exclude generated credentials, local properties, Pods, build products, and ephemeral files.
- Edit existing `README.md` with the binding API, construction examples, platform tuple, verification commands, and known limits.
- Edit existing `example/chat_completions.dart` and `example/models.dart` to demonstrate subscription-only production construction and the safe binding check.
- Edit existing `pubspec.yaml` to declare only Android and iOS under the package `platforms` field while preserving Dart `^3.13.0` and `http ^1.6.0`.
- Edit existing `CHANGELOG.md` so `0.1.0` includes the subscription/custom binding contract and first-release verification.
- Edit existing `.gitignore` with narrow negations for the mobile fixture's Gradle wrapper scripts and JAR so a clean checkout retains the runner required by the Android build gate.
- Add **new** `.gitleaks.toml` at the existing repository root. Allowlist only the two tracked localhost TLS private-key fixtures by exact path and document that they are non-production test keys.
- Add **new** `tool/install_gitleaks.sh` under a **new** root `tool/` directory. It downloads Gitleaks `8.30.1` only for reviewed Linux/Darwin x64/arm64 tuples, verifies the release SHA-256 before extraction, and installs into a caller-supplied temporary directory rather than a global location.
- Edit existing `.github/workflows/ci.yml` to add a secret-scan job using the repository installer and Gitleaks `8.30.1`. Its pinned `actions/checkout` step uses `fetch-depth: 0`, proves `git rev-parse --is-shallow-repository` is `false`, and fails if complete history is unavailable. Add `dart doc --validate-links` to the Dart matrix.

## Deterministic test matrix

Preserve and rerun every existing contract:

- immutable request bytes and allowed headers;
- invalid identity, body octets, protected headers, roots, credentials, caller identity, and limits;
- reserved protocols fail before body inspection and dispatch;
- initial, awaiting-header, between-chunk, paused, never-listened, and close cancellation;
- borrowed client remains open after auth close;
- one fixed route and protected header injection;
- redirect refusal and safe response metadata;
- concurrent conversation identity isolation;
- bounded streaming and catalog bodies;
- synchronous executor/listener failure redaction;
- local TLS redirect, incremental stream, and connection-loss one-receipt behavior;
- catalog requests omit authorization and session identity.

Add the binding cases from [01-endpoint-binding-contract.md](01-endpoint-binding-contract.md). Assert dispatch count at the recording executor, not only auth-method invocation count. Rejected custom clients must have an empty executor request list.

Add a two-request hermetic provider-shaped tool exchange using opaque `deepseek-v4-flash` request bodies. It does not decode model semantics in production. The test records two executor requests and proves:

- both carry the same `x-opencode-session` value and user agent;
- each provider-level `send` produces exactly one executor dispatch;
- the second body represents a distinct tool-result turn supplied by the fixture;
- neither cancellation nor injected connection loss creates a third dispatch;
- no provider guard case reaches request construction or the executor.

## Live gate

Keep `test/live_test.dart` opt-in with `OPENCODE_AUTH_LIVE_TEST=true`, exact `OPENCODE_AUTH_LIVE_MODEL=deepseek-v4-flash`, and a test-launcher-only `OPENCODE_GO_API_KEY`. Production library code must not read the environment.

Wrap the real `IOClient` in **new** `test/support/counting_client.dart` and pass it through the existing non-barrel executor seam. Use the same `IOClient` as `OpenCodeAuthOptions.client` and as the wrapper's delegate. The wrapper delegates each request once, records only an integer count plus in-memory equality checks for expected session/user-agent values, and never prints or stores header values in retained evidence. Teardown closes the auth client first and then closes the counting wrapper exactly once; the wrapper closes the single `IOClient`, which is not closed independently.

For the first and second tool requests:

1. retain one random, unprinted conversation ID and one `opencode-auth-dart-live-test/0.1.0` caller identity;
2. require one forced synthetic `lookup_file` call from the first request;
3. send the returned assistant tool call plus synthetic result in the second request;
4. require a non-empty final assistant message and normal stop;
5. after each `send`, require the counting executor to increase by exactly one;
6. after both, require two total dispatches and equality of captured session/user-agent values without printing them.

Keep the existing streaming and cancellation stages. Count those as distinct explicit requests and require one dispatch for each. For cancellation, extend the test-only counting wrapper with a one-shot barrier: call the real `IOClient.send` exactly once, signal that dispatch began, and withhold its result from the auth client until the test cancels. The test waits for that signal, cancels the same request, requires `OpenCodeCancelledException` and a count of one, releases the barrier in `finally`, and drains/cancels any late delegated response without starting another request.

An inconclusive cancellation is release-blocking even if the Dart test process otherwise exits successfully. The operator may launch a fresh entire live test again after a transient external failure, but neither the test nor auth layer retries a request internally. Any auth, quota, rate, model, protocol, policy, or network failure remains typed/redacted and blocks release. Do not substitute another model/root/account.

Retained live output is limited to UTC date, package/Dart/http versions, public model and protocol, stage name, dispatch count, terminal category, and pass/fail. Exclude credentials, session/tool IDs, request/response content, headers, URLs, account metadata, and raw exceptions.

## Mobile gate and exact supported tuple

The intended release tuple is:

- package `opencode_auth` `0.1.0`;
- model `deepseek-v4-flash` over `OpenCodeProtocol.chatCompletions`;
- Flutter 3.47.1 and bundled Dart 3.13.1;
- `http` 1.6.0 with borrowed `IOClient`;
- physical iPhone 12 with the exact tested iOS version recorded publicly, while the device identifier remains private;
- physical AYN Thor with the exact tested Android/firmware version recorded publicly, while the device identifier remains private.

Provision Flutter 3.47.1 because this checkout currently has no `flutter` executable. From `example/mobile_smoke/`, generate the absent runners with the pinned toolchain and fixed test-only organization, then review every resulting diff:

```sh
flutter create --platforms=android,ios --project-name opencode_auth_mobile_smoke --org com.mattsp1290 .
```

Audit and record the generated Android application ID, iOS bundle identifier, Android min/compile SDK, and iOS deployment target. Require compatibility with the named physical devices. Require Android Internet permission for fixture networking. Keep iOS localhost TLS trust inside the test's `SecurityContext`; do not add a broad App Transport Security exception. Keep signing team, provisioning profiles, device IDs, `local.properties`, Pods, and generated secrets untracked. Review `.gitignore` coverage and commit only reproducible runner source/toolchain metadata required to execute the fixture.

Add exact negations after the existing broad Android ignores for `example/mobile_smoke/android/gradlew`, `example/mobile_smoke/android/gradlew.bat`, and `example/mobile_smoke/android/gradle/wrapper/gradle-wrapper.jar`. Require `git ls-files` to show those files and the remaining reviewed Android/iOS runner inputs. From a fresh clone of the candidate commit, provision Flutter 3.47.1, run `flutter pub get`, and run both no-sign Android/iOS build commands before publication; a build that works only in the generation checkout does not pass.

Then run:

```sh
flutter pub get
flutter analyze
flutter test
flutter test integration_test/opencode_auth_smoke_test.dart -d <iphone-12-id>
flutter test integration_test/opencode_auth_smoke_test.dart -d <ayn-thor-id>
flutter build ios --no-codesign
flutter build apk --debug
```

The fixture keeps local TLS requests explicitly custom and verifies binding classification. It preserves stable conversation identity across host reconstruction, distinct concurrent identities, redirect refusal, cancellation, and exactly one server receipt for disconnect during upload, before response, and after headers. Builds do not replace physical-device tests.

Record only date, device model, public OS/firmware version, Flutter/Dart/http/package versions, `IOClient`, test case, and pass/fail in the README/release response. Never retain device IDs, credentials, session values, headers, bodies, generated model/tool content, or raw failures. If either device or exact toolchain is unavailable, stop before publication and response completion.

## Secret, archive, docs, and CI gates

Configure Gitleaks so the exact tracked localhost certificate keys are the only path-scoped exceptions. Do not use a broad regex or directory allowlist. The CI secret-scan checkout must use `fetch-depth: 0`; fail unless `git rev-parse --is-shallow-repository` prints `false`. Run an explicit full-history scan with redaction in CI and a working-tree scan before publication. Any new finding blocks publication until removed or specifically reviewed; do not paste the finding's secret text into logs, plans, or the response.

Use Gitleaks `8.30.1` for local and CI scans. The installer supports and verifies these official archives: Linux arm64 `e4a487ee7ccd7d3a7f7ec08657610aa3606637dab924210b3aee62570fb4b080`, Linux x64 `551f6fc83ea457d62a0d98237cbad105af8d557003051f41f3e7ca7b3f2470eb`, Darwin arm64 `b40ab0ae55c505963e365f271a8d3846efbc170aa17f2607f13df610a9aeb6a5`, and Darwin x64 `dfe101a4db2255fc85120ac7f3d25e4342c3c20cf749f2c20a18081af1952709`. Reject every other OS/architecture. Before both scan commands require the temporary binary's version output to identify `8.30.1`. CI calls the same installer instead of a separately versioned action, so configuration semantics match local release checks.

The CI action must use a full immutable action commit, not a mutable tag. Record the human-readable action version in a workflow comment. Keep workflow permissions read-only and do not add live credentials to ordinary CI.

Run API documentation generation after the shared-library conversion. Inspect the generated symbol index or analyzer output to confirm the public barrel contains `OpenCodeEndpointBinding`, `OpenCodeAuthOptions`, and `OpenCodeAuthClient.endpointBinding`, and excludes `openCodeTransportApiKey`, `serviceRoot`, `_apiKey`, and `_serviceRoot`.

Run `dart pub publish --dry-run` and inspect the archive manifest. It must include only intended root documentation/examples/library files, exclude tests, reviews, `.agents`, mobile fixture, CI, and local artifacts according to existing `.pubignore`, and report zero warnings.

## Acceptance criteria

- Every deterministic test passes on Dart 3.13.1 and the current stable Dart matrix entry.
- Provider-shaped rejection proves zero dispatch for every non-subscription category.
- Live tool exchange records exactly two dispatches for two tool-round sends with stable identity.
- Cancellation and every connection-loss stage remain one-dispatch outcomes with no fallback or alternate root.
- Both physical device suites and builds pass on the exact recorded tuple.
- Secret scan, docs, and publish dry-run pass with redacted output and no unintended surface/archive files.
- README, examples, changelog, public API, package metadata, and tests use the same binding names and support claims.

## Risks and exclusions

The counting live executor uses a non-barrel test seam but delegates to the same `IOClient` used by production construction. Treat it only as test instrumentation; do not export counters or diagnostics in production.

Gitleaks can produce false positives from deliberate canaries and localhost keys. Allowlist only exact reviewed fixtures, and prefer changing synthetic canaries over weakening rules. Secret scanning does not authorize committing live evidence.

Do not expand platform claims when desktop tests happen to pass. Do not add Flutter or Genkit dependencies to the production package.
