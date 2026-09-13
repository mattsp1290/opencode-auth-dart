import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

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
      OpenCodeAuthOptions(
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
}

Future<void> _send(
  SecurityContext context,
  int port,
  String conversationId, {
  required String apiKey,
}) async {
  final ioClient = IOClient(HttpClient(context: context));
  final auth = OpenCodeAuthClient(
    OpenCodeAuthOptions(
      apiKey: apiKey,
      client: ioClient,
      userAgent: 'rook/0.1.0',
      serviceRoot: 'https://localhost:$port/zen/go/v1',
    ),
  );
  try {
    await (await auth.send(_request(conversationId))).stream.drain<void>();
  } finally {
    await auth.close();
    ioClient.close();
  }
}

OpenCodeInferenceRequest _request(String conversationId) =>
    OpenCodeInferenceRequest(
      protocol: OpenCodeProtocol.chatCompletions,
      conversationId: conversationId,
      body: const <int>[1, 2, 3],
      headers: const {'content-type': 'application/json'},
    );

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
