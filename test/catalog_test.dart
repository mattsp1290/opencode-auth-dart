import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:opencode_auth/opencode_auth.dart';
import 'package:test/test.dart';

import 'support/recording_client.dart';

void main() {
  test(
    'catalog is bounded metadata and carries no credentials or session',
    () async {
      final context = createTestClient(
        (_) => response(200, <List<int>>[
          utf8.encode(
            '{"object":"list","data":['
            '{"id":"z","object":"model","created":1,"owned_by":"open"},'
            '{"id":"z","future":true}]}',
          ),
        ]),
      );
      addTearDown(context.close);
      final models = await context.auth.listModels();
      expect(models.map((model) => model.id), ['z', 'z']);
      final sent = context.recording.requests.single;
      expect(sent.method, 'GET');
      expect(sent.url.path, '/zen/go/v1/models');
      expect(sent.headers['accept'], 'application/json');
      expect(sent.headers['user-agent'], 'rook-test/1.0');
      expect(sent.headers, isNot(contains('authorization')));
      expect(sent.headers, isNot(contains('x-opencode-session')));
      expect(sent, isA<http.AbortableRequest>());
    },
  );

  test('malformed catalog is a fixed protocol failure', () async {
    for (final document in <String>[
      '{}',
      '{"object":"list","data":null}',
      '{"object":"list","data":[{}]}',
      '{"object":"list","data":[{"id":"x","created":"bad"}]}',
      '{"object":"list","data":[]} trailing',
    ]) {
      final context = createTestClient(
        (_) => response(200, <List<int>>[utf8.encode(document)]),
      );
      await expectLater(
        context.auth.listModels(),
        throwsA(isA<OpenCodeProtocolException>()),
        reason: document,
      );
      await context.close();
    }
  });

  test('catalog cancellation while awaiting headers settles locally', () async {
    final pending = Completer<http.StreamedResponse>();
    final source = OpenCodeCancellationSource();
    final context = createTestClient((_) => pending.future);
    addTearDown(() {
      if (!pending.isCompleted) {
        pending.complete(response(200, const <List<int>>[]));
      }
      return context.close();
    });
    final result = context.auth.listModels(cancellationToken: source.token);
    final expectation = expectLater(
      result,
      throwsA(isA<OpenCodeCancelledException>()),
    );
    await Future<void>.delayed(Duration.zero);
    source.cancel();
    await expectation;
    expect(context.recording.requests, hasLength(1));
  });

  test('catalog stream failures and oversized bodies are bounded', () async {
    final failingStream = StreamController<List<int>>();
    final failing = createTestClient(
      (_) => http.StreamedResponse(failingStream.stream, 200),
    );
    final failed = failing.auth.listModels();
    final failedExpectation = expectLater(
      failed,
      throwsA(isA<OpenCodeNetworkException>()),
    );
    failingStream.addError(StateError('test-secret-canary'));
    await failingStream.close();
    await failedExpectation;
    await failing.close();

    final oversized = createTestClient(
      (_) => response(200, <List<int>>[
        List<int>.filled(8 * 1024 * 1024, 1),
        const <int>[2],
      ]),
    );
    await expectLater(
      oversized.auth.listModels(),
      throwsA(isA<OpenCodeResponseLimitException>()),
    );
    await oversized.close();
  });
}
