import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/io_client.dart';
import 'package:integration_test/integration_test.dart';
import 'package:opencode_auth/opencode_auth.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('native identity survives host reconstruction', (tester) async {
    final contexts = await _contexts();
    final server = await HttpServer.bindSecure(
      InternetAddress.loopbackIPv4,
      0,
      contexts.server,
    );
    final sessions = <String?>[];
    final userAgents = <String?>[];
    final serverDone = server.listen((request) async {
      sessions.add(request.headers.value('x-opencode-session'));
      userAgents.add(request.headers.value(HttpHeaders.userAgentHeader));
      await request.drain<void>();
      request.response
        ..statusCode = HttpStatus.ok
        ..add(const <int>[1]);
      await request.response.close();
    }).asFuture<void>();
    addTearDown(() async {
      await server.close(force: true);
      await serverDone;
    });

    final store = _HostConversationStore();
    final first = store.loadOrCreate('first', 'stable-conversation');
    await _send(
      contexts.client,
      server.port,
      first,
      apiKey: 'host-injected-key',
    );
    final reconstructedStore = _HostConversationStore.fromSnapshot(
      store.snapshot,
    );
    await _send(
      contexts.client,
      server.port,
      reconstructedStore.loadOrCreate('first', 'must-not-replace'),
      apiKey: 'host-injected-key',
    );
    await _send(
      contexts.client,
      server.port,
      reconstructedStore.loadOrCreate('second', 'other-conversation'),
      apiKey: 'host-injected-key',
    );

    expect(sessions, [
      'stable-conversation',
      'stable-conversation',
      'other-conversation',
    ]);
    expect(userAgents, everyElement('rook/0.1.0'));
    expect(
      reconstructedStore.snapshot.values,
      isNot(contains('host-injected-key')),
    );
  });

  testWidgets('connection loss records one native receipt', (tester) async {
    final contexts = await _contexts();
    var receipts = 0;
    final server = await HttpServer.bindSecure(
      InternetAddress.loopbackIPv4,
      0,
      contexts.server,
    );
    final serverDone = server.listen((request) async {
      receipts += 1;
      await request.drain<void>();
      final socket = await request.response.detachSocket();
      socket.destroy();
    }).asFuture<void>();
    addTearDown(() async {
      await server.close(force: true);
      await serverDone;
    });

    final ioClient = IOClient(HttpClient(context: contexts.client));
    final auth = OpenCodeAuthClient(
      OpenCodeAuthOptions.custom(
        apiKey: 'host-injected-key',
        client: ioClient,
        userAgent: 'rook/0.1.0',
        serviceRoot: 'https://localhost:${server.port}/zen/go/v1',
      ),
    );
    addTearDown(() async {
      await auth.close();
      ioClient.close();
    });
    final response = await auth.send(_request('loss-conversation'));
    await expectLater(
      response.stream.drain<void>(),
      throwsA(isA<OpenCodeNetworkException>()),
    );
    await Future<void>.delayed(const Duration(seconds: 2));
    expect(receipts, 1);
  });

  testWidgets('native client refuses a redirect before its target is reached', (
    tester,
  ) async {
    final contexts = await _contexts();
    final paths = <String>[];
    final server = await HttpServer.bindSecure(
      InternetAddress.loopbackIPv4,
      0,
      contexts.server,
    );
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
    addTearDown(() async {
      await server.close(force: true);
      await serverDone;
    });
    final owned = _auth(contexts.client, server.port);
    addTearDown(owned.close);
    await expectLater(
      owned.auth.send(_request('redirect-conversation')),
      throwsA(isA<OpenCodeRedirectException>()),
    );
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(paths, ['/zen/go/v1/chat/completions']);
  });

  testWidgets('cancellation stops a native response stream after first chunk', (
    tester,
  ) async {
    final contexts = await _contexts();
    final release = Completer<void>();
    final server = await HttpServer.bindSecure(
      InternetAddress.loopbackIPv4,
      0,
      contexts.server,
    );
    final serverDone = server.listen((request) async {
      await request.drain<void>();
      request.response
        ..bufferOutput = false
        ..add(const <int>[1]);
      await request.response.flush();
      await release.future;
      request.response.add(const <int>[2]);
      await request.response.close();
    }).asFuture<void>();
    addTearDown(() async {
      if (!release.isCompleted) release.complete();
      await server.close(force: true);
      await serverDone;
    });
    final source = OpenCodeCancellationSource();
    final owned = _auth(contexts.client, server.port);
    addTearDown(owned.close);
    final response = await owned.auth.send(
      OpenCodeInferenceRequest(
        protocol: OpenCodeProtocol.chatCompletions,
        conversationId: 'cancel-conversation',
        body: const <int>[1, 2, 3],
        headers: const {'content-type': 'application/json'},
        cancellationToken: source.token,
      ),
    );
    final terminal = Completer<Object>();
    final subscription = response.stream.listen(
      (_) => source.cancel(),
      onError: (Object error) {
        if (!terminal.isCompleted) terminal.complete(error);
      },
    );
    await expectLater(
      terminal.future,
      completion(isA<OpenCodeCancelledException>()),
    );
    await subscription.cancel();
  });

  for (final stage in _DisconnectStage.values) {
    testWidgets('connection loss at $stage has one receipt', (tester) async {
      final contexts = await _contexts();
      var receipts = 0;
      final server = await HttpServer.bindSecure(
        InternetAddress.loopbackIPv4,
        0,
        contexts.server,
      );
      final serverDone = server.listen((request) async {
        receipts += 1;
        switch (stage) {
          case _DisconnectStage.duringUpload:
            final subscription = request.listen((_) async {
              final socket = await request.response.detachSocket();
              socket.destroy();
            });
            await subscription.asFuture<void>();
          case _DisconnectStage.beforeResponse:
            await request.drain<void>();
            final socket = await request.response.detachSocket();
            socket.destroy();
          case _DisconnectStage.afterHeaders:
            await request.drain<void>();
            request.response
              ..bufferOutput = false
              ..add(const <int>[1]);
            await request.response.flush();
            final socket = await request.response.detachSocket();
            socket.destroy();
        }
      }).asFuture<void>();
      addTearDown(() async {
        await server.close(force: true);
        await serverDone;
      });
      final owned = _auth(contexts.client, server.port);
      addTearDown(owned.close);
      try {
        final response = await owned.auth.send(
          _request('loss-$stage', body: List<int>.filled(2 * 1024 * 1024, 7)),
        );
        await response.stream.drain<void>();
      } on OpenCodeNetworkException {
        // Expected: the host, rather than this package, decides whether to retry.
      }
      await Future<void>.delayed(const Duration(seconds: 2));
      expect(receipts, 1);
    });
  }
}

