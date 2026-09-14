import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:opencode_auth/src/auth.dart';

typedef RequestHandler = FutureOr<http.StreamedResponse> Function(
  http.BaseRequest request,
);

final class RecordingClient extends http.BaseClient {
  RecordingClient(this.handler);

  final RequestHandler handler;
  final List<http.BaseRequest> requests = <http.BaseRequest>[];
  bool closed = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests.add(request);
    return handler(request);
  }

  @override
  void close() {
    closed = true;
  }
}

final class TestClientContext {
  TestClientContext(this.auth, this.recording, this.ioClient);

  final OpenCodeAuthClient auth;
  final RecordingClient recording;
  final IOClient ioClient;

  Future<void> close() async {
    await auth.close();
    ioClient.close();
  }
}

TestClientContext createTestClient(
  RequestHandler handler, {
  int maxRequestBytes = 8 * 1024 * 1024,
  int maxResponseBytes = 8 * 1024 * 1024,
  String? serviceRoot,
  DateTime Function()? clock,
}) {
  final ioClient = IOClient(HttpClient());
  final options = serviceRoot == null
      ? OpenCodeAuthOptions(
          apiKey: 'test-secret-canary',
          client: ioClient,
          userAgent: 'rook-test/1.0',
          maxRequestBytes: maxRequestBytes,
          maxResponseBytes: maxResponseBytes,
        )
      : OpenCodeAuthOptions.custom(
          apiKey: 'test-secret-canary',
          client: ioClient,
          userAgent: 'rook-test/1.0',
          serviceRoot: serviceRoot,
          maxRequestBytes: maxRequestBytes,
          maxResponseBytes: maxResponseBytes,
        );
  final recording = RecordingClient(handler);
  return _testContext(options, recording, ioClient, clock);
}

TestClientContext createTestClientWithExecutor(
  http.BaseClient executor, {
  DateTime Function()? clock,
}) {
  final ioClient = IOClient(HttpClient());
  final options = OpenCodeAuthOptions(
    apiKey: 'test-secret-canary',
    client: ioClient,
    userAgent: 'rook-test/1.0',
  );
  return _testContext(options, executor, ioClient, clock);
}

TestClientContext _testContext(
  OpenCodeAuthOptions options,
  http.BaseClient executor,
  IOClient ioClient,
  DateTime Function()? clock,
) {
  final recording = executor is RecordingClient
      ? executor
      : RecordingClient((_) => throw StateError('not a recording executor'));
  return TestClientContext(
    createOpenCodeAuthClientForTesting(options, executor, clock: clock),
    recording,
    ioClient,
  );
}

http.StreamedResponse response(
  int statusCode,
  List<List<int>> chunks, {
  Map<String, String> headers = const <String, String>{},
}) => http.StreamedResponse(
  Stream<List<int>>.fromIterable(chunks),
  statusCode,
  headers: headers,
);
