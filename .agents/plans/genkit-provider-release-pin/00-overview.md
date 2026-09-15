# Genkit provider release pin

Status: **Ready**

This is a planning deliverable. The endpoint-binding API, verification changes, hosted release, and dependency response have not been implemented.

## Application context

```json
{
  "application_context": {
    "has_active_users": false,
    "backward_compatibility_required": false,
    "feature_flags": "not-applicable",
    "confirmation_digest": "5c007cf19e1395f63308e3da6315d8eb87bbca5e154f6956b0b9446a42c2fea3",
    "confirmed_at": "2026-09-14T13:51:33Z"
  }
}
```

The user confirmed that the package has no active users or external consumers and that backward compatibility is not required. No feature flag, configuration migration, deprecation period, or legacy constructor is required. The named Genkit project and Rook are prospective consumers, so the first hosted contract must still fail closed.

## Requested outcome and success criteria

Publish `opencode_auth` `0.1.0` as the first immutable hosted release with a provider-verifiable OpenCode Go subscription binding. A provider that receives an already-constructed `OpenCodeAuthClient` can read `OpenCodeAuthClient.endpointBinding` and accept only `OpenCodeEndpointBinding.subscriptionGo` before it calls `send`. Custom construction remains available for hermetic tests and explicit custom consumers, but it can never claim the subscription binding, even when given the production URL as text.

Implementation succeeds only when all of the following are true:

1. Subscription construction selects the package-owned `https://opencode.ai/zen/go/v1` root and reports only `OpenCodeEndpointBinding.subscriptionGo`.
2. Custom construction validates a caller-supplied HTTPS root, keeps that root private, and reports only `OpenCodeEndpointBinding.custom`.
3. No public getter, exported helper, exception, or `toString()` returns an endpoint URL or credential. The internal credential access helper is no longer importable as a public identifier from `package:opencode_auth/src/...`.
4. Provider-shaped tests accept a subscription client and reject custom, synthetic pay-as-you-go, wrong-host, and custom-with-production-text clients before `send`; the rejected cases record zero executor dispatches.
5. Only `OpenCodeProtocol.chatCompletions` can reach I/O. Reserved `messages` and `responses` values fail before body inspection and dispatch.
6. The existing transport retains injected caller identity, stable `x-opencode-session`, byte preservation, bounds, cancellation, borrowed-client ownership, redirect refusal, and one-dispatch/no-retry behavior.
7. The two-request live `deepseek-v4-flash` tool exchange uses one generated unprinted conversation ID and one caller identity, and a counting executor records exactly one dispatch for each `send`.
8. Formatting, analysis, unit, TLS transport, live, Android/iOS mobile smoke, secret scanning, API documentation, package dry-run, and clean hosted-consumer gates pass with redacted evidence.
9. The reviewed response at `$HOME/.agents/projects/opencode-auth-dart/responses/2026-09-14-genkit-provider-release-pin.md` records maintainer acceptance, exact public symbols, hosted version, tag, source commit, supported tuple, verification results, and known limits.

## Change type and affected areas

This is a breaking public-API hardening, security-boundary, test-infrastructure, documentation, and first-release change. The user-confirmed lack of consumers permits removing the URL-exposing `serviceRoot` getter and constructor parameter instead of preserving an ambiguous compatibility surface.

Affected areas:

- the library boundary that currently separates `lib/src/options.dart` from `lib/src/client.dart` and therefore requires a publicly named credential helper, plus the request-limit constant imported by `lib/src/request.dart` from the options library;
- options construction, endpoint routing, public exports, string representations, and client inspection;
- unit, provider-shaped, real-I/O, live, and Flutter mobile fixtures;
- credential-free CI and secret scanning;
- package metadata, README, changelog, API docs, version tag, pub.dev publication, clean-consumer proof, and the external response.

## Repository-grounded findings

