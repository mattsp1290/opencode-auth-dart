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

  test(
    'unknown, malformed, and oversized classifier fields remain unknown',
    () async {
      for (final envelope in <String>[
        '{"error":{"type":"AuthError","code":"future_category"}}',
        '{"error":{"type":"AuthError","code":42}}',
        '{"error":{"type":42,"code":"RateLimitError"}}',
        '{"error":{"type":"${'a' * 129}"}}',
      ]) {
        final context = createTestClient(
          (_) => response(400, <List<int>>[utf8.encode(envelope)]),
        );
        await expectLater(
          context.auth.send(request()),
          throwsA(isA<OpenCodeHttpException>()),
          reason: envelope,
        );
        await context.close();
      }
    },
  );

  test('retry-after accepts bounded seconds and HTTP dates only', () async {
    final now = DateTime.utc(2026, 9, 13, 14, 0, 0);
    Future<OpenCodeAuthException> sendWith(String retryAfter) async {
      final context = createTestClient(
        (_) => response(
          429,
          <List<int>>[utf8.encode('{"error":{"type":"RateLimitError"}}')],
          headers: {'retry-after': retryAfter},
        ),
        clock: () => now,
      );
      try {
        await context.auth.send(request());
        throw StateError('expected a rate limit error');
      } on OpenCodeAuthException catch (error) {
        return error;
      } finally {
        await context.close();
      }
    }

    expect(
      (await sendWith('5') as OpenCodeRateLimitException).retryAfter,
      const Duration(seconds: 5),
    );
    expect(
      (await sendWith(
        'Sun, 13 Sep 2026 14:00:30 GMT',
      ) as OpenCodeRateLimitException).retryAfter,
      const Duration(seconds: 30),
    );
    for (final value in <String>[
      '-1',
      '86401',
      'Sun, 13 Sep 2026 13:59:59 GMT',
      'Mon, 14 Sep 2026 14:00:01 GMT',
      '1, 2',
    ]) {
      expect(
        (await sendWith(value) as OpenCodeRateLimitException).retryAfter,
        isNull,
        reason: value,
      );
    }
  });
}
