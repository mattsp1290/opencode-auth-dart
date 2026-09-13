import 'dart:async';

import 'package:http/http.dart' as http;
import 'package:opencode_auth/opencode_auth.dart';
import 'package:test/test.dart';

import 'support/recording_client.dart';

void main() {
  test('request owns immutable body and canonical allowed headers', () {
    final body = <int>[1, 2, 3];
    final headers = <String, String>{'Content-Type': 'application/json'};
    final request = OpenCodeInferenceRequest(
      protocol: OpenCodeProtocol.chatCompletions,
      conversationId: 'conversation-1',
      body: body,
      headers: headers,
    );
    body[0] = 9;
    headers['Content-Type'] = 'text/plain';
    expect(request.body, <int>[1, 2, 3]);
    expect(request.headers, {'content-type': 'application/json'});
    expect(() => request.body[0] = 8, throwsUnsupportedError);
    expect(
      () => request.headers['accept'] = 'text/plain',
      throwsUnsupportedError,
    );
  });

  test('request rejects invalid identity, bytes, and protected headers', () {
    expect(
      () => OpenCodeInferenceRequest(
        protocol: OpenCodeProtocol.chatCompletions,
        conversationId: 'bad id',
        body: const <int>[],
      ),
      throwsA(isA<OpenCodeConfigurationException>()),
    );
    expect(
      () => OpenCodeInferenceRequest(
        protocol: OpenCodeProtocol.chatCompletions,
        conversationId: 'valid',
        body: const <int>[256],
      ),
      throwsA(isA<OpenCodeConfigurationException>()),
    );
    for (final name in <String>[
      'authorization',
      'USER-AGENT',
      'X-OpenCode-Session',
      'cookie',
    ]) {
      expect(
        () => OpenCodeInferenceRequest(
          protocol: OpenCodeProtocol.chatCompletions,
          conversationId: 'valid',
          body: const <int>[],
          headers: {name: 'canary'},
        ),
        throwsA(isA<OpenCodeConfigurationException>()),
      );
    }
  });

  test(
    'unsupported protocols and initial cancellation never dispatch',
    () async {
      final context = createTestClient(
        (_) => response(200, const <List<int>>[]),
      );
      addTearDown(context.close);
      for (final protocol in <OpenCodeProtocol>[
        OpenCodeProtocol.messages,
        OpenCodeProtocol.responses,
      ]) {
        await expectLater(
          context.auth.send(
            OpenCodeInferenceRequest(
              protocol: protocol,
              conversationId: 'conversation',
              body: const <int>[],
            ),
          ),
          throwsA(isA<UnsupportedProtocolException>()),
        );
      }
      final source = OpenCodeCancellationSource()..cancel();
      await expectLater(
        context.auth.send(
          OpenCodeInferenceRequest(
            protocol: OpenCodeProtocol.chatCompletions,
            conversationId: 'conversation',
            body: const <int>[],
            cancellationToken: source.token,
          ),
        ),
        throwsA(isA<OpenCodeCancelledException>()),
      );
      expect(context.recording.requests, isEmpty);
    },
  );

  test(
    'close settles a pending send and does not close borrowed clients',
    () async {
      final pending = Completer<http.StreamedResponse>();
      final context = createTestClient((_) => pending.future);
      final sendFuture = context.auth.send(
        OpenCodeInferenceRequest(
          protocol: OpenCodeProtocol.chatCompletions,
          conversationId: 'conversation',
          body: const <int>[],
        ),
      );
      final expectation = expectLater(
        sendFuture,
        throwsA(isA<OpenCodeCancelledException>()),
      );
      await Future<void>.delayed(Duration.zero);
      await context.auth.close();
      await expectation;
      expect(context.recording.closed, isFalse);
      context.ioClient.close();
    },
  );
}
