# OpenCode Go transport for Dart

Status: Ready

Planning deliverable only. The Dart package, tests, release, and Beans response have not been implemented.

## Application context

```json
{
  "application_context": {
    "has_active_users": false,
    "backward_compatibility_required": false,
    "feature_flags": "not-applicable",
    "confirmation_digest": "9a3ed660597762df44d6485067d25df9a62886aec489db7b7c6dbb5ba5238bd3",
    "confirmed_at": "2026-09-13T03:13:42Z"
  }
}
```

The user confirmed that this new library has no active users and no backward-compatibility obligation. No feature flags, migrations, or legacy API adapters are required. This decision does not relax Rook's persistence or security acceptance criteria.

## Outcome and success criteria

Create the pure-Dart `opencode_auth` package requested by Beans request `opencode-auth-dart-r-ugiz`. It authenticates bounded OpenCode Go Chat Completions traffic without owning native model schemas, tool execution, conversation storage, or API-key storage.

Implementation succeeds when all of the following are true:

- A host injects an API key, the supported native `package:http` `IOClient`, a caller-specific user agent, and a stable conversation ID without environment or desktop credential discovery.
- The package constructs only the normalized `https://opencode.ai/zen/go/v1/chat/completions` destination by default, injects bearer authentication, `User-Agent`, and `x-opencode-session`, and refuses redirects.
- Request bodies and successful response bytes pass through unchanged and exactly once. The package never retries or selects another model, protocol, origin, or billing root.
- Cancellation aborts dispatch or an active response stream, and response/request byte limits fail with typed local errors.
- Authentication, quota, rate-limit, policy/model, redirect, cancellation, response-limit, protocol, and network failures have redacted typed classifications.
- Hermetic tests cover security, identity, concurrency, streaming, cancellation, and failure ownership. An opt-in live test completes a two-request tool exchange with exact model `deepseek-v4-flash` through the implemented Dart client.
- A clean consumer without a local path override resolves an immutable published pin. The first-class Beans request is then updated with maintainer, public names, pin, toolchain/platform tuple, verification summary, and known limits.

## Change type and affected areas

This is a greenfield Dart library and release-readiness change. At `a3c264bde9a1e5a8ce13876fc27eb2d08d096ce2`, the repository contains only `README.md`, `LICENSE`, and `.gitignore`; all package source, tests, examples, analysis configuration, and CI are new.

Affected areas:

- package metadata and public exports;
- configuration, URI/identity validation, and protocol selection;
- authenticated HTTP dispatch and response-stream lifecycle;
- bounded error decoding and public model-catalog metadata;
- hermetic, live, mobile-consumer, and publication verification;
- the existing external Beans request that blocks Rook's provider work.

## Decisions

1. Keep native Chat Completions JSON and SSE decoding in the future provider adapter. This library accepts opaque bytes and returns opaque streamed bytes.
2. Expose a high-level authenticated dispatch method instead of an unrestricted credentialed `http.Client`. The library constructs the destination internally, so a caller cannot redirect credentials by supplying a URL.
3. Accept a borrowed `IOClient` explicitly for the first production contract. This satisfies HTTP-client injection while excluding retry wrappers from the supported boundary. The host closes it after closing this library. A non-exported internal test seam accepts recording executors without widening production support.
4. Use a package-owned cancellation token with synchronous state, then bridge its non-erroring completion future into `http.AbortableRequest`. `IOClient` documents abort support and is the initial native consumer implementation. `RetryClient` is forbidden because invisible resubmission violates the request.
5. Represent Chat Completions, Messages, and Responses in the public protocol enum. Only Chat Completions is enabled in the initial support table; selecting another value fails locally before body consumption or dispatch.
6. Do not add a credential-store interface. The host reads secure storage and injects the key; this package never persists, refreshes, clears, or discovers credentials.

Rejected alternatives: copying Codex device login and refresh machinery assigns the wrong credential lifecycle; returning a general credentialed HTTP wrapper enlarges the exfiltration surface; parsing model JSON here duplicates the provider adapter; environment fallback violates the mobile contract; automatic retry can double-charge or duplicate a tool turn.

## Target control flow

```text
host secure storage ──API key──┐
Rook conversation store ──stable ID──┼─> OpenCodeAuthClient.send(...)
provider adapter ──opaque Chat JSON───┘      │
                                             ├─ validate identity/protocol/limits
host-injected package:http IOClient <────────┤  construct fixed endpoint + headers
                                             └─ one abortable POST, no redirects/retry
                                                        │
OpenCode Go Chat Completions <── opaque bytes ──────────┘
```

