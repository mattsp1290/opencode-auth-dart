import 'dart:io';

import 'package:http/io_client.dart';
import 'package:opencode_auth/opencode_auth.dart';
import 'package:test/test.dart';

void main() {
  late IOClient ioClient;

  setUp(() => ioClient = IOClient(HttpClient()));
  tearDown(() => ioClient.close());

  OpenCodeAuthOptions options({
    String apiKey = 'secret',
    String userAgent = 'rook/1.0',
    String? root,
    int maxRequestBytes = openCodeAbsoluteMaxRequestBytes,
    int maxResponseBytes = 8 * 1024 * 1024,
  }) => OpenCodeAuthOptions(
    apiKey: apiKey,
    client: ioClient,
    userAgent: userAgent,
    serviceRoot: root,
    maxRequestBytes: maxRequestBytes,
    maxResponseBytes: maxResponseBytes,
  );

  test('normalizes a strict HTTPS service root without exposing secrets', () {
    final value = options(root: 'HTTPS://Example.COM/root/');
    expect(value.serviceRoot.toString(), 'https://example.com/root');
    expect(value.toString(), isNot(contains('secret')));
  });

  test('rejects unsafe keys and user agents with fixed diagnostics', () {
    for (final key in <String>['', ' secret', 'secret\ncanary']) {
      expect(
        () => options(apiKey: key),
        throwsA(isA<OpenCodeConfigurationException>()),
      );
    }
    for (final agent in <String>['', '   ', 'rook\n1', 'é']) {
      expect(
        () => options(userAgent: agent),
        throwsA(isA<OpenCodeConfigurationException>()),
      );
    }
  });

  test('rejects ambiguous or insecure roots', () {
    for (final root in <String>[
      'http://example.com/root',
      'https://user@example.com/root',
      'https://example.com/root?query=1',
      'https://example.com/root#fragment',
      'https://example.com/a//b',
      'https://example.com/%2e%2e/escape',
      'https://example.com/a%2fb',
      'relative/path',
    ]) {
      expect(
        () => options(root: root),
        throwsA(isA<OpenCodeConfigurationException>()),
        reason: root,
      );
    }
  });

  test('enforces absolute configured ceilings', () {
    for (final limit in <int>[0, -1, openCodeAbsoluteMaxRequestBytes + 1]) {
      expect(
        () => options(maxRequestBytes: limit),
        throwsA(isA<OpenCodeConfigurationException>()),
      );
    }
    expect(
      () => options(maxResponseBytes: openCodeAbsoluteMaxResponseBytes + 1),
      throwsA(isA<OpenCodeConfigurationException>()),
    );
  });

  test('cancellation is synchronous, idempotent, and non-erroring', () async {
    final source = OpenCodeCancellationSource();
    expect(source.token.isCancelled, isFalse);
    source.cancel();
    expect(source.token.isCancelled, isTrue);
    source.cancel();
    await expectLater(source.token.whenCancelled, completes);
  });
}
