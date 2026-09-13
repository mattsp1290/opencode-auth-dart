import 'dart:convert';

import 'package:opencode_auth/opencode_auth.dart';
import 'package:test/test.dart';

import 'support/recording_client.dart';

void main() {
  OpenCodeInferenceRequest request() => OpenCodeInferenceRequest(
    protocol: OpenCodeProtocol.chatCompletions,
    conversationId: 'session-canary',
    body: utf8.encode('body-canary'),
  );

  final cases = <String, Type>{
    'AuthError': OpenCodeAuthenticationException,
    'authentication_error': OpenCodeAuthenticationException,
    'CreditsError': OpenCodeQuotaException,
    'GoUsageLimitError': OpenCodeQuotaException,
    'insufficient_quota': OpenCodeQuotaException,
    'RateLimitError': OpenCodeRateLimitException,
    'ModelError': OpenCodeModelException,
    'RegionError': OpenCodePolicyException,
    'DataPolicyError': OpenCodePolicyException,
  };

  for (final entry in cases.entries) {
    test('maps ${entry.key} to ${entry.value}', () async {
      final context = createTestClient(
        (_) => response(
          429,
          <List<int>>[utf8.encode('{"error":{"type":"${entry.key}"}}')],
          headers: const {'retry-after': '5'},
        ),
      );
      addTearDown(context.close);
      await expectLater(
        context.auth.send(request()),
        throwsA(
          isA<OpenCodeAuthException>().having(
            (error) => error.runtimeType,
            'runtime type',
            entry.value,
          ),
        ),
      );
    });
  }

  test(
    'does not infer failure category from status or expose server text',
    () async {
      final context = createTestClient(
        (_) => response(401, <List<int>>[
          utf8.encode(
            '{"error":{"type":"unknown",'
            '"message":"test-secret-canary session-canary body-canary"}}',
          ),
        ]),
      );
      addTearDown(context.close);
      await expectLater(
        context.auth.send(request()),
        throwsA(
          isA<OpenCodeHttpException>().having(
            (error) => error.toString(),
            'redacted',
            allOf(
              isNot(contains('secret')),
              isNot(contains('session-canary')),
              isNot(contains('body-canary')),
            ),
          ),
        ),
      );
    },
  );

  test('conflicting recognized categories remain unknown', () async {
    final context = createTestClient(
      (_) => response(429, <List<int>>[
        utf8.encode('{"error":{"type":"AuthError","code":"RateLimitError"}}'),
      ]),
    );
    addTearDown(context.close);
    await expectLater(
      context.auth.send(request()),
      throwsA(isA<OpenCodeHttpException>()),
    );
  });
}