The future provider adapter owns exact `deepseek-v4-flash` selection, Chat Completions messages/tool-call correlation, SSE decoding, and replay of native assistant state. Rook owns durable conversation IDs and secure key storage.

## Scope, constraints, and non-goals

In scope: one authenticated inference route, public model listing as descriptive metadata, strict HTTPS roots, caller/session validation, bounded request and response bytes, cancellation, typed safe failures, examples, CI, a live tool-loop gate, and a clean-consumer publication gate.

Constraints: use the subscription root `https://opencode.ai/zen/go/v1`, not the Zen pay-as-you-go root; use exact model `deepseek-v4-flash` in live acceptance; identify clients truthfully; send no credentials to model listing; do not capture credentials or generated content in logs, fixtures, plans, or Beans updates.

Non-goals: Messages or Responses dispatch, OAuth/device login, environment/profile reads, a credential store implementation, model-schema types, SSE parsing, tool execution, Genkit integration, conversation persistence, usage/balance modification, automatic fallback, automatic retry, or Rook application changes.

## Evidence, assumptions, risks, and gates

- Verified repository fact: the initial checkout is clean and has no Dart package structure or local contributor instructions.
- Verified reference: `opencode-auth-go` at `a3f44cca7a18028a4e6e90b021438923988539c6` validates destinations and identity, injects route-specific credentials/session headers, passes streams through, performs no retry, and bounds catalog/error bodies.
- Verified upstream fact on 2026-09-13: OpenCode documents `deepseek-v4-flash` on `.../chat/completions` and requires a host-specific user agent plus stable `x-opencode-session` per conversation.
- Verified planning evidence on 2026-09-13: a redacted two-request synthetic tool exchange for exact model `deepseek-v4-flash` completed through the subscription route. This curl probe did not use the future Dart implementation and is not its release gate.
- Verified toolchain gap: `dart` and `flutter` are not on PATH in this checkout environment. WP1 must install or select the supported Dart SDK before dependency resolution or tests can run.
- Non-blocking assumption: Dart `^3.13.0` and `http ^1.6.0` will form the initial tuple, matching the sibling Dart package's floor and the inspected current abort API. WP1 must resolve and record the lockfile with the selected installed SDK; a resolution failure returns to the maintainer.
- Risk: an injected `IOClient` and its underlying `dart:io` client are trusted code and can observe credentials or apply proxy/logging policy. Retry wrappers and arbitrary `http.Client` implementations are outside the public production contract. The Rook conformance gate proves one server receipt for the supported tuple under connection loss.
- Risk: service model lists and endpoint assignments can change. The package does not infer protocol/tool support from the catalog. A failed live gate blocks release and is not permission to substitute a model.

There are no unresolved blocking planning decisions. Library implementation may start. Publication and the Rook unblock response remain stop/go gated on the evidence in [05-verification-and-request-response.md](05-verification-and-request-response.md). The selected initial mobile tuple is Flutter 3.47.1 / Dart 3.13.1 / `http` 1.6.0 `IOClient` on iPhone 12 and AYN Thor; inability to provision either target blocks Rook-ready publication without blocking WP1–WP3.

## External request

Canonical record: Beans request `opencode-auth-dart-r-ugiz`, resolved with `bn request show opencode-auth-dart-r-ugiz` from this repository. Its hub-relative path is `projects/opencode-auth-dart/requests/opencode-auth-dart-r-ugiz-opencode-go-subscription-transport-for-rook.md` under the configured Beans hub.

Matt is the decision/creation owner and prospective package maintainer until another maintainer accepts. Rook is the confirmed intended first consumer; no production adoption exists. The request blocks Rook's provider work. Creating this plan does not accept, implement, close, or satisfy the request. WP4 defines the exact future unblock evidence.

## Document map

- [01-evidence-and-readiness.md](01-evidence-and-readiness.md): source pins, live evidence, package constraints, and implementation gates.
- [02-package-contract.md](02-package-contract.md): WP1 metadata, public API, identity, routes, and lifecycle ownership.
- [03-secure-stream-transport.md](03-secure-stream-transport.md): WP2 authenticated dispatch, confinement, limits, cancellation, and concurrency.
- [04-catalog-errors-and-tests.md](04-catalog-errors-and-tests.md): WP3 catalog, typed errors, hermetic test matrix, and CI.
- [05-verification-and-request-response.md](05-verification-and-request-response.md): WP4 examples, live tool loop, device tuple, publication, and Beans response.
- [06-execution-handoff.md](06-execution-handoff.md): dependency order, parallel boundaries, gates, and definition of done.