Future<void> _send(
  SecurityContext context,
  int port,
  String conversationId, {
  required String apiKey,
}) async {
  final ioClient = IOClient(HttpClient(context: context));
  final auth = OpenCodeAuthClient(
    OpenCodeAuthOptions.custom(
      apiKey: apiKey,
      client: ioClient,
      userAgent: 'rook/0.1.0',
      serviceRoot: 'https://localhost:$port/zen/go/v1',
    ),
  );
  if (auth.endpointBinding != OpenCodeEndpointBinding.custom) {
    throw StateError('The localhost fixture must use a custom binding.');
  }
  try {
    await (await auth.send(_request(conversationId))).stream.drain<void>();
  } finally {
    await auth.close();
    ioClient.close();
  }
}

OpenCodeInferenceRequest _request(String conversationId, {List<int>? body}) =>
    OpenCodeInferenceRequest(
      protocol: OpenCodeProtocol.chatCompletions,
      conversationId: conversationId,
      body: body ?? const <int>[1, 2, 3],
      headers: const {'content-type': 'application/json'},
    );

_OwnedAuth _auth(SecurityContext context, int port) {
  final ioClient = IOClient(HttpClient(context: context));
  final auth = OpenCodeAuthClient(
    OpenCodeAuthOptions.custom(
      apiKey: 'host-injected-key',
      client: ioClient,
      userAgent: 'rook/0.1.0',
      serviceRoot: 'https://localhost:$port/zen/go/v1',
    ),
  );
  if (auth.endpointBinding != OpenCodeEndpointBinding.custom) {
    throw StateError('The localhost fixture must use a custom binding.');
  }
  return _OwnedAuth(auth, ioClient);
}

Future<({SecurityContext server, SecurityContext client})> _contexts() async {
  final certificate = await rootBundle.load('assets/localhost-cert.pem');
  final key = await rootBundle.load('assets/localhost-key.pem');
  Uint8List bytes(ByteData data) =>
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  final server = SecurityContext()
    ..useCertificateChainBytes(bytes(certificate))
    ..usePrivateKeyBytes(bytes(key));
  final client = SecurityContext(withTrustedRoots: false)
    ..setTrustedCertificatesBytes(bytes(certificate));
  return (server: server, client: client);
}

final class _HostConversationStore {
  _HostConversationStore();
  _HostConversationStore.fromSnapshot(Map<String, String> values)
    : _values = Map<String, String>.of(values);

  Map<String, String> _values = <String, String>{};

  Map<String, String> get snapshot => Map<String, String>.unmodifiable(_values);

  String loadOrCreate(String key, String candidate) =>
      _values.putIfAbsent(key, () => candidate);
}

enum _DisconnectStage { duringUpload, beforeResponse, afterHeaders }

final class _OwnedAuth {
  _OwnedAuth(this.auth, this._client);

  final OpenCodeAuthClient auth;
  final IOClient _client;

  Future<void> close() async {
    await auth.close();
    _client.close();
  }
}
