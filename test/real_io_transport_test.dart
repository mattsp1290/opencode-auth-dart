import 'dart:async';
import 'dart:io';

import 'package:http/io_client.dart';
import 'package:opencode_auth/opencode_auth.dart';
import 'package:test/test.dart';

void main() {
  late SecurityContext serverContext;
  late SecurityContext clientContext;

  setUpAll(() {
    serverContext = SecurityContext()
      ..useCertificateChain('test/support/localhost-cert.pem')
      ..usePrivateKey('test/support/localhost-key.pem');
    clientContext = SecurityContext(withTrustedRoots: false)
      ..setTrustedCertificates('test/support/localhost-cert.pem');
  });

  test(
    'native IOClient refuses redirects and never reaches their target',
    () async {
      final paths = <String>[];
      final server = await HttpServer.bindSecure(
        InternetAddress.loopbackIPv4,
        0,
        serverContext,
      );
      addTearDown(server.close);
      final serverDone = server.listen((request) async {
        paths.add(request.uri.path);
        await request.drain<void>();
        if (request.uri.path.endsWith('/chat/completions')) {
          request.response
            ..statusCode = HttpStatus.temporaryRedirect
            ..headers.set(HttpHeaders.locationHeader, '/credential-target');
        }
        await request.response.close();
      }).asFuture<void>();

      final ioClient = IOClient(HttpClient(context: clientContext));
      final auth = OpenCodeAuthClient(
        OpenCodeAuthOptions.custom(
          apiKey: 'native-test-secret',
          client: ioClient,
          userAgent: 'native-test/1.0',
          serviceRoot: 'https://localhost:${server.port}/zen/go/v1',
        ),
      );
      addTearDown(() async {
        await auth.close();
        ioClient.close();
      });

      await expectLater(
        auth.send(_request()),
        throwsA(isA<OpenCodeRedirectException>()),
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(paths, ['/zen/go/v1/chat/completions']);
      await server.close(force: true);
      await serverDone;
    },
  );

  test('native IOClient exposes incremental opaque response chunks', () async {
    final releaseSecond = Completer<void>();
    final received = Completer<List<int>>();
    final server = await HttpServer.bindSecure(
      InternetAddress.loopbackIPv4,
      0,
      serverContext,
    );
    addTearDown(server.close);
    final serverDone = server.listen((request) async {
      received.complete(
        await request.fold<List<int>>(
          <int>[],
          (all, chunk) => all..addAll(chunk),
        ),
      );
      request.response
        ..statusCode = HttpStatus.ok
        ..bufferOutput = false
        ..add(const <int>[1, 2]);
      await request.response.flush();
      await releaseSecond.future;
      request.response.add(const <int>[3, 4]);
      await request.response.close();
    }).asFuture<void>();

    final ioClient = IOClient(HttpClient(context: clientContext));
    final auth = OpenCodeAuthClient(
      OpenCodeAuthOptions.custom(
        apiKey: 'native-test-secret',
        client: ioClient,
        userAgent: 'native-test/1.0',
        serviceRoot: 'https://localhost:${server.port}/zen/go/v1',
      ),
    );
    addTearDown(() async {
      if (!releaseSecond.isCompleted) releaseSecond.complete();
      await auth.close();
      ioClient.close();
    });

    final response = await auth.send(_request());
    final chunks = <List<int>>[];
    final first = Completer<void>();
    final subscription = response.stream.listen((chunk) {
      chunks.add(chunk);
      if (!first.isCompleted) first.complete();
    });
    await first.future.timeout(const Duration(seconds: 2));
    expect(chunks, [
      <int>[1, 2],
    ]);
    expect(await received.future, <int>[9, 8, 7]);
    releaseSecond.complete();
    await subscription.asFuture<void>();
    await subscription.cancel();
    expect(chunks, [
      <int>[1, 2],
      <int>[3, 4],
    ]);
    await server.close(force: true);
    await serverDone;
  });

  test('connection loss produces one receipt and no transport retry', () async {
    var receipts = 0;
    final server = await HttpServer.bindSecure(
      InternetAddress.loopbackIPv4,
      0,
      serverContext,
    );
    addTearDown(server.close);
    final serverDone = server.listen((request) async {
      receipts += 1;
      await request.drain<void>();
      final socket = await request.response.detachSocket();
      socket.destroy();
    }).asFuture<void>();

    final ioClient = IOClient(HttpClient(context: clientContext));
    final auth = OpenCodeAuthClient(
      OpenCodeAuthOptions.custom(
        apiKey: 'native-test-secret',
        client: ioClient,
        userAgent: 'native-test/1.0',
        serviceRoot: 'https://localhost:${server.port}/zen/go/v1',
      ),
    );
    addTearDown(() async {
      await auth.close();
      ioClient.close();
    });

    final response = await auth.send(_request());
    await expectLater(
      response.stream.drain<void>(),
      throwsA(isA<OpenCodeNetworkException>()),
    );
    await Future<void>.delayed(const Duration(milliseconds: 250));
    expect(receipts, 1);
    await server.close(force: true);
    await serverDone;
  });
}

OpenCodeInferenceRequest _request() => OpenCodeInferenceRequest(
  protocol: OpenCodeProtocol.chatCompletions,
  conversationId: 'native-conversation',
  body: const <int>[9, 8, 7],
  headers: const {'content-type': 'application/json'},
);
