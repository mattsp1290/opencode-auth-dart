import 'dart:convert';
import 'dart:io';

import 'package:http/io_client.dart';
import 'package:opencode_auth/opencode_auth.dart';

Future<void> main() async {
  final apiKey = Platform.environment['OPENCODE_GO_API_KEY'];
  final conversationId = Platform.environment['OPENCODE_CONVERSATION_ID'];
  final userAgent = Platform.environment['OPENCODE_USER_AGENT'];
  if (apiKey == null || conversationId == null || userAgent == null) {
    stderr.writeln(
      'Set OPENCODE_GO_API_KEY, OPENCODE_CONVERSATION_ID, and '
      'OPENCODE_USER_AGENT.',
    );
    exitCode = 64;
    return;
  }

  final httpClient = IOClient(HttpClient());
  final auth = OpenCodeAuthClient(
    OpenCodeAuthOptions(
      apiKey: apiKey,
      client: httpClient,
      userAgent: userAgent,
    ),
  );
  final cancellation = OpenCodeCancellationSource();
  try {
    final nativeBody = utf8.encode(
      jsonEncode({
        'model': 'deepseek-v4-flash',
        'messages': [
          {'role': 'user', 'content': 'Reply with one short greeting.'},
        ],
        'stream': true,
        'max_tokens': 256,
      }),
    );
    final response = await auth.send(
      OpenCodeInferenceRequest(
        protocol: OpenCodeProtocol.chatCompletions,
        conversationId: conversationId,
        body: nativeBody,
        headers: const {
          'content-type': 'application/json',
          'accept': 'text/event-stream',
        },
        cancellationToken: cancellation.token,
      ),
    );
    var receivedBytes = 0;
    await for (final chunk in response.stream) {
      receivedBytes += chunk.length;
    }
    stdout.writeln(
      'Chat Completions finished with status ${response.statusCode}; '
      'received $receivedBytes opaque bytes.',
    );
  } on OpenCodeAuthException catch (error) {
    stderr.writeln('OpenCode request failed: ${error.code}.');
    exitCode = 1;
  } finally {
    await auth.close();
    httpClient.close();
  }
}
