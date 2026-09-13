# WP4 — Examples, live verification, publication, and request response

Goal: prove the package through its public API, establish the supported Rook tuple, publish an immutable consumer artifact, and return exact unblock evidence. Prerequisites: WP2 and WP3 integrated with G1–G4 passing.

## Change surface

- Edit existing `README.md` with package purpose, ownership boundaries, supported route/model evidence, security model, complete usage, local/live gates, and known limits.
- Add **new** `CHANGELOG.md` at repository root.
- Add **new** `example/chat_completions.dart` and `example/models.dart` under the new `example/` directory.
- Add **new** `example/mobile_smoke/` Flutter integration fixture under the existing new `example/` insertion point. Exclude the nested fixture from the published package archive if pub tooling would include host build artifacts.
- Add **new** `test/live_test.dart`, skipped unless explicitly enabled.
- Extend **new** `.github/workflows/ci.yml` only for credential-free checks. Do not put the live key in ordinary CI.
- Update the existing external Beans request only after all publication gates pass. This future mutation is not performed by this plan.

## Examples and documentation

The Chat example accepts the API key, caller ID, session ID, model, and host-created native JSON at the boundary. It uses exact model `deepseek-v4-flash` in the documented sample, an injected `IOClient`, bounded cancellation, `try/finally`, response-stream consumption, and explicit closure of auth then HTTP clients. It does not print secrets, sessions, response headers, raw diagnostic errors, or reasoning as diagnostics.

README states:

- the host owns secure key storage and durable per-conversation IDs;
- production code does not read `OPENCODE_GO_API_KEY`; only opt-in test/example launchers may read it outside the library and inject it;
- the provider adapter owns Chat Completions JSON/SSE, tools, model selection, and continuation;
- only Chat Completions is supported initially; enum presence is not dispatch support;
- catalog visibility is not entitlement or tool capability;
- the initial production contract accepts only a borrowed `IOClient`; arbitrary clients, browser clients, and retry wrappers are unsupported;
- the initial runtime support claim is Android/iOS native only; web and desktop are unverified even if `IOClient` can run on some desktop targets;
- success streams are opaque, bounded, single-subscription, and caller-consumed;
- the package has no automatic fallback, retry, storage, login, or billing-root switching.

## Opt-in live gate

`test/live_test.dart` runs only when a fixed enable flag is present and receives `OPENCODE_GO_API_KEY` from the process environment in test code. The production library never reads it. Require an explicit confirmation variable for model `deepseek-v4-flash`; do not silently select a cheaper/different model.

Use a random unprinted session ID, truthful `opencode-auth-dart-live-test/<version>` user agent, 90-second per-request deadline, 256-token cap, and synthetic tool/schema/result. Run sequentially:

1. Send a nonstreaming Chat Completions request forcing one synthetic `lookup_file` tool call.
2. Validate one tool call and capture its native assistant message/tool-call ID in memory.
3. Send the assistant state and synthetic tool result with the same model, session, and user agent.
4. Require a nonempty final assistant message and normal terminal finish.
5. Run one additional streaming request through the same public transport; require at least one data chunk and the protocol's terminal marker without asserting generated text or event count.
6. Start a bounded streaming request, cancel after the first observable chunk, and verify the Dart stream and underlying supported client settle without resubmission. If service timing makes this nondeterministic, retain deterministic cancellation as the hard library gate and label the live cancellation result inconclusive rather than passing it silently.

The live test prints only date, package/Dart/http versions, public model/protocol, user-agent category, request stage, finish/event category, and pass/fail. It never prints credentials, sessions, tool IDs, prompt/answer content, reasoning, raw bodies/headers, account metadata, or upstream error strings.

A service/account/network failure blocks release readiness until the maintainer reruns with an eligible authorized key or explicitly revises scope. Do not try another model, route, account, or the pay-as-you-go root automatically.

## Rook platform tuple

