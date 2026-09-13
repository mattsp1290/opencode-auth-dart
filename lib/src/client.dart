import 'dart:async';

import 'package:http/http.dart' as http;

import 'cancellation.dart';
import 'catalog.dart';
import 'errors.dart';
import 'options.dart';
import 'protocol.dart';
import 'request.dart';
import 'response.dart';
import 'transport.dart';

final class OpenCodeAuthClient {
  OpenCodeAuthClient(OpenCodeAuthOptions options)
    : this._(options, options.client, DateTime.now);

  OpenCodeAuthClient._(this._options, this._client, this._clock);

  final OpenCodeAuthOptions _options;
  final http.BaseClient _client;
  final DateTime Function() _clock;
  final Set<OpenCodeOperation> _operations = <OpenCodeOperation>{};
  bool _closed = false;
  Future<void>? _closeFuture;

  Future<OpenCodeStreamResponse> send(
    OpenCodeInferenceRequest inferenceRequest,
  ) async {
    _ensureOpen();
    throwIfOpenCodeCancelled(inferenceRequest.cancellationToken);
    if (!inferenceRequest.protocol.isSupported) {
      throw const UnsupportedProtocolException();
    }
    if (inferenceRequest.body.length > _options.maxRequestBytes) {
      throw const OpenCodeRequestLimitException();
    }

    final operation = _startOperation(inferenceRequest.cancellationToken);
    final request =
        http.AbortableRequest(
            'POST',
            _route('chat/completions'),
            abortTrigger: operation.whenAborted,
          )
          ..followRedirects = false
          ..maxRedirects = 0
          ..bodyBytes = inferenceRequest.body;
    request.headers
      ..addAll(inferenceRequest.headers)
      ..['authorization'] = 'Bearer ${openCodeTransportApiKey(_options)}'
      ..['user-agent'] = _options.userAgent
      ..['x-opencode-session'] = inferenceRequest.conversationId;

    final response = await _dispatch(request, operation);
    if (operation.isAborted) {
      unawaited(response.stream.listen(null).cancel());
      throw const OpenCodeCancelledException();
    }
    if (response.statusCode >= 300 && response.statusCode < 400) {
      unawaited(response.stream.listen(null).cancel());
      operation.finish();
      throw OpenCodeRedirectException(response.statusCode);
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      try {
        final bytes = await readOpenCodeBounded(
          response.stream,
          64 * 1024,
          operation,
        );
        throw classifyOpenCodeHttpFailure(
          response.statusCode,
          bytes,
          response.headers['retry-after'],
          _clock,
        );
      } on OpenCodeAuthException {
        rethrow;
      } catch (_) {
        if (operation.isAborted) throw const OpenCodeCancelledException();
        throw OpenCodeHttpException(response.statusCode);
      } finally {
        operation.finish();
      }
    }
    return _streamSuccess(response, operation);
  }

  Future<List<OpenCodeModel>> listModels({
    OpenCodeCancellationToken? cancellationToken,
  }) async {
    _ensureOpen();
    throwIfOpenCodeCancelled(cancellationToken);
    final operation = _startOperation(cancellationToken);
    final request =
        http.AbortableRequest(
            'GET',
            _route('models'),
            abortTrigger: operation.whenAborted,
          )
          ..followRedirects = false
          ..maxRedirects = 0;
    request.headers
      ..['accept'] = 'application/json'
      ..['user-agent'] = _options.userAgent;

    try {
      final response = await _dispatch(request, operation);
      if (operation.isAborted) {
        unawaited(response.stream.listen(null).cancel());
        throw const OpenCodeCancelledException();
      }
      if (response.statusCode >= 300 && response.statusCode < 400) {
        unawaited(response.stream.listen(null).cancel());
        throw OpenCodeRedirectException(response.statusCode);
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final bytes = await readOpenCodeBounded(
          response.stream,
          64 * 1024,
          operation,
        );
        throw classifyOpenCodeHttpFailure(
          response.statusCode,
          bytes,
          response.headers['retry-after'],
          _clock,
        );
      }
      final bytes = await readOpenCodeBounded(
        response.stream,
        8 * 1024 * 1024,
        operation,
      );
      return decodeOpenCodeCatalog(bytes);
    } on OpenCodeAuthException {
      rethrow;
    } catch (_) {
      if (operation.isAborted) throw const OpenCodeCancelledException();
      throw const OpenCodeNetworkException();
    } finally {
      operation.finish();
    }
  }

  Future<void> close() => _closeFuture ??= _close();

  Future<void> _close() async {
    _closed = true;
    final active = _operations.toList(growable: false);
    for (final operation in active) {
      operation.abort();
    }
    await Future.wait(active.map((operation) => operation.whenFinished));
  }

  void _ensureOpen() {
    if (_closed) throw const OpenCodeClosedException();
  }

