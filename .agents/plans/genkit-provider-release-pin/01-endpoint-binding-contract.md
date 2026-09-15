# Endpoint-binding and encapsulation contract

Goal: make endpoint policy structural and inspectable without exposing the endpoint URL or credential. Prerequisite: start from the request-inspected commit or reconcile later changes before editing.

## Repository evidence

- Existing `lib/src/options.dart` owns `_apiKey`, public `serviceRoot`, validation, limits, and a URL-bearing `toString()`.
- Existing `lib/src/client.dart` owns routing and protected-header injection but can access `_apiKey` only through the publicly named `openCodeTransportApiKey` helper because each file is a separate Dart library.
- Existing `lib/opencode_auth.dart` exports options and client as separate libraries, while tests directly import both `src` paths for the internal executor seam.
- Existing `lib/src/request.dart` imports `options.dart` for `openCodeAbsoluteMaxRequestBytes`; converting options to a part without relocating that constant would make the import graph invalid.
- Existing routing appends `chat/completions` or `models` to the configured root. Existing tests assert the fixed subscription route and local custom TLS routes.

## Exact change surface

- Add **new** `lib/src/auth.dart` under existing `lib/src/`. It becomes the shared Dart library for endpoint binding, options, and client; it imports the existing cancellation, catalog, error, protocol, request, response, transport, `dart:async`, `package:http/http.dart`, and `package:http/io_client.dart` dependencies and declares the options/client files as parts.
- Add **new** independent library `lib/src/limits.dart` under existing `lib/src/`. Move `openCodeAbsoluteMaxRequestBytes` and `openCodeAbsoluteMaxResponseBytes` from options into it without changing their public names or values.
- Edit existing `lib/src/options.dart` to become `part of 'auth.dart'`; remove standalone imports.
- Edit existing `lib/src/client.dart` to become `part of 'auth.dart'`; remove standalone imports.
- Edit existing `lib/src/request.dart` to import `limits.dart` instead of the former standalone options library.
- Edit existing `lib/opencode_auth.dart` to export `src/auth.dart` with the intended public types, export `src/limits.dart` for the existing limit constants, and stop exporting the client/options part files directly.
- Add **proposed public enum** `OpenCodeEndpointBinding { subscriptionGo, custom }` in the shared auth library.
- Keep the existing unnamed `OpenCodeAuthOptions(...)` symbol but change it to subscription-only construction with no `serviceRoot` parameter.
- Add **proposed public named constructor** `OpenCodeAuthOptions.custom(...)` with required `String serviceRoot` and the same key, borrowed `IOClient`, user agent, and limit inputs.
- Add **proposed public property** `OpenCodeEndpointBinding OpenCodeAuthOptions.endpointBinding`.
- Add **proposed public property** `OpenCodeEndpointBinding OpenCodeAuthClient.endpointBinding`, delegating to the immutable options value.
- Replace the existing public `Uri OpenCodeAuthOptions.serviceRoot` with **proposed private field** `_serviceRoot` in the shared library.
- Remove existing `openCodeTransportApiKey`; client code reads `_apiKey` directly inside the shared library.
- Retain existing `createOpenCodeAuthClientForTesting` as a non-barrel test seam in `src/auth.dart` unless implementation can give tests the same executor control with a smaller safe seam. It must never expose `_apiKey` or `_serviceRoot`.
- Edit existing `test/support/recording_client.dart` to import the shared auth source library and construct either subscription or explicit custom options.

## Construction rules and invariants

The unnamed constructor always assigns:

- `endpointBinding = OpenCodeEndpointBinding.subscriptionGo`;
- `_serviceRoot` from one private compile-time string for `https://opencode.ai/zen/go/v1`, passed through the same strict root validator;
- validated `_apiKey`, `userAgent`, request limit, and response limit.

The custom named constructor always assigns:

- `endpointBinding = OpenCodeEndpointBinding.custom` before any client can observe it;
- `_serviceRoot` from its required validated input;
- the same validated credential, caller identity, and limits.

Do not add a constructor parameter that directly accepts `OpenCodeEndpointBinding`. Do not infer the binding by comparing normalized URI strings. `OpenCodeAuthOptions.custom(serviceRoot: 'https://opencode.ai/zen/go/v1', ...)` must remain `custom`; only package-controlled subscription construction grants `subscriptionGo`.

