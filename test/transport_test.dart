import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:opencode_auth/opencode_auth.dart';
import 'package:test/test.dart';

import 'support/recording_client.dart';

void main() {
  OpenCodeInferenceRequest request({String session = 'conversation-a'}) =>
      OpenCodeInferenceRequest(
        protocol: OpenCodeProtocol.chatCompletions,
        conversationId: session,
        body: utf8.encode('{"model":"deepseek-v4-flash"}'),
        headers: const {
          'content-type': 'application/json',
          'accept': 'text/event-stream',
        },
      );

  test('dispatches exactly one fixed request and preserves bytes', () async {
    final context = createTestClient(
      (_) => response(
        200,
        const <List<int>>[
          <int>[1, 2],
          <int>[3],
        ],
        headers: const {'content-type': 'text/event-stream'},
      ),
    );
    addTearDown(context.close);
    final inference = request();
    final result = await context.auth.send(inference);
    expect(await result.stream.toList(), <List<int>>[
      <int>[1, 2],
      <int>[3],
    ]);
    expect(result.statusCode, 200);
    expect(result.contentType, 'text/event-stream');
    expect(context.recording.requests, hasLength(1));
    final sent = context.recording.requests.single as http.Request;
    expect(sent.method, 'POST');
    expect(
      sent.url.toString(),
      'https://opencode.ai/zen/go/v1/chat/completions',
    );
    expect(sent.followRedirects, isFalse);
    expect(sent.maxRedirects, 0);
    expect(sent.headers['authorization'], 'Bearer test-secret-canary');
    expect(sent.headers['user-agent'], 'rook-test/1.0');
    expect(sent.headers['x-opencode-session'], 'conversation-a');
    expect(sent.bodyBytes, inference.body);
  });

  test(
    'redirect is refused and sensitive response metadata is hidden',
    () async {
      final context = createTestClient(
        (_) => response(
          307,
          <List<int>>[utf8.encode('test-secret-canary body-canary')],
          headers: const {
            'location': 'https://attacker.example/steal',
            'set-cookie': 'secret=canary',
          },
        ),
      );
      addTearDown(context.close);
      final matcher = throwsA(
        isA<OpenCodeRedirectException>()
            .having(
              (error) => error.toString(),
              'safe text',
              isNot(contains('attacker')),
            )
            .having(
              (error) => error.toString(),
              'no body',
              isNot(contains('canary')),
            ),
      );
      await expectLater(context.auth.send(request()), matcher);
      expect(context.recording.requests, hasLength(1));
    },
  );

  test('concurrent conversations retain isolated session identity', () async {
    final context = createTestClient(
      (_) => response(200, const <List<int>>[
        <int>[1],
      ]),
    );
    addTearDown(context.close);
    final responses = await Future.wait([
      context.auth.send(request(session: 'conversation-a')),
      context.auth.send(request(session: 'conversation-b')),
    ]);
    await Future.wait(responses.map((item) => item.stream.drain<void>()));
    expect(
      context.recording.requests
          .map((item) => item.headers['x-opencode-session'])
          .toSet(),
      {'conversation-a', 'conversation-b'},
    );
  });
}
