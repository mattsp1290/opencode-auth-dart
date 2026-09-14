import 'dart:convert';

import 'package:opencode_auth/opencode_auth.dart';
import 'package:test/test.dart';

import 'support/recording_client.dart';

void main() {
  test(
    'provider accepts only the package-owned subscription binding',
    () async {
      final sentBodies = <String>[];
      final context = createTestClient((request) async {
        final bytes = await request.finalize().fold<List<int>>(
          <int>[],
          (all, chunk) => all..addAll(chunk),
        );
        sentBodies.add(utf8.decode(bytes));
        return response(200, const <List<int>>[]);
      });
      addTearDown(context.close);

      final provider = _ProviderAdapter(context.auth);
      final first = await provider.send(body: 'initial-tool-request');
      await first.stream.drain<void>();
      final second = await provider.send(body: 'tool-result-turn');
      await second.stream.drain<void>();
      expect(
        context.auth.endpointBinding,
        OpenCodeEndpointBinding.subscriptionGo,
      );
      expect(context.recording.requests, hasLength(2));
      expect(
        context.recording.requests
            .map((request) => request.headers['x-opencode-session'])
            .toSet(),
        {'provider-conversation'},
      );
      expect(
        context.recording.requests
            .map((request) => request.headers['user-agent'])
            .toSet(),
        {'rook-test/1.0'},
      );
      expect(sentBodies, [
        '{"model":"deepseek-v4-flash","turn":"initial-tool-request"}',
        '{"model":"deepseek-v4-flash","turn":"tool-result-turn"}',
      ]);
    },
  );

  for (final root in <String>[
    'https://example.test/v1',
    'https://api.openai.com/v1',
    'https://wrong-host.test/zen/go/v1',
    'https://opencode.ai/zen/go/v1',
  ]) {
    test('provider rejects custom binding before dispatch: $root', () async {
      final context = createTestClient(
        (_) => response(200, const <List<int>>[]),
        serviceRoot: root,
      );
      addTearDown(context.close);

      await expectLater(
        Future<OpenCodeStreamResponse>.sync(
          () => _ProviderAdapter(context.auth).send(),
        ),
        throwsA(
          isA<_ProviderBindingException>()
              .having(
                (error) => error.toString(),
                'redacted',
                isNot(contains(root)),
              )
              .having(
                (error) => error.toString(),
                'credential',
                isNot(contains('test-secret-canary')),
              )
              .having(
                (error) => error.toString(),
                'identity',
                isNot(contains('rook-test/1.0')),
              ),
        ),
      );
      expect(context.recording.requests, isEmpty);
    });
  }
}

final class _ProviderAdapter {
  _ProviderAdapter(this._auth);

  final OpenCodeAuthClient _auth;

  Future<OpenCodeStreamResponse> send({String body = 'request'}) {
    if (_auth.endpointBinding != OpenCodeEndpointBinding.subscriptionGo) {
      throw const _ProviderBindingException();
    }
    return _auth.send(
      OpenCodeInferenceRequest(
        protocol: OpenCodeProtocol.chatCompletions,
        conversationId: 'provider-conversation',
        body: utf8.encode('{"model":"deepseek-v4-flash","turn":"$body"}'),
        headers: const <String, String>{'content-type': 'application/json'},
      ),
    );
  }
}

final class _ProviderBindingException implements Exception {
  const _ProviderBindingException();

  @override
  String toString() => 'Provider requires endpoint binding subscriptionGo.';
}
