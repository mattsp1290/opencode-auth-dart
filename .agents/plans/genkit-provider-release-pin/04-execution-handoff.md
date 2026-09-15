# Execution handoff

Status: **Ready for implementation**. Implementation has not started.

Re-read repository guidance, the canonical request, `git status`, remote state, and registry availability before editing. Preserve unrelated user changes if the checkout is no longer clean.

## Dependency-ordered work packages

| Order | Work package and bounded result | Existing/proposed surface | Prerequisites and parallelization |
| --- | --- | --- | --- |
| 1 | WP1: [endpoint-binding contract](01-endpoint-binding-contract.md) — an already-built client exposes a trustworthy safe enum and no URL/credential accessor | Edit existing `lib/opencode_auth.dart`, `lib/src/options.dart`, `lib/src/client.dart`, `lib/src/request.dart`; add **new** `lib/src/auth.dart` and `lib/src/limits.dart`; proposed enum/constructors/getters; edit existing test support | Start from reconciled source. Central auth files have one owner. Nothing else should rename the API in parallel. |
| 2 | WP2: [deterministic verification](02-verification-contract.md) — provider rejection and every transport regression pass | Add **new** `test/endpoint_binding_test.dart`; edit existing option/client/transport/catalog/real-I/O tests and mobile fixture | WP1 fixed. Test files may be divided, but one owner reconciles test support and constructor use. |
| 3 | WP3: [live, mobile, docs, and CI](02-verification-contract.md) — exact model/identity/dispatch evidence and exact platform tuple | Add **new** `test/support/counting_client.dart`, `.gitleaks.toml`, `tool/install_gitleaks.sh`, and generated `example/mobile_smoke/android/` plus `ios/`; edit existing live/mobile docs, README, examples, pubspec, changelog, `.gitignore`, and CI | WP1/WP2 integrated. Live runs are sequential. Mobile work needs Flutter/devices. CI/docs can proceed while devices are provisioned. |
| 4 | WP4: [hosted release](03-release-and-response.md) — one accepted commit becomes immutable `opencode_auth 0.1.0` | Existing package metadata; proposed `v0.1.0`; external pub.dev version | All deterministic/live/mobile/security/docs/archive gates; maintainer acceptance; registry recheck; clean tree. |
| 5 | WP5: [consumer and response](03-release-and-response.md) — hosted resolution unblocks Genkit integration | **New temporary** clean consumer outside repository; **proposed new external** `responses/` directory and response at the canonical `$HOME/.agents/projects/.../responses/` path | Pub.dev version visible. Response waits for clean-consumer success and must identify WP4's exact source/hash. |

WP1 is strictly first. WP2 and the non-live documentation portions of WP3 may proceed after its public symbols are fixed. WP4 and WP5 are sequential and must not be parallelized because publication evidence determines the consumer pin and response.

## Package-level verification

After WP1, run:

```sh
dart format --output=none --set-exit-if-changed lib test/support test/options_test.dart test/endpoint_binding_test.dart
dart analyze --fatal-infos
dart test test/options_test.dart test/endpoint_binding_test.dart test/client_contract_test.dart test/transport_test.dart
```

Acceptance: the barrel compiles with the exact proposed public symbols; subscription/custom construction is unforgeable by URL input; rejected provider cases dispatch zero times; no string or exception includes credential/root canaries.

After WP2, run:

```sh
dart test test/transport_stream_test.dart test/real_io_transport_test.dart test/catalog_test.dart test/errors_test.dart
dart test
```

Acceptance: all existing behavior remains green, custom local TLS fixtures are explicitly classified custom, unsupported protocols remain pre-I/O, and cancellation/connection loss never produce an extra executor/server receipt.

After WP3 source changes, run:

```sh
dart pub get
dart format --output=none --set-exit-if-changed .
dart analyze --fatal-infos
dart test
dart doc --validate-links
gitleaks_bin_dir=$(mktemp -d)
./tool/install_gitleaks.sh "$gitleaks_bin_dir"
"$gitleaks_bin_dir/gitleaks" version
"$gitleaks_bin_dir/gitleaks" git --redact --config .gitleaks.toml
"$gitleaks_bin_dir/gitleaks" dir --redact --config .gitleaks.toml .
dart pub publish --dry-run
```

