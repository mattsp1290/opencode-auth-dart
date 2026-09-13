# Evidence and readiness

Research date: 2026-09-13. Existing paths are repository-relative unless a source repository is named. Proposed paths and symbols are labeled in their work files.

## Repository and source evidence

| Source | Inspected evidence | Design consequence |
| --- | --- | --- |
| This repository at `a3c264bde9a1e5a8ce13876fc27eb2d08d096ce2` | `README.md`, `LICENSE`, `.gitignore`; no package or tests | Every Dart surface is new; no migration or compatibility adapter exists |
| Beans request `opencode-auth-dart-r-ugiz` | OpenCode Go subscription transport for Rook, priority 1, no linked issues | Local delivery needs a first-class request response and immutable consumer pin |
| Rook plan `rook-plan-ci37`, section `11-opencode-auth-dart.md` | Stable session per conversation, mobile-safe injection, bounded/cancellable streams, exact Flash route, no fallback | Split responsibility among host persistence, auth transport, and provider schema adapter |
| `opencode-auth-go` at `a3f44cca7a18028a4e6e90b021438923988539c6` | `client.go`, `endpoint.go`, `session.go`, `transport.go`, `errors.go`, `catalog.go`, tests and README | Port behavior and failure cases, not Go-specific context or `net/http` APIs |
| `codex-auth-dart` at `57a82514b6289087bd01f3b59ba107754545a6cc` | `pubspec.yaml`, `lib/src/cancellation.dart`, `errors.dart`, `http_adapter.dart`, README | Reuse pure-Dart naming, redacted exception style, cooperative cancellation, and Dart `^3.13.0` convention; omit OAuth/store code |
| `github.com/mattsp1290/eino-channels` at `355bff4a0530755e9a0f5d14ba7c2d4a6dc11908`, `docs/setup.md` and `docs/manual-smoke.md` | Fixed `deepseek-v4-flash`/Chat Completions, truthful user agent, 120-second turn deadline, restart/session smoke | Pin the first protocol/model acceptance and test restart identity without importing Go channel code |

To reproduce external inspection, set `OPENCODE_AUTH_GO_DIR`, `CODEX_AUTH_DART_DIR`, and `EINO_CHANNELS_DIR` to checkouts of the named repositories and use the immutable revisions above. The current local Eino Channels checkout is stale and lacks the cited commit. Resolve it without changing that checkout by opening the two raw GitHub files at the full immutable SHA or fetching that SHA into a temporary worktree. WP4 live-test design cannot finalize until both files open at that revision. These variables are research conveniences, not runtime configuration.

## Current authoritative contracts

- OpenCode Go documentation: `https://opencode.ai/docs/go/`. On 2026-09-13 it assigned bare model ID `deepseek-v4-flash` to `https://opencode.ai/zen/go/v1/chat/completions` and documented caller-specific `User-Agent` plus stable `x-opencode-session` requirements.
- Dart HTTP package documentation: `https://pub.dev/packages/http` and its API reference. The inspected current release is 1.6.0. It recommends injected clients and documents abort support through `AbortableRequest` for `IOClient`. The first production contract intentionally supports only native `IOClient`; browser, retry, and arbitrary implementations require a future conformance change.

Record the final dependency versions in `pubspec.lock` and README during WP1. Mutable documentation is evidence for implementation-time revalidation, not a permanent promise that all catalog models or endpoints remain unchanged.

## Redacted live planning probe

The user authorized use of the `OPENCODE_GO_API_KEY` variable loaded from the local profile. The probe kept the key in memory, used an unrecorded random session ID, capped both responses at 256 tokens and 90 seconds, and sent only synthetic content.

| Request | Model and route | Retained result |
| --- | --- | --- |
| First Chat Completions call | `deepseek-v4-flash`, bearer, stable session, planning-specific Rook user agent | request completed; finish category `tool_calls`; one `lookup_file` call |
| Second call with synthetic tool result | same model, route, session, user agent, and native assistant tool state | request completed; finish category `stop`; nonempty assistant text |

No credential, session/tool identifier, prompt/answer body, reasoning, headers, or raw errors were retained. The probe establishes current account/model/tool feasibility. It does not prove Dart transport behavior, stream cancellation, mobile behavior, or future service availability.

## Readiness gates

G1 — Toolchain: install/select Dart 3.13.x or a compatible explicitly chosen release; run `dart --version`; resolve `http` and dev dependencies without overrides. If `http 1.6.0` does not resolve against the selected SDK, the maintainer chooses and documents a supported tuple before source work proceeds.

G2 — API/security contract: WP1 tests establish strict production HTTPS roots, exact route enablement, valid identity, borrowed-client ownership, and redacted diagnostics before authenticated dispatch is implemented.

G3 — Transport: WP2 passes deterministic tests through both an internal recording executor and a real local `IOClient` HTTPS fixture. It proves no redirect follow, one wire receipt after a recorded request is deliberately disconnected, byte-preserving incremental response delivery, cancellation, limits, concurrent-session isolation, late-response cleanup, and no credential exposure through public values.

G4 — Live/package: WP3 and WP4 pass format, analyze, tests, examples, and the exact-model live two-request tool exchange through the implemented Dart client. A catalog hit alone cannot pass this gate.

G5 — Consumer/publication stop/go gate: use Flutter 3.47.1 / Dart 3.13.1 / `http` 1.6.0 `IOClient` in the proposed mobile fixture on an iPhone 12 and AYN Thor. Prove one underlying server receipt under connection loss, then publish an authorized immutable version or commit, consume it from a clean fixture without path overrides, and update the Beans request. Matt and the Rook implementer own device provisioning, signing, installation, and any tuple revision. If either target or compatible toolchain is unavailable, they must record the missing target and provision it or explicitly revise the Beans/Rook contract; Rook-ready publication remains blocked. Only completed G5 evidence unblocks downstream provider work.

G1 is the first implementation gate. The missing local Dart executable is an environmental prerequisite, not a blocking design decision.
