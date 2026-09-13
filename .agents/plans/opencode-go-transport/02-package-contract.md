# WP1 — Package and public contract

Goal: establish a compiling pure-Dart package with locally validated configuration, protocol selection, identity, limits, and lifecycle ownership. Prerequisite: G1 from [01-evidence-and-readiness.md](01-evidence-and-readiness.md).

## Change surface

All paths and symbols below are **new/proposed**, anchored to the existing repository root `.`, except the explicitly existing `.gitignore`:

- `pubspec.yaml`: package `opencode_auth`, initial version `0.1.0`, repository URL, Dart SDK constraint, production dependency on `http`, and test/lint dev dependencies.
- `pubspec.lock` (**new**): resolved application-style lockfile retained for repeatable repository CI; publication consumers still resolve their own compatible graph.
- `.gitignore` (**existing**): remove the blanket `*.lock` rule or add `!pubspec.lock` before dependency resolution, while retaining intentional generated-file exclusions.
- `analysis_options.yaml`: strict analyzer/lint configuration compatible with the selected SDK.
- `lib/opencode_auth.dart`: public library barrel. Export only supported consumer types.
- `lib/src/client.dart`: proposed `OpenCodeAuthClient`, dispatch API, close state, and borrowed HTTP-client ownership.
- `lib/src/cancellation.dart`: proposed package-owned `OpenCodeCancellationToken` and `OpenCodeCancellationSource`.
- `lib/src/options.dart`: proposed `OpenCodeAuthOptions`, default service root, byte limits, and validation.
- `lib/src/protocol.dart`: proposed `OpenCodeProtocol` and explicit support table.
- `lib/src/request.dart`: proposed immutable `OpenCodeInferenceRequest`.
- `lib/src/response.dart`: proposed `OpenCodeStreamResponse` with a single-subscription byte stream and sanitized metadata.
- `lib/src/errors.dart`: proposed sealed exception hierarchy, completed in WP3.
- `test/options_test.dart`, `test/client_contract_test.dart`: local validation and zero-dispatch tests.

The implementer may refine names before the first public release, but must update every plan reference, example, test, and Beans response together. Do not preserve a placeholder alias after the contract is selected because there are no compatibility consumers.

## Proposed public contract

`OpenCodeAuthOptions` requires `apiKey`, `IOClient`, and `userAgent`. It accepts an optional `serviceRoot` defaulting to `https://opencode.ai/zen/go/v1`, `maxRequestBytes`, and `maxResponseBytes`. The supported public production constructor accepts only `package:http/io_client.dart`'s `IOClient`, not `RetryClient`, `BrowserClient`, or arbitrary `http.Client`. A source-internal testing executor supports deterministic fixtures and is not exported from `lib/opencode_auth.dart`. The injected `IOClient` is borrowed: the host retains it, may share it, and closes it after `OpenCodeAuthClient.close()` settles local operations.

Define an absolute package request ceiling of 8 MiB and an absolute response ceiling of 32 MiB. `OpenCodeInferenceRequest` checks `body.length` against the request ceiling before iterating or copying, validates octets, then stores an immutable `Uint8List` copy. `OpenCodeAuthOptions.maxRequestBytes` defaults to and cannot exceed 8 MiB; `send` applies any smaller client-specific limit to the safely bounded copy. `maxResponseBytes` defaults to 8 MiB and cannot exceed 32 MiB.

`OpenCodeCancellationSource` exposes an `OpenCodeCancellationToken`, and its idempotent `cancel()` synchronously sets `token.isCancelled` before successfully completing `token.whenCancelled`. Both types have package-controlled construction; callers bridge other cancellation systems by calling the source. The future never completes with an error, so arbitrary error text cannot enter abort handling.

`OpenCodeAuthClient.send(OpenCodeInferenceRequest request)` returns `Future<OpenCodeStreamResponse>`. The request contains:

- `OpenCodeProtocol protocol`;
- nonempty `conversationId`;
- opaque `List<int> body` copied at construction;
- a header map limited exactly to one case-insensitive `content-type` entry and one case-insensitive `accept` entry;
- optional `OpenCodeCancellationToken cancellationToken`.

The initial `OpenCodeProtocol` values are `chatCompletions`, `messages`, and `responses`. Only `chatCompletions` resolves to an endpoint. The other values throw proposed `UnsupportedProtocolException` before finalizing the request body or calling the injected client. This preserves an explicit protocol dimension without claiming untested routes work.