The initial supported tuple is Flutter 3.47.1 / Dart 3.13.1 / `http` 1.6.0 `IOClient`, matching the Rook plan's current shared-toolchain target. Run proposed `example/mobile_smoke/integration_test/opencode_auth_smoke_test.dart` on an iPhone 12 and AYN Thor. The fixture injects `IOClient`, exercises a synthetic TLS endpoint for redirect/cancellation/connection-loss mechanics, and uses the authorized live account for one exact-model exchange.

From `example/mobile_smoke/`, after supplying host signing/device configuration, run `flutter pub get`, `flutter analyze`, `flutter test`, `flutter test integration_test/opencode_auth_smoke_test.dart -d <iphone-12-device-id>`, and the same integration command with `<ayn-thor-device-id>`. Matt and the Rook implementer record actual device IDs privately and retain only device model, OS/firmware, Flutter/Dart/http versions, client type, date, and per-case pass/fail. They also run `flutter build ios --no-codesign` and `flutter build apk --debug`; builds do not replace device tests.

The connection-loss endpoint atomically records the first authenticated request and complete body, then severs the connection before sending a response. Wait beyond plausible retry windows and require no second receipt. Repeat with a disconnect during upload and after response headers. This proves the no-resubmission promise only for the named `IOClient` tuple. A future supported client requires the same conformance cases before entering the public constructor surface.

Rook acceptance additionally proves host persistence: create two conversation IDs in the fixture's host-owned test store, restart/reconstruct host and auth objects, verify the first ID remains stable, verify the second differs, and verify every tool-loop dispatch carries the correct session plus `rook/<app-version>` user agent. This belongs in the mobile fixture until the Rook app exists. No key is persisted by this package or fixture.

If Flutter 3.47.1, either physical target, signing/install access, or a compatible `IOClient` resolution is unavailable, stop before Rook-ready publication and the Beans unblock response. Matt and the Rook implementer must provision the missing item or explicitly revise the Rook and Beans contracts; desktop `IOClient` evidence is not a substitute.

## Publication and clean-consumer gate

After all source/test gates pass, Matt or the accepted maintainer creates an authorized immutable commit and version tag. Record the full commit SHA and tag. Do not publish from a dirty tree or include live artifacts.

Create a fresh temporary Dart consumer outside this checkout with no path/git override. Add the published package from its actual distribution mechanism and import `package:opencode_auth/opencode_auth.dart`. Compile/test construction, one fake request, cancellation, and public error matching. Inspect dependency resolution to confirm the immutable source/version and absence of path dependencies.

If the package is consumed by Git before pub.dev publication, pin the full commit SHA in the consumer and record that exact pin. A local path or mutable branch does not satisfy the request.

## Beans response and acceptance

Resolve the first-class record with:

```sh
bn request show opencode-auth-dart-r-ugiz
```

Prepare a response body that preserves the original requested scope and adds:

- accepted maintainer and scope;
- package name `opencode_auth` and final public type/method names;
- immutable tag/full commit and clean-consumer resolution evidence;
- Dart, Flutter if applicable, `http`, Android, and iOS tuple tested;
- deterministic, live tool-loop, streaming/cancellation, and Rook-shaped persistence results;
- supported Chat Completions route and exact tested model;
- known limits, including unsupported Messages/Responses and the native `IOClient`-only production boundary.

Use `bn request update opencode-auth-dart-r-ugiz --body-file <reviewed-response-file> --status <workflow-valid-accepted-status>` only after inspecting the hub workflow's valid statuses and reviewing the final body. The CLI owns hub commits. Do not hand-edit hub files. If the workflow has no accepted/completed status matching delivery, preserve `open` and append the evidence without inventing one.

Acceptance: the request body and package documentation agree; the pin resolves cleanly; Rook has enough public API and tuple detail to start provider integration; no acknowledgement is presented as delivery; no secret/live content enters Git or Beans.