- The repository is clean at `1d4df9c897dc030f6e46ee72b84824f79779131c`, matching the request's inspected revision. `main`, `origin/main`, and `origin/opencode-go-transport` resolve to that commit.
- `OpenCodeAuthOptions` currently defaults to the subscription root but also accepts any validated HTTPS `serviceRoot`. Its public `serviceRoot` getter and `toString()` disclose the normalized URL.
- `OpenCodeAuthClient` stores options privately and exposes no endpoint policy, so a provider cannot validate a borrowed client before dispatch.
- `openCodeTransportApiKey` is omitted from the barrel but remains a publicly named top-level function in `lib/src/options.dart`; a consumer can directly import that source library. A shared Dart library with `part` files is needed if client code must access private option fields without a public credential accessor.
- `OpenCodeInferenceRequest` rejects unsupported protocols during construction before copying the body. `OpenCodeAuthClient.send` repeats the support check before operation creation.
- `test/real_io_transport_test.dart` and `example/mobile_smoke/integration_test/opencode_auth_smoke_test.dart` need custom HTTPS roots for local TLS fixtures. Their construction must move to the explicit custom API without weakening production binding.
- `test/live_test.dart` already performs the exact two-request tool exchange with one session and user agent. It does not currently count underlying dispatches.
- `.github/workflows/ci.yml` runs Dart 3.13.1 and stable formatting, analysis, tests, publish dry-run, and a tracked-lockfile check. It has no secret-scan or API-doc job. Live and device gates are intentionally outside ordinary credential-free CI.
- The repository-wide `.gitignore` excludes Gradle wrapper scripts and JARs, and the mobile fixture has no generated Android/iOS runner trees. Reproducible device/build gates require narrow fixture-specific negations or verified regeneration from the pinned Flutter version.
- Gitleaks is not installed in the planning environment. Local and CI secret scans need one checksum-pinned engine and version assertion rather than an ambient executable.
- On 2026-09-14 the local Dart SDK is 3.13.1, Flutter is not installed, pub.dev returns 404 for `opencode_auth`, and the Git repository has no tags or GitHub releases. These observations must be rechecked immediately before publication because names and remote state can change.
- The baseline passes `dart format --output=none --set-exit-if-changed .`, `dart analyze --fatal-infos`, `dart test` with 44 passes and one skipped live test, and `dart pub publish --dry-run` with zero warnings.
- The downstream `genkit_opencode_go` plan requires this exact safe binding before authenticated integration and publication. It intends to reject any custom or uninspectable client before invoking `OpenCodeAuthClient.send`.

## Key decisions

1. Define the public enum `OpenCodeEndpointBinding` with exactly `subscriptionGo` and `custom`, and expose `OpenCodeAuthClient.endpointBinding`. This is sufficient for a borrowed-client policy check and contains no URL or credential.
2. Keep the unnamed `OpenCodeAuthOptions(...)` constructor as the subscription-only constructor. Add `OpenCodeAuthOptions.custom(...)` with a required custom root. Do not accept a binding enum and URL together, because that would let a caller label an arbitrary URL as subscription-bound.
3. Make the normalized root private and remove it from `toString()`. A custom constructor given the literal production root still has binding `custom`; subscription identity comes from the constructor path, not string comparison.
4. Add a new shared source library `lib/src/auth.dart`, convert the existing options/client files into parts of it, and move shared public byte-limit constants to a new independent `lib/src/limits.dart`. This lets the client read `_apiKey` and `_serviceRoot` without a publicly importable credential-returning helper while `request.dart` retains a valid standalone import.
5. Publish the completed first contract as `opencode_auth` `0.1.0`. The existing `0.1.0` has not been hosted, so no version migration exists. Recheck pub.dev immediately before publishing and stop if the name or version is no longer available.

Rejected alternatives: a boolean loses the extensible endpoint-policy vocabulary; accepting both an enum and arbitrary root makes the binding forgeable; deriving policy from URL equality or `toString()` repeats the downstream defect; retaining public `serviceRoot` is unnecessary without compatibility obligations; adding Genkit types or a provider-specific assertion method would put consumer policy in the transport package.

## Target control flow

```text
OpenCodeAuthOptions(...) ----------------------> binding: subscriptionGo
         |                                       private fixed root
         v
OpenCodeAuthClient.endpointBinding --safe enum--> provider preflight
                                                    |
                                      accept only subscriptionGo
                                                    |
                                                    v
                                              one send/dispatch

OpenCodeAuthOptions.custom(serviceRoot: ...) ---> binding: custom
         |                                       private validated root
         +--> provider rejects before send ------> zero dispatches
```