Require the version output to identify `8.30.1`, then remove only the created temporary installer directory after the scans. The CI full-history scan additionally requires a checkout with `fetch-depth: 0` and a `false` result from `git rev-parse --is-shallow-repository`; absence of the pinned engine or complete history fails G6.

Then run the opt-in live test with the implemented environment-variable contract and the exact mobile commands in [02-verification-contract.md](02-verification-contract.md). Never place credential values in commands retained in Git, reviews, plans, CI, or the response.

## Integration and release gates

1. **G1 API:** `OpenCodeAuthClient.endpointBinding` distinguishes subscription from every custom constructor path without revealing a URL.
2. **G2 encapsulation:** public docs/archive inspection finds no raw credential helper or service-root getter; direct part imports are not a usable library API.
3. **G3 deterministic:** provider-shaped, protocol, transport, error, catalog, cancellation, and real-I/O tests pass and record the required zero/one/two dispatch counts.
4. **G4 live:** exact `deepseek-v4-flash` completes the two-request tool exchange with two underlying dispatches, one stable unprinted session, and one stable caller identity. The barrier-driven cancellation separately witnesses `OpenCodeCancelledException` with exactly one dispatch; inconclusive blocks G4.
5. **G5 mobile:** Flutter 3.47.1/Dart 3.13.1/`http` 1.6.0 `IOClient` passes on the recorded iPhone 12/iOS and AYN Thor/Android firmware tuple plus both builds. A fresh clone contains the tracked Gradle wrapper and reproduces both builds.
6. **G6 security/package:** Gitleaks full-history and directory scans, API docs, and publish dry-run pass with only exact reviewed localhost-key allowlists and zero publish warnings.
7. **G7 release:** maintainer acceptance, registry availability, clean source, `v0.1.0`, full commit, pub.dev version, and hosted content hash agree.
8. **G8 unblock:** fresh hosted consumer resolves exact `0.1.0` without overrides, then the reviewed canonical response records all evidence.

Failure at G1-G6 returns to the owning work package and reruns the smallest affected checks plus the full suite. Failure at G7-G8 follows the rollback rules in [03-release-and-response.md](03-release-and-response.md). No failure authorizes fallback, retry, alternate model/root/account, skipped validation, or weakened redaction.

## Compatibility, migration, and rollout

The confirmed application context requires no backward compatibility. Remove the old `serviceRoot` argument/getter and credential helper in the same API commit. Convert every repository-owned custom-root fixture to `OpenCodeAuthOptions.custom`; add no alias or deprecation period.

There is no stored data, configuration, feature flag, or staged runtime rollout. Rollout is the immutable hosted package version plus explicit downstream pin adoption. Before adoption, rollback is a source correction; after publication, correction is a new version; after consumer adoption, rollback is a consumer pin change.

## Definition of done

- `opencode_auth` `0.1.0` is hosted and resolves to the reviewed source commit/content hash.
- The exact enum, constructor, and client getter exist through the public barrel and no URL/credential accessor survives.
- Subscription routing remains package-fixed; every custom root remains visibly custom; a provider rejects all non-subscription clients before `send`.
- Only Chat Completions dispatches. Cancellation, disconnect, redirects, and unsupported protocols never cause replay, fallback, alternate model, or alternate billing root.
- Deterministic, conclusive live cancellation/tool exchange, fresh-clone mobile, pinned secret-engine, documentation, archive, and clean-consumer gates pass on the exact recorded tuple.
- Production code remains free of Genkit types, JSON/SSE/model/tool logic, retry/fallback, credential storage, and conversation persistence.
- The external response states maintainer acceptance, exact public API, immutable pin/source, tuple, redacted results, limits, and the Genkit unblock contract.
- No plan text claims that downstream provider or Rook implementation has occurred.

## Deferred work

Genkit integration, provider encoding/SSE/tool execution, session/attempt persistence, Rook adoption, Messages/Responses protocols, other models, alternate subscription endpoints, pay-as-you-go support, browser/desktop clients, credential lifecycle, and automated first-package publication remain outside this implementation.

First implementation action: create `lib/src/auth.dart` and move options/client into one Dart library without changing runtime behavior.