  OpenCodeOperation _startOperation(OpenCodeCancellationToken? token) {
    _ensureOpen();
    late final OpenCodeOperation operation;
    operation = OpenCodeOperation(() {
      _operations.removeWhere((candidate) => identical(candidate, operation));
    });
    _operations.add(operation);
    if (token != null) {
      if (token.isCancelled) {
        operation.abort();
      } else {
        unawaited(token.whenCancelled.then((_) => operation.abort()));
      }
    }
    return operation;
  }

  Future<http.StreamedResponse> _dispatch(
    http.BaseRequest request,
    OpenCodeOperation operation,
  ) {
    if (operation.isAborted) {
      operation.finish();
      throw const OpenCodeCancelledException();
    }
    final publicResult = Completer<http.StreamedResponse>.sync();
    operation.onAbort = () {
      if (!publicResult.isCompleted) {
        publicResult.completeError(const OpenCodeCancelledException());
      }
      operation.finish();
    };
    Future<http.StreamedResponse> sent;
    try {
      if (operation.isAborted) {
        operation.finish();
        throw const OpenCodeCancelledException();
      }
      sent = _client.send(request);
    } on OpenCodeAuthException {
      operation.onAbort = null;
      operation.finish();
      rethrow;
    } catch (_) {
      operation.onAbort = null;
      operation.finish();
      throw const OpenCodeNetworkException();
    }
    unawaited(
      sent.then(
        (response) {
          if (operation.isAborted || publicResult.isCompleted) {
            unawaited(response.stream.listen(null).cancel());
            operation.finish();
          } else {
            publicResult.complete(response);
          }
        },
        onError: (Object _, StackTrace _) {
          if (!publicResult.isCompleted) {
            publicResult.completeError(
              operation.isAborted
                  ? const OpenCodeCancelledException()
                  : const OpenCodeNetworkException(),
            );
          }
          operation.finish();
        },
      ),
    );
    return publicResult.future;
  }

  OpenCodeStreamResponse _streamSuccess(
    http.StreamedResponse response,
    OpenCodeOperation operation,
  ) {
    final controller = StreamController<List<int>>();
    StreamSubscription<List<int>>? upstream;
    var terminal = false;
    var byteCount = 0;

    void finish() {
      if (terminal) return;
      terminal = true;
      operation.finish();
    }

    Future<void> cancel({required bool emitError}) async {
      if (terminal) return;
      terminal = true;
      operation.abort();
      if (emitError && !controller.isClosed) {
        controller.addError(const OpenCodeCancelledException());
        unawaited(controller.close());
      }
      final cancellation = upstream?.cancel();
      if (cancellation != null) {
        unawaited(cancellation.catchError((Object _) {}));
      }
      operation.finish();
    }

    operation.onAbort = () {
      unawaited(cancel(emitError: true));
    };
    controller.onPause = () => upstream?.pause();
    controller.onResume = () => upstream?.resume();
    controller.onCancel = () => cancel(emitError: false);

    try {
      upstream = response.stream.listen(
        (chunk) {
          if (terminal) return;
          byteCount += chunk.length;
          if (byteCount > _options.maxResponseBytes) {
            terminal = true;
            operation.abort();
            controller.addError(const OpenCodeResponseLimitException());
            unawaited(controller.close());
            final cancellation = upstream?.cancel();
            if (cancellation != null) {
              unawaited(cancellation.catchError((Object _) {}));
            }
            operation.finish();
            return;
          }
          controller.add(chunk);
        },
        onError: (Object _, StackTrace _) {
          if (terminal) return;
          controller.addError(
            operation.isAborted
                ? const OpenCodeCancelledException()
                : const OpenCodeNetworkException(),
          );
          unawaited(controller.close());
          finish();
        },
        onDone: () {
          if (terminal) return;
          unawaited(controller.close());
          finish();
        },
        cancelOnError: true,
      );
    } catch (_) {
      operation.onAbort = null;
      operation.finish();
      unawaited(controller.close());
      throw const OpenCodeNetworkException();
    }

    return OpenCodeStreamResponse(
      statusCode: response.statusCode,
      contentType: _safeContentType(response.headers['content-type']),
      stream: controller.stream,
      onCancel: () => cancel(emitError: true),
    );
  }

  Uri _route(String suffix) => Uri.parse('${_options.serviceRoot}/$suffix');
}

/// Internal test seam. It is intentionally omitted from the public barrel.
OpenCodeAuthClient createOpenCodeAuthClientForTesting(
  OpenCodeAuthOptions options,
  http.BaseClient executor, {
  DateTime Function()? clock,
}) => OpenCodeAuthClient._(options, executor, clock ?? DateTime.now);

String? _safeContentType(String? value) {
  if (value == null ||
      value.isEmpty ||
      value.length > 256 ||
      value.contains(',') ||
      value.codeUnits.any((unit) => unit < 0x20 || unit > 0x7e)) {
    return null;
  }
  return value;
}