`OpenCodeStreamResponse` exposes only `statusCode`, optional validated `contentType`, the response byte stream, and idempotent `Future<void> cancel()`. It excludes the authenticated request, URL, reason phrase, redirect history/location, cookies, and arbitrary response headers. It does not decode Chat Completions JSON or SSE. WP3 turns non-2xx responses into safe typed failures before this object is returned.

`OpenCodeAuthClient.listModels({OpenCodeCancellationToken? cancellationToken})` returns bounded proposed `OpenCodeModel` metadata. It performs a fresh unauthenticated abortable GET, joins the same close/active-operation registry as inference, and does not affect protocol/model admission.

## Validation and invariants

- API key: nonempty, already trimmed, no ASCII control characters. Never read `Platform.environment`, profiles, OpenCode CLI files, or desktop credential directories.
- User agent: 1–256 visible ASCII bytes after rejecting blank-only values. The host must use its actual application identity, such as `rook/<version>`; generic `Dart`, `http`, or package-only defaults do not satisfy consumer acceptance.
- Conversation ID: 1–256 visible non-whitespace ASCII bytes. It is opaque. The package neither generates nor persists it.
- Service root: absolute HTTPS URI with no user info, query, fragment, encoded slash/backslash/dot ambiguity, dot segments, or trailing empty ambiguity. Normalize scheme/host casing and a single trailing slash. Do not permit HTTP production exceptions.
- Route: construct `/chat/completions` and `/models` from the canonical root. Never accept an inference URL from a caller.
- Header ownership: callers may set only `content-type` and `accept`. Canonicalize names case-insensitively, reject duplicate canonical names, and require nonempty visible ASCII values of at most 4 KiB with no controls. Reject every other header, including authorization, API key, user agent, session, host, cookie, forwarding, proxy, and hop-by-hop fields.
- Body bytes: copy eagerly and require every integer to be in `0..255`; reject invalid elements before dispatch rather than relying on a downstream encoder.
- Limits: reject nonpositive configured limits and a body larger than `maxRequestBytes` before dispatch.
- Lifecycle: construction performs no network/filesystem I/O. `Future<void> close()` is idempotent, marks the auth client unusable, and locally settles active public operations without waiting indefinitely. It never closes the borrowed `IOClient` or erases the host's key.

All `toString` values and `ArgumentError` messages use field names and fixed categories only. They never include the key, session ID, body, URI input containing user info, or arbitrary injected-client errors.

## Compatibility, rollback, and exclusions

No legacy API or stored data exists. Do not add feature flags or migration code. Before publication, correct the proposed API directly. After publication, future compatibility is a separate versioning decision.

Rollback is removal/reversion of the new package work before downstream pinning. The library stores no data and has no remote configuration rollback. Rook conversation and credential persistence remain host responsibilities.

Exclude credential-store interfaces, login/logout, model request types, JSON/SSE parsing, retry policy, Genkit types, and Flutter imports.

## Tests and acceptance

- Construct valid options without I/O and expose only the normalized non-secret root and supported protocol metadata.
- Reject every invalid key, user agent, conversation ID, service root, unknown/duplicate/invalid header, invalid body octet, unsupported protocol, and size limit before the fake HTTP client records a call. Include mixed-case protected names and header control/length cases.
- Verify caller-owned input byte lists and header maps cannot mutate an in-flight request after construction. A custom oversized `List<int>` proves the fixed length check occurs before element iteration/copy, allocation, and dispatch.
- Verify an initially cancelled token, repeated cancellation, and cancellation immediately before `IOClient.send` produce zero calls. Package-owned token completion never carries an error; an arbitrary external future can affect the package only through caller-controlled `source.cancel()`.
- Verify `close()` is idempotent, rejects later sends with a fixed typed error, locally settles active operations, and does not call `close()` on the borrowed fake client.
- Reconstruct the auth client with the same host-supplied conversation ID and observe the same session header in WP2; use a different ID and observe isolation. This is the library-boundary proof for restart semantics.
- Run `dart format --set-exit-if-changed .`, `dart analyze`, and `dart test test/options_test.dart test/client_contract_test.dart`.
- Verify `git check-ignore pubspec.lock` exits nonzero and `git ls-files --error-unmatch pubspec.lock` succeeds before WP1 is committed.