The auth client continues to own destination composition and protected headers. The provider owns model selection, Chat Completions JSON/SSE decoding, tool execution, retry admission, and conversation persistence.

## Scope, constraints, and non-goals

In scope: endpoint-binding construction and inspection, URL/credential encapsulation, source-library consolidation, provider-shaped rejection tests, regression and live dispatch counting, supported-tuple documentation, secret scanning, first publication, clean-consumer proof, and the request response.

Constraints: subscription requests use only the fixed OpenCode Go root; only Chat Completions dispatches; exact live model is `deepseek-v4-flash`; production accepts a borrowed `http` 1.6.0 `IOClient`; output and retained evidence exclude credentials, endpoint URLs beyond the documented public subscription route, session values, device identifiers, request/response bodies, headers, tool content, and raw upstream messages.

Non-goals: Genkit model types, Chat Completions JSON/SSE decoding in production, tool execution, model or provider fallback, automatic retry, credential storage/discovery, conversation persistence, Messages/Responses dispatch, OAuth, web support, desktop support, or changes in `genkit-providers-dart` and Rook.

## Risks, assumptions, and gates

- **Publication stop/go:** Matt or the accepted `opencode_auth` maintainer must explicitly accept the release contents and operate the first pub.dev publication. Acknowledgement alone does not satisfy the external request.
- **Registry stop/go:** immediately before tagging, require pub.dev to still return no existing `opencode_auth` package/version owned by another party. If availability changed, stop; Matt decides whether to obtain ownership or select a new package name, and the plan plus downstream request must be revised.
- **Live stop/go:** auth, quota, model, service, cancellation, network failure, or an inconclusive cancellation outcome blocks the release. A test-only barrier must witness one dispatched request becoming `OpenCodeCancelledException`. Failure never authorizes another model, route, billing root, account, fallback, or auth-layer replay.
- **Mobile stop/go:** Flutter 3.47.1 and physical iPhone 12/AYN Thor access are not available in this checkout. The release operator must provision them, record exact iOS/Android OS or firmware versions, and pass both device runs before claiming the requested tuple.
- **Security risk:** Dart `src/` paths can be imported despite barrel omissions. The shared-library change must remove the public credential-returning helper, and the package archive/API-doc inspection must verify the intended surface.
- **Test risk:** local TLS tests necessarily use custom roots. They prove transport mechanics but not subscription classification; separate binding and live tests must cover that boundary.
- **Non-blocking assumption:** `opencode_auth` remains available for a first hosted `0.1.0` release. The registry stop/go gate converts a changed result into a blocking maintainer decision.

There are no unresolved blocking planning decisions. Local implementation can start. Publication remains gated on maintainer acceptance, live/device access, registry availability, and the verified evidence in [03-release-and-response.md](03-release-and-response.md).

## External dependency request

Canonical request: `$HOME/.agents/projects/opencode-auth-dart/requests/2026-09-14-genkit-provider-release-pin.md`.

Owner: Matt / `opencode-auth-dart` maintainer. Demonstrated blocking consumer: `github.com/mattsp1290/genkit-providers-dart` through Beans request `genkit-providers-dart-r-pkzc`. Prospective downstream consumer: Rook. The request blocks authenticated provider integration, provider live acceptance, and provider publication, but not pure encoder/SSE work.

Exact unblock evidence: a reviewed response at `$HOME/.agents/projects/opencode-auth-dart/responses/2026-09-14-genkit-provider-release-pin.md` that names the accepted maintainer, package and symbols, immutable hosted version, tag and source commit, supported/tested tuple, redacted gate results, known limits, and a successful clean hosted-consumer resolution. Creating this plan does not accept or complete the request.

## Document map

- [01-endpoint-binding-contract.md](01-endpoint-binding-contract.md): public binding API, private endpoint/credential boundary, routing invariants, and compatibility treatment.
- [02-verification-contract.md](02-verification-contract.md): provider-shaped, regression, live, mobile, secret-scan, CI, and documentation evidence.
- [03-release-and-response.md](03-release-and-response.md): immutable publication, clean-consumer validation, response contract, rollback, and release gates.
- [04-execution-handoff.md](04-execution-handoff.md): dependency-ordered work packages, commands, acceptance gates, and definition of done.
