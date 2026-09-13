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

  test(
    'synchronous executor failure disarms cancellation and closes locally',
    () async {
      final context = createTestClientWithExecutor(
        _SynchronousThrowingClient(),
      );
      addTearDown(context.close);
      final source = OpenCodeCancellationSource();
      await expectLater(
        context.auth.send(_request(token: source.token)),
        throwsA(isA<OpenCodeNetworkException>()),
      );
      source.cancel();
      await Future<void>.delayed(Duration.zero);
      await context.auth.close().timeout(const Duration(seconds: 1));
    },
  );

  test(
    'synchronous upstream listen failure is redacted and does not strand close',
    () async {
      final context = createTestClient(
        (_) => http.StreamedResponse(_ThrowingListenStream(), 200),
      );
      addTearDown(context.close);
      await expectLater(
        context.auth.send(_request()),
        throwsA(isA<OpenCodeNetworkException>()),
      );
      await context.auth.close().timeout(const Duration(seconds: 1));
    },
  );

  test('cancellation between chunks emits one typed terminal error', () async {
    final upstream = StreamController<List<int>>();
    final source = OpenCodeCancellationSource();
    final context = createTestClient(
      (_) => http.StreamedResponse(upstream.stream, 200),
    );
    addTearDown(context.close);
    final result = await context.auth.send(_request(token: source.token));
    final received = <List<int>>[];
    final terminal = Completer<Object>();
    final subscription = result.stream.listen(
      (chunk) {
        received.add(chunk);
        source.cancel();
      },
      onError: (Object error) {
        if (!terminal.isCompleted) terminal.complete(error);
      },
    );
    upstream
      ..add(const <int>[1])
      ..add(const <int>[2]);
    await expectLater(
      terminal.future,
      completion(isA<OpenCodeCancelledException>()),
    );
    expect(received, [
      <int>[1],
    ]);
    await subscription.cancel();
    await upstream.close();
  });

  test(
    'paused response cancellation and close do not await upstream cancel',
    () async {
      final neverCancels = Completer<void>();
      final upstream = StreamController<List<int>>(
        onCancel: () => neverCancels.future,
      );
      final context = createTestClient(
        (_) => http.StreamedResponse(upstream.stream, 200),
      );
      final result = await context.auth.send(_request());
      final subscription = result.stream.listen((_) {})..pause();
      await result.cancel().timeout(const Duration(seconds: 1));
      await context.auth.close().timeout(const Duration(seconds: 1));
      neverCancels.complete();
      await subscription.cancel();
      await upstream.close();
      context.ioClient.close();
    },
  );
}

final class _SynchronousThrowingClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      throw StateError('test-secret-canary');
}

final class _ThrowingListenStream extends Stream<List<int>> {
  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int>)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => throw StateError('test-secret-canary');
}
