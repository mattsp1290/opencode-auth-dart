# WP3 — Catalog, typed failures, and repository verification

Goal: add bounded public discovery, safe failure classification, complete hermetic coverage, and CI. Prerequisites: WP1; catalog/error work may overlap WP2 behind the fixed client contract.

## Change surface

All paths/symbols are **new/proposed**, anchored to the repository root or WP1-created directories:

- `lib/src/catalog.dart`: proposed `OpenCodeModel` and bounded catalog decoder.
- `lib/src/errors.dart`: proposed sealed `OpenCodeAuthException` family and HTTP classifier.
- `lib/src/client.dart`: connect `listModels` and non-2xx decoding.
- `test/catalog_test.dart`, `test/errors_test.dart`, `test/integration_test.dart`: catalog/error matrices and full public-seam fixtures.
- `.github/workflows/ci.yml`: format, analyze, test, and package checks against the minimum and one current Dart SDK.

## Catalog behavior

`listModels({OpenCodeCancellationToken? cancellationToken})` synchronously checks cancellation/open state, registers in WP2's shared operation registry, and issues one fresh `http.AbortableRequest` GET to canonical `/models`. It sends `Accept: application/json` and the configured truthful user agent, but never sends authorization, `x-api-key`, `x-opencode-session`, cookies, or a conversation identifier.

Read at most 8 MiB plus one limit-check byte, cancel the response stream on overflow/failure, and decode a single JSON object. Cancellation before headers, during body read, overflow, stream/read failure, parse failure, and client close each locally settle once and remove the registry entry. A late response/error follows WP2's detached cleanup rules. Require `object == "list"`, a non-null list `data`, and a nonempty string `id` for each entry. Accept an empty list, unknown fields, duplicate IDs, and original order. Validate types for known optional `object`, `created`, and `owned_by` fields. Reject malformed entries, null required data, trailing JSON, and partial results with fixed local errors.

The result is descriptive public metadata only. It does not claim API-key validity, account admission, route, tool support, context length, price, quota, or fallback eligibility. Do not filter to known IDs or infer `OpenCodeProtocol` from a model name.

## Error contract

The proposed sealed hierarchy includes:

- `OpenCodeConfigurationException` and `UnsupportedProtocolException` for local failures;
- `OpenCodeAuthenticationException`;
- `OpenCodeQuotaException`;
- `OpenCodeRateLimitException` with optional validated `retryAfter`;
- `OpenCodeModelException` and `OpenCodePolicyException`;
- `OpenCodeRedirectException`;
- `OpenCodeNetworkException`;
- `OpenCodeCancelledException`;
- `OpenCodeRequestLimitException` and `OpenCodeResponseLimitException`;
- `OpenCodeProtocolException` for malformed catalog/error protocol data;
- `OpenCodeHttpException` with status and local `unknown` classification.

For every non-2xx, consume at most 64 KiB plus one check byte and stop/cancel the stream. Parse only exact bounded `error.type` and `error.code` strings. Recognize the Go reference's current categories: `AuthError`; `CreditsError`, `MonthlyLimitError`, `UserLimitError`, `GoUsageLimitError`, `FreeUsageLimitError`, `BlackUsageLimitError`; `RateLimitError`; `ModelError`; `RegionError`; `DataPolicyError`; plus common native `authentication_error`, `invalid_api_key`, `insufficient_quota`, and `rate_limit_error`.

If fields are missing, unknown, malformed, or conflicting, return unknown HTTP classification with the status. Do not infer authentication/quota solely from status 401/403/429. Parse one unambiguous `Retry-After` delta or HTTP date with an injected test clock; reject duplicates, negative/overflowing values, and oversized text.

Exceptions contain only fixed codes, status, safe category, and validated retry duration. They never contain upstream messages/codes, raw response bodies/headers, URLs supplied by users, credentials, sessions, tool IDs, or wrapped client exception text.

## Test matrix

- Catalog: observed shape, empty list, duplicate/order preservation, future fields, wrong/missing/null known fields, malformed/trailing JSON, exact/over limit, initially cancelled, close/cancel during headers and body, late response/error, stream read failure, non-2xx, and registry cleanup.
- Errors: each exact mapping, multiple meanings under 401/429, unknown/conflicting/native envelopes, HTML/malformed/oversized/truncated bodies, retry seconds/date/past/duplicate/overflow, and safe `toString` canaries.
- Integration: public options → client → request → recording transport → two-chunk response for exact Chat route. The fixture checks no model JSON decoding, exact body preservation, and no catalog credentials.
- Security: internal-executor errors and response fields containing key/session/body canaries do not escape through public exception properties or text. Success response metadata exposes only a 2xx status and optional `content-type` after requiring one non-comma-containing visible-ASCII value of at most 256 bytes; request, URL, reason phrase, locations, cookies, duplicate/combined/invalid content types, and other headers remain inaccessible.
- Lifecycle: cover listened, never-listened, paused, explicitly canceled, and auth-client-closed response states. Await local controller/subscription cleanup without requiring a paused consumer to resume, and leave no active timers or network clients.

## CI and acceptance

CI runs on Linux using the supported minimum Dart SDK and one current stable SDK selected during WP1. Pin action revisions to immutable commits. Run:

```sh
dart pub get
dart format --output=none --set-exit-if-changed .
dart analyze --fatal-infos
dart test
dart pub publish --dry-run
git check-ignore pubspec.lock && exit 1 || true
git ls-files --error-unmatch pubspec.lock
```

Add an isolated import/compile fixture in CI or a test-controlled temporary directory that imports only `package:opencode_auth/opencode_auth.dart`. It must not rely on sibling checkouts, local path overrides, Flutter, environment credentials, or network access.

Acceptance: all deterministic tests pass without `OPENCODE_GO_API_KEY`; CI detects formatting/analyzer failures; `pubspec.lock` is tracked despite the repository's initial `*.lock` ignore rule; the package archive includes only intended library/example/docs/license files; production dependencies contain `http` and its transitive graph only, with no Flutter, Genkit, storage, retry, or protocol SDK dependency.
