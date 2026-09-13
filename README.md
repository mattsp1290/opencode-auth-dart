# opencode_auth

`opencode_auth` is a pure-Dart, native transport for authenticated OpenCode Go
Chat Completions traffic. It confines credentials to one configured HTTPS
origin, preserves request and successful response bytes, and performs exactly
one `package:http` dispatch.

The host owns secure API-key storage and durable conversation IDs. A provider
adapter owns Chat Completions JSON, SSE decoding, model selection, tool
execution, and continuation state. This package owns only validation,
authentication, cancellation, byte limits, and safe failure classification.

## Supported contract

- Route: `https://opencode.ai/zen/go/v1/chat/completions`
- Initial protocol: `OpenCodeProtocol.chatCompletions`
- Live acceptance model: `deepseek-v4-flash`
- Runtime boundary: Android and iOS using a borrowed `http` 1.6.0 `IOClient`
- Toolchain baseline: Dart 3.13.1; planned Rook tuple Flutter 3.47.1

The `messages` and `responses` enum values reserve an explicit protocol
dimension but fail locally; they are not supported dispatch routes. Catalog
visibility is descriptive metadata, not proof of entitlement, tool support, or
route compatibility.

## Usage

```dart
import 'dart:convert';
import 'dart:io';

import 'package:http/io_client.dart';
import 'package:opencode_auth/opencode_auth.dart';

Future<void> runTurn(String apiKey, String conversationId) async {
  final httpClient = IOClient(HttpClient());
  final auth = OpenCodeAuthClient(
    OpenCodeAuthOptions(
      apiKey: apiKey,
      client: httpClient,
      userAgent: 'rook/1.0.0',
    ),
  );
  final cancellation = OpenCodeCancellationSource();
  try {
    final response = await auth.send(
      OpenCodeInferenceRequest(
        protocol: OpenCodeProtocol.chatCompletions,
        conversationId: conversationId,
        body: utf8.encode('{"model":"deepseek-v4-flash","messages":[]}'),
        headers: const {'content-type': 'application/json'},
        cancellationToken: cancellation.token,
      ),
    );
    await for (final bytes in response.stream) {
      // Pass each unchanged chunk to the provider adapter.
      consumeNativeBytes(bytes);
    }
  } finally {
    await auth.close();
    httpClient.close();
  }
}

void consumeNativeBytes(List<int> bytes) {}
```

`OpenCodeAuthClient.close()` cancels local operations but never closes the
borrowed `IOClient`. Close the auth client first, then the HTTP client.

## Security and ownership

Production library code never reads environment variables, profiles, desktop
credentials, or OpenCode CLI state. The API key, caller-specific user agent,
and stable per-conversation ID must be injected. The package does not persist,
refresh, clear, or log them. Caller headers are limited to `content-type` and
`accept`; authorization, session, redirects, and destination routes remain
package-owned.

Responses are opaque, bounded, eager, single-subscription byte streams. The
package has no automatic retry, fallback, protocol conversion, alternate
origin, model selection, storage, login, or billing-root switching. An injected
native client and its proxy/TLS configuration remain trusted code.

## Verification

Credential-free checks:

```sh
dart pub get
dart format --output=none --set-exit-if-changed .
dart analyze --fatal-infos
dart test
dart pub publish --dry-run
```

The opt-in live test is deliberately excluded from ordinary CI. It uses only
the exact model and subscription route above:

```sh
OPENCODE_AUTH_LIVE_TEST=true \
OPENCODE_AUTH_LIVE_MODEL=deepseek-v4-flash \
OPENCODE_GO_API_KEY='...' \
dart test test/live_test.dart --reporter expanded
```

Only the test launcher reads `OPENCODE_GO_API_KEY`; it injects the value into
the production API. Live output is redacted. The mobile fixture under
`example/mobile_smoke` documents the iPhone 12 and AYN Thor gate. Desktop and
web are not part of the initial runtime support claim.

See `example/chat_completions.dart` and `example/models.dart` for complete
lifecycle examples.

## Known limits

- Chat Completions only; no Messages or Responses dispatch.
- Native borrowed `IOClient` only; no browser, retry, or arbitrary-client
  production constructor.
- No JSON/SSE/model/tool abstractions.
- No credential or conversation persistence.
- No automatic resubmission after cancellation or connection loss.

`deepseek-v4-flash` and service availability can change independently of this
package. A catalog result never changes the fixed protocol support table.
