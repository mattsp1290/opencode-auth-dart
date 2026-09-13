# WP2 — Secure streamed transport

Goal: send one byte-preserving, abortable Chat Completions request while confining credentials and conversation identity. Prerequisite: WP1's public contract and G2.

## Change surface

All paths and symbols are **new/proposed** under existing `lib/src/` and `test/` insertion points created by WP1:

- `lib/src/transport.dart`: internal request construction, shared active-operation registry, send/cancel race state machine, response stream wrapper, and injected-client error mapping.
- `lib/src/endpoint.dart`: canonical URI/origin helpers if WP1 validation is large enough to separate.
- `lib/src/client.dart`: connect proposed `OpenCodeAuthClient.send` and lifecycle tracking.
- `test/transport_test.dart`: headers, request bytes, origin/route, redirect, single-dispatch, and concurrent identity tests.
- `test/transport_stream_test.dart`: incremental delivery, cancellation, byte caps, error mapping, and cleanup.
- `test/support/recording_transport.dart`: **new** internal deterministic executor fixture with call counts and controllable streams. It enters only through the non-exported source testing seam.

## Dispatch algorithm

1. Validate client-open state, synchronously check `token.isCancelled`, then validate supported protocol, identity, headers, body octets, and size before touching the injected client.
2. Construct an `http.AbortableRequest('POST', canonicalChatUri, abortTrigger: combinedAbort)` with copied body bytes. The combined abort future completes successfully only.
3. Set `followRedirects=false` and `maxRedirects=0` before send.
4. Set caller content headers, then overwrite package-owned `Authorization: Bearer <key>`, `User-Agent`, and `x-opencode-session`. Never set `x-api-key` for Chat Completions.
5. Register one active operation before dispatch. Recheck `token.isCancelled` immediately before `IOClient.send`; if true, settle locally and record no client call. Combine caller cancellation and client close into an idempotent internal abort completer.
6. Call `IOClient.send` exactly once. The public constructor's concrete type excludes `RetryClient` and arbitrary wrappers. Do not loop on exceptions/statuses or reconstruct/resubmit a body.
7. Race the send future with local cancellation. Map pre-response abort to proposed `OpenCodeCancelledException`. Map other transport failures to proposed redacted `OpenCodeNetworkException` without retaining the original error text.
8. Refuse every 3xx as proposed `OpenCodeRedirectException`, cancel/drain only within the bounded error policy, and never follow `Location`.
9. Decode non-2xx through WP3. For 2xx, subscribe eagerly to the upstream stream before returning `OpenCodeStreamResponse`; a bounded controller can buffer before the caller listens and gives the client ownership needed for close/cancel.
10. Count successful response bytes while forwarding each received chunk immediately. At `maxResponseBytes + 1`, abort upstream, settle once with proposed `OpenCodeResponseLimitException`, and release registry state.
11. Translate an abort-originated stream error to `OpenCodeCancelledException`. Translate every other upstream stream error to a fresh redacted `OpenCodeNetworkException`; never forward the injected exception or URI. Abort/cancel upstream and emit exactly one terminal event.
12. Caller stream cancellation completes the internal abort, cancels the upstream subscription, and releases registry state. Natural completion or error does the same cleanup without emitting a late second terminal event.

The package must not mutate or return a caller-owned request because it accepts opaque values rather than a `BaseRequest`. It must not expose the internal authenticated `AbortableRequest` through the response.

## Security and lifecycle behavior

The fixed-route API prevents a caller from sending credentials to another origin. Strict root validation prevents ambiguous origins. Redirect flags prevent the supported `IOClient` from following a server redirect. The injected `IOClient` and its underlying `dart:io HttpClient` remain trusted and can observe credentials or apply proxy/logging policy. The public production type excludes `RetryClient` and other wrappers. Connection loss returns a network failure and preserves host input for an explicit user-directed retry outside this library.

