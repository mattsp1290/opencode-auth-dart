# Execution handoff

Status: Ready for local implementation. Implementation has not started. Re-read repository guidance and status before editing because this greenfield checkout may change after planning.

## Ordered work packages

| Order | Package and bounded result | Paths and symbols | Prerequisites / gate |
| --- | --- | --- | --- |
| 1 | [WP1: package contract](02-package-contract.md) — package resolves and local validation API is fixed | **New** `pubspec.yaml`, lockfile, analysis config, public barrel, cancellation/options/client/protocol/request/response/errors sources and contract tests | G1 toolchain; then G2 |
| 2a | [WP2: secure transport](03-secure-stream-transport.md) — one credential-confined, abortable, byte-preserving Chat POST | **New** transport/endpoint sources, transport fixtures/tests; proposed `send` integration | WP1; then G3 |
| 2b | [WP3: catalog and errors](04-catalog-errors-and-tests.md) — bounded discovery and safe typed failures | **New** catalog/error sources, tests, CI; proposed `listModels` | WP1; may run beside WP2 with one owner for shared client/errors files |
| 3 | Integrate WP2/WP3 — full hermetic public seam and package archive pass | All new source/tests/CI | Both branches/work packages; G4 deterministic half |
| 4 | [WP4: verification and response](05-verification-and-request-response.md) — examples, exact-model live evidence, selected mobile tuple, immutable pin, Beans response | Existing `README.md`; **new** changelog/examples/live test/mobile fixture; external request update after release | Integrated package; G4 live and G5 stop/go gate |

Suggested reviewable commits follow WP1, WP2, WP3/integration, and WP4. These are planning boundaries, not existing branches, issues, or PRs.

## Parallelization and ownership

WP2 and WP3 may proceed in parallel only after WP1 signatures are committed. Assign one implementer to shared `lib/src/client.dart` and `lib/src/errors.dart`, or sequence edits to prevent contract drift. Do not run concurrent live calls against the subscription. The maintainer owns final security, release, and Beans-response judgment.

The external request has no linked Beans implementation issue. Before execution tracking, create/link issues through `bn` only if the maintainer wants tracker state; this plan does not authorize or claim those issue mutations.

## Verification gates

1. Toolchain gate: `dart --version` records the selected supported SDK; `dart pub get` resolves without overrides.
2. WP1 gate: local validation, package-owned synchronous cancellation, immutable inputs, unsupported protocols, close ownership, and restart/session reconstruction tests pass with zero network dispatch.
3. WP2 gate: internal-executor and real-local-`IOClient` tests prove fixed origin, no redirect, exact headers/body, incremental bounded stream, typed mid-stream failures, never-listened/paused close behavior, bounded close and late cleanup, concurrent session isolation, and no wire resubmission across staged connection loss.
4. WP3 gate: catalog/error matrices pass; exceptions remain redacted; catalog sends no credentials; CI and publish dry-run pass.
5. Live gate: exact `deepseek-v4-flash` completes a two-request tool exchange and a streaming completion through the implemented public API. Planning curl evidence does not substitute.
6. Consumer gate: Rook-shaped persistence/identity and one underlying server receipt under connection loss pass with Flutter 3.47.1 / Dart 3.13.1 / `http` 1.6.0 `IOClient` on iPhone 12 and AYN Thor. Missing target access blocks Rook-ready publication and requires Matt/Rook implementer action.
7. Publication gate: recompute the application-context SHA-256 from the exact NUL-separated record and require it to match `00-overview.md`; verify every document link/path; resolve an immutable pin in a clean consumer without path overrides; then update the reviewed Beans request with complete evidence.

Run the final local gate from repository root:

```sh
dart pub get
dart format --output=none --set-exit-if-changed .
dart analyze --fatal-infos
dart test
dart pub publish --dry-run
```

Run the live command exactly as documented by the implemented test, with `OPENCODE_GO_API_KEY` injected at execution time. Never include the value in command transcripts or test output.

## Failure, recovery, and rollback

- A deterministic defect returns to its owning work package and reruns the smallest affected gate plus the final suite.
- A live auth/quota/rate/service failure remains typed and redacted. It blocks release but does not authorize fallback or automatic replay.
- Cancellation or connection loss settles the call as incomplete. The host decides whether a user explicitly retries; the library never resubmits.
- Before publication, rollback is a normal revert of the relevant new commit. No stored data or configuration migration exists.
- After publication but before Rook adoption, withdraw the proposed pin in the request and publish a corrected immutable version. Never retag an existing immutable release.
- After Rook pins a release, rollback occurs in the consumer dependency pin. Conversation IDs and keys stay host-owned and require no library data rollback.

## Definition of done

- The public `opencode_auth` package and its documented symbols exist at an immutable usable pin.
- Production code depends on `http` only and contains no Flutter, Genkit, model-schema, retry, OAuth, environment, or storage integration.
- Only Chat Completions dispatch is enabled. Exact request/response bytes, session identity, and caller identity survive every tool-loop request.
- Invalid configuration and unsupported routes fail before dispatch. Redirects cannot forward library-injected credentials through supported clients.
- Request/response limits and cancellation terminate public streams and release operation state. Explicit response cancellation handles never-listened and paused streams. Detached cleanup consumes late results. The supported `IOClient` tuple proves no wire resubmission after staged connection loss.
- Typed errors distinguish required classes without exposing credentials, identifiers, bodies, raw upstream messages, or injected-client text.
- Default checks are credential-free. Exact-model live, Rook-shaped persistence, platform-client, and clean-consumer gates have recorded redacted results.
- Beans request `opencode-auth-dart-r-ugiz` names the maintainer, public API/package, pin, tuple, verification, and limitations. Rook can begin its separate provider-adapter work without a local override.

## Deferred work

Messages and Responses routes, model-schema/SSE/tool adapters, Genkit integration, credential storage UI, OpenCode login/key management, automatic routing, balance configuration, wider model tests, and Rook application integration remain separate work. Enabling another protocol requires current official evidence, deterministic native-route tests, live tool/stream verification, and a public support-table change.

First implementation action: install or select the Dart SDK and create the WP1 `pubspec.yaml` with a resolving `http` dependency tuple.