Both constructors create immutable objects. A caller cannot mutate the root or binding after construction. `OpenCodeAuthClient.endpointBinding` remains readable after options go out of scope and before or after `close()` because it is static configuration, not network state.

## Routing, failure, and lifecycle behavior

- `_route` uses private `_serviceRoot` and retains exact suffix composition.
- Subscription `send` reaches only `/zen/go/v1/chat/completions`; subscription `listModels` reaches only `/zen/go/v1/models`.
- Custom routing remains available only through explicit custom construction. It retains strict HTTPS validation, no user info, query, fragment, ambiguous escapes, traversal, duplicate slash, or trailing duplicate slash.
- Endpoint construction and binding checks perform no network I/O.
- Unsupported protocol rejection remains before body access, operation creation, and dispatch.
- Binding does not add retry, fallback, alternate route, model parsing, or policy-based dispatch inside this package. The downstream provider compares the enum before calling `send`.
- Cancellation and connection loss retain the current single `_client.send` call. No failure path reconstructs a request against another root.
- `OpenCodeAuthClient.close()` continues to cancel local operations without closing the borrowed `IOClient`.

## Redaction and public-surface rules

`OpenCodeAuthOptions.toString()` may include only the binding enum and numeric request/response limits. It excludes `_apiKey`, `_serviceRoot`, user agent, and client details. The enum's generated string is safe because its values contain no endpoint text.

No new exception carries a URL. Invalid custom roots continue to throw `OpenCodeConfigurationException('service_root')`. Provider rejection belongs to the provider and should name only the expected/actual enum categories. Existing auth exceptions keep fixed codes and must not wrap raw validation, URI, client, or upstream exception text.

The public barrel exposes only the enum, intended options/client constructors and getters, the relocated existing limit constants, and the existing supported API. Package API documentation must not list `openCodeTransportApiKey`, `_apiKey`, or `_serviceRoot`. Direct import of the part files must fail because parts are not standalone libraries; importing `src/auth.dart` must still reveal no credential-returning function. Analyzer coverage must compile `request.dart` through the barrel and catch any stale import of `options.dart` or `client.dart` as standalone libraries.

## Tests and observable acceptance

Edit existing `test/options_test.dart` to prove:

- default construction reports `subscriptionGo`;
- custom construction normalizes internally and reports `custom` without exposing the normalized value;
- custom construction with the literal production root still reports `custom`;
- every valid object's `toString()` excludes key, root host/path canaries, user agent, and client representation;
- invalid root failures expose only the fixed `service_root` code;
- existing key, caller identity, and limit validation remains unchanged.

Edit existing `test/transport_test.dart`, `test/real_io_transport_test.dart`, and mobile helpers to use subscription construction for production-route assertions and custom construction only for local TLS endpoints. Require one fixed subscription route, one custom local route per intended request, redirects disabled, and protected headers unchanged.

Add **new** `test/endpoint_binding_test.dart` under existing `test/`. Implement a small provider-shaped test adapter that receives only an `OpenCodeAuthClient`, compares `endpointBinding`, and throws a fixed local test error before request construction or `send` unless it equals `subscriptionGo`. Cover:

1. subscription client accepted and exactly one recording-executor dispatch;
2. arbitrary custom root rejected with zero dispatches;
3. synthetic pay-as-you-go-labelled root rejected with zero dispatches;
4. wrong-host root rejected with zero dispatches;
5. custom construction using the exact documented production URL rejected with zero dispatches;
6. rejection text contains neither candidate URL, credential, session, user agent, nor request body canaries.

Retain existing `test/client_contract_test.dart` poisoned-body cases for `messages` and `responses`, and add the endpoint guard ahead of request construction in the provider-shaped fixture. This proves both provider policy and protocol policy fail before inference I/O.

## Dependencies, risks, and exclusions

This work package must land before live/release changes because every later fixture and document names the final API. The `part` conversion touches imports and test seams across two central files; run formatting, analysis, and the smallest option/client/transport tests immediately after it.

No backward-compatibility shim is required. Do not retain `serviceRoot` as deprecated, add a URL-returning debug API, or keep the old credential helper for source imports. Custom consumers must intentionally move to `OpenCodeAuthOptions.custom`.

This package does not add a `requireSubscriptionGo()` method: acceptance versus rejection is consumer policy. It exposes a trustworthy fact and keeps dispatch behavior transport-focused.
