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
}
