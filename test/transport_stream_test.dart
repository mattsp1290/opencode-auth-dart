import 'dart:async';

import 'package:http/http.dart' as http;
import 'package:opencode_auth/opencode_auth.dart';
import 'package:test/test.dart';

import 'support/recording_client.dart';

OpenCodeInferenceRequest _request({OpenCodeCancellationToken? token}) =>
    OpenCodeInferenceRequest(
      protocol: OpenCodeProtocol.chatCompletions,
      conversationId: 'conversation',
      body: const <int>[1, 2],
      cancellationToken: token,
    );

void main() {
  test('forwards first chunk before the upstream completes', () async {
    final upstream = StreamController<List<int>>();
    final context = createTestClient(
      (_) => http.StreamedResponse(upstream.stream, 200),
    );
    addTearDown(context.close);
    final response = await context.auth.send(_request());
    final first = Completer<List<int>>();
    final subscription = response.stream.listen((chunk) {
      if (!first.isCompleted) first.complete(chunk);
    });
    upstream.add(const <int>[1, 2]);
    expect(await first.future, <int>[1, 2]);
    upstream.add(const <int>[3]);
    await upstream.close();
    await subscription.asFuture<void>();
    await subscription.cancel();
  });

  test('exact response limit succeeds and one byte over fails typed', () async {
    final exact = createTestClient(
      (_) => response(200, const <List<int>>[
        <int>[1, 2, 3],
      ]),
      maxResponseBytes: 3,
    );
    addTearDown(exact.close);
    expect(await (await exact.auth.send(_request())).stream.single, <int>[
      1,
      2,
      3,
    ]);

    final over = createTestClient(
      (_) => response(200, const <List<int>>[
        <int>[1, 2],
        <int>[3, 4],
      ]),
      maxResponseBytes: 3,
    );
    addTearDown(over.close);
    await expectLater(
      (await over.auth.send(_request())).stream.drain<void>(),
      throwsA(isA<OpenCodeResponseLimitException>()),
    );
    expect(over.recording.requests, hasLength(1));
  });

  test('token cancellation while awaiting headers settles locally', () async {
    final pending = Completer<http.StreamedResponse>();
    final source = OpenCodeCancellationSource();
    final context = createTestClient((_) => pending.future);
    addTearDown(() {
      if (!pending.isCompleted) {
        pending.complete(response(200, const <List<int>>[]));
      }
      return context.close();
    });
    final result = context.auth.send(_request(token: source.token));
    final expectation = expectLater(
      result,
      throwsA(isA<OpenCodeCancelledException>()),
    );
    await Future<void>.delayed(Duration.zero);
    source.cancel();
    await expectation;
    expect(context.recording.requests, hasLength(1));
  });

  test(
    'explicit response cancellation settles a never-listened stream',
    () async {
      final upstream = StreamController<List<int>>();
      final context = createTestClient(
        (_) => http.StreamedResponse(upstream.stream, 200),
      );
      final result = await context.auth.send(_request());
      await result.cancel();
      await context.auth.close();
      expect(context.recording.closed, isFalse);
      context.ioClient.close();
      await upstream.close();
    },
  );

  test('upstream failures are redacted and never resubmitted', () async {
    final upstream = StreamController<List<int>>();
    final context = createTestClient(
      (_) => http.StreamedResponse(upstream.stream, 200),
    );
    addTearDown(context.close);
    final result = await context.auth.send(_request());
    final consumed = result.stream.drain<void>();
    final expectation = expectLater(
      consumed,
      throwsA(
        isA<OpenCodeNetworkException>().having(
          (error) => error.toString(),
          'redacted',
          allOf(
            isNot(contains('secret')),
            isNot(contains('conversation')),
            isNot(contains('body-canary')),
          ),
        ),
      ),
    );
    upstream.addError(Exception('test-secret-canary conversation body-canary'));
    await upstream.close();
    await expectation;
    expect(context.recording.requests, hasLength(1));
  });
}
