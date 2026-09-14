import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:http/io_client.dart';
import 'package:opencode_auth/opencode_auth.dart';
import 'package:opencode_auth/src/auth.dart'
    show createOpenCodeAuthClientForTesting;
import 'package:test/test.dart';

import 'support/counting_client.dart';

const _model = 'deepseek-v4-flash';
const _timeout = Duration(seconds: 90);

void main() {
  final enabled = Platform.environment['OPENCODE_AUTH_LIVE_TEST'] == 'true';

  test(
    'exact-model two-request tool exchange, streaming, and cancellation',
    () async {
      final apiKey = Platform.environment['OPENCODE_GO_API_KEY'];
      if (apiKey == null || apiKey.isEmpty) {
        fail('OPENCODE_GO_API_KEY is required when the live gate is enabled.');
      }
      if (Platform.environment['OPENCODE_AUTH_LIVE_MODEL'] != _model) {
        fail('Confirm the exact live model with OPENCODE_AUTH_LIVE_MODEL.');
      }

      final session = List<int>.generate(
        24,
        (_) => Random.secure().nextInt(256),
      ).map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
      final httpClient = IOClient(HttpClient());
      const userAgent = 'opencode-auth-dart-live-test/0.1.0';
      final countingClient = CountingClient(httpClient);
      final auth = createOpenCodeAuthClientForTesting(
        OpenCodeAuthOptions(
          apiKey: apiKey,
          client: httpClient,
          userAgent: userAgent,
        ),
        countingClient,
      );
      addTearDown(() async {
        await auth.close();
        countingClient.close();
      });

      stdout.writeln('live stage=tool-request model=$_model protocol=chat');
      final initialMessage = <String, Object?>{
        'role': 'user',
        'content': 'Use lookup_file for synthetic.txt and do not answer yet.',
      };
      final first = await _sendJson(auth, session, {
        'model': _model,
        'messages': [initialMessage],
        'tools': [
          {
            'type': 'function',
            'function': {
              'name': 'lookup_file',
              'description': 'Returns synthetic test content.',
              'parameters': {
                'type': 'object',
                'properties': {
                  'path': {'type': 'string'},
                },
                'required': ['path'],
              },
            },
          },
        ],
        'tool_choice': {
          'type': 'function',
          'function': {'name': 'lookup_file'},
        },
        'max_tokens': 256,
        'stream': false,
      });
      expect(countingClient.dispatchCount, 1);
      expect(countingClient.hasStableSession, isTrue);
      expect(countingClient.hasStableUserAgent, isTrue);
      final firstChoice = _firstChoice(first);
      final assistant = _objectMap(firstChoice['message']);
      final toolCalls = assistant['tool_calls'];
      if (toolCalls is! List<Object?> || toolCalls.length != 1) {
        fail('The live tool stage did not return exactly one tool call.');
      }
      final toolCall = _objectMap(toolCalls.single);
      final toolCallId = toolCall['id'];
      if (toolCallId is! String || toolCallId.isEmpty) {
        fail('The live tool stage returned no usable tool call identifier.');
      }
      stdout.writeln('live stage=tool-request finish=tool_calls pass=true');

      stdout.writeln('live stage=tool-result model=$_model protocol=chat');
      final second = await _sendJson(auth, session, {
        'model': _model,
        'messages': [
          initialMessage,
          {
            'role': 'assistant',
            'content': assistant['content'],
            'tool_calls': toolCalls,
          },
          {
            'role': 'tool',
            'tool_call_id': toolCallId,
            'content': 'Synthetic file contents: alpha.',
          },
        ],
        'max_tokens': 256,
        'stream': false,
      });
      expect(countingClient.dispatchCount, 2);
      expect(countingClient.hasStableSession, isTrue);
      expect(countingClient.hasStableUserAgent, isTrue);
      final secondChoice = _firstChoice(second);
      final finalMessage = _objectMap(secondChoice['message']);
      if (finalMessage['content'] is! String ||
          (finalMessage['content']! as String).trim().isEmpty) {
        fail('The live tool result stage returned no assistant content.');
      }
      if (secondChoice['finish_reason'] != 'stop') {
        fail('The live tool result stage did not finish normally.');
      }
      stdout.writeln('live stage=tool-result finish=stop pass=true');

      stdout.writeln('live stage=stream model=$_model protocol=chat');
      final streaming = await auth
          .send(
            OpenCodeInferenceRequest(
              protocol: OpenCodeProtocol.chatCompletions,
              conversationId: session,
              body: utf8.encode(
                jsonEncode({
                  'model': _model,
                  'messages': [
                    {'role': 'user', 'content': 'Reply with OK.'},
                  ],
                  'max_tokens': 256,
                  'stream': true,
                }),
              ),
              headers: const {
                'content-type': 'application/json',
                'accept': 'text/event-stream',
              },
            ),
          )
          .timeout(_timeout);
      expect(countingClient.dispatchCount, 3);
      final streamedBytes = await streaming.stream
          .expand((chunk) => chunk)
          .toList()
          .timeout(_timeout);
      final eventText = utf8.decode(streamedBytes);
      if (!eventText.contains('data:') || !eventText.contains('[DONE]')) {
        fail('The live stream had no data event or terminal marker.');
      }
      stdout.writeln('live stage=stream finish=terminal-marker pass=true');

      stdout.writeln('live stage=cancel model=$_model protocol=chat');
      final source = OpenCodeCancellationSource();
      countingClient.holdNextResponse();
      final cancellable = auth.send(
        OpenCodeInferenceRequest(
          protocol: OpenCodeProtocol.chatCompletions,
          conversationId: session,
          body: utf8.encode(
            jsonEncode({
              'model': _model,
              'messages': [
                {'role': 'user', 'content': 'Count slowly from one to ten.'},
              ],
              'max_tokens': 256,
              'stream': true,
            }),
          ),
          headers: const {
            'content-type': 'application/json',
            'accept': 'text/event-stream',
          },
          cancellationToken: source.token,
        ),
      );
      try {
        expect(countingClient.dispatchCount, 4);
        source.cancel();
        await expectLater(
          cancellable.timeout(_timeout),
          throwsA(isA<OpenCodeCancelledException>()),
        );
        expect(countingClient.dispatchCount, 4);
        stdout.writeln('live stage=cancel dispatches=1 pass=true');
      } finally {
        countingClient.releaseHeldResponse();
      }
    },
    skip: enabled ? false : 'Set OPENCODE_AUTH_LIVE_TEST=true to run.',
    timeout: const Timeout(Duration(minutes: 8)),
  );
}

Future<Map<String, Object?>> _sendJson(
  OpenCodeAuthClient auth,
  String session,
  Map<String, Object?> body,
) async {
  final response = await auth
      .send(
        OpenCodeInferenceRequest(
          protocol: OpenCodeProtocol.chatCompletions,
          conversationId: session,
          body: utf8.encode(jsonEncode(body)),
          headers: const {
            'content-type': 'application/json',
            'accept': 'application/json',
          },
        ),
      )
      .timeout(_timeout);
  final bytes = await response.stream
      .expand((chunk) => chunk)
      .toList()
      .timeout(_timeout);
  try {
    return _objectMap(jsonDecode(utf8.decode(bytes)));
  } catch (_) {
    fail('The live response was not a valid expected JSON object.');
  }
}

Map<String, Object?> _firstChoice(Map<String, Object?> response) {
  final choices = response['choices'];
  if (choices is! List<Object?> || choices.isEmpty) {
    fail('The live response contained no choices.');
  }
  return _objectMap(choices.first);
}

Map<String, Object?> _objectMap(Object? value) {
  if (value is! Map<String, Object?>) {
    fail('The live response had an unexpected object shape.');
  }
  return value;
}