Each operation moves through `validating → sending → streaming-unlistened → streaming-listening/paused → locallySettled`. Only the first transition to `locallySettled` completes the public send future or marks its controller terminal. On cancellation/close while `sending`, remove the registry entry and settle the public future immediately, then retain a detached handler on the original send future. If a late response arrives, subscribe and immediately cancel its stream; if a late error arrives, absorb it. Neither path reopens public state.

The package owns the eager upstream subscription. Before a caller listens, it buffers only within `maxResponseBytes`; natural completion, error, explicit `OpenCodeStreamResponse.cancel()`, or auth-client close releases the registry entry. When the caller pauses, pause upstream for backpressure. Response cancel or auth-client close cancels upstream even while paused, marks the public controller terminal, removes the registry entry, and returns without waiting for the consumer to resume or for an upstream cancellation future. Attach a detached error handler to that future. A later listen/resume observes the queued typed cancellation terminal state and no buffered post-cancel bytes.

Cancellation has three observable stages:

| Stage | Required result |
| --- | --- |
| Before send | synchronous token check; no injected-client call; typed cancellation |
| Awaiting headers | abort request; typed cancellation; registry entry removed |
| Reading response | stop forwarding bytes, abort and cancel upstream, one typed stream error or caller cancellation completion, registry entry removed |

Late bytes, failures, or abort completions after settlement are handled only by detached cleanup and never reach the caller. Closing one response does not close the shared injected client or another conversation's stream. `OpenCodeAuthClient.close()` completes after each caller-facing future is settled or controller is marked terminal, upstream cancellation has been requested, registry entries are removed, and detached late-result handlers are installed. A paused consumer may observe its queued terminal event only after resuming; it cannot keep network work or `close()` alive.

## Tests and acceptance

- Recording fake receives exactly one POST to the canonical Chat endpoint with bearer auth, exact truthful user agent, exact conversation header, copied allowed headers, and byte-identical body.
- No public response, exception, string representation, fake assertion output, or captured diagnostic contains synthetic key/session/body canaries except inside the test fixture's private capture used for direct equality.
- Invalid/cross-origin roots, protected headers, unsupported protocols, closed clients, and oversized bodies produce zero dispatches.
- A 301/302/307/308 response is not followed. A second fake origin records zero calls. `Location`, cookies, auth body, and arbitrary server strings are not exposed through the exception.
- Controlled two-chunk response proves the first chunk is observable before the second is released. Chunk boundaries and all bytes remain unchanged below the cap. A two-chunk-then-error case containing URI/key/session/body canaries exposes only `OpenCodeNetworkException` and records no second send.
- Never-listened completion, never-listened explicit response cancel, listen-after-client-close, paused-then-response-cancel, and paused-then-client-close release the eager upstream subscription and registry without an unbounded close wait.
- Exactly-at-limit succeeds. One byte over the response/request cap fails deterministically and closes/cancels upstream.
- Initially cancelled/repeatedly cancelled token, cancellation immediately before send, before headers, between response chunks, stream-subscription cancel, auth-client close, upstream close, and upstream error each settle once and remove active state.
- Two concurrent conversations receive distinct correct session headers and do not interfere. Recreated clients with the same host ID reproduce the header.
- A real local TLS server plus `IOClient` proves redirect disabled, streaming before completion, socket cancellation, and body cleanup. Configure trust only inside the test; production code must not weaken certificate validation.
- Exercise abort-ignoring internal executors that later return headers, later throw, and never settle. Late headers are canceled, late errors are absorbed, and the never-settling executor cannot prevent bounded local close/caller settlement.
- Instrument the package-level fixture to fail on a second dispatch. In the real `IOClient` fixture, atomically record the first authenticated request and full body, sever the connection before any response, wait beyond plausible client retry windows, and assert no second receipt. Repeat for disconnect while uploading and after headers to cover failure stages.
- Run `dart test test/transport_test.dart test/transport_stream_test.dart`, then the full analyzer and test gates.
