import 'dart:async';
import 'dart:convert';
import 'dart:io' show HttpDate;
import 'dart:math' as math;

import 'package:http/http.dart' as http;

import 'cancellation.dart';
import 'catalog.dart';
import 'errors.dart';
import 'options.dart';
import 'protocol.dart';
import 'request.dart';
import 'response.dart';

final class OpenCodeAuthClient {
  OpenCodeAuthClient(OpenCodeAuthOptions options)
    : this._(options, options.client);

  OpenCodeAuthClient._(this._options, this._client);

  final OpenCodeAuthOptions _options;
  final http.BaseClient _client;
  final Set<_Operation> _operations = <_Operation>{};
  bool _closed = false;
  Future<void>? _closeFuture;

  Future<OpenCodeStreamResponse> send(
    OpenCodeInferenceRequest inferenceRequest,
  ) async {
    _ensureOpen();
    _checkCancelled(inferenceRequest.cancellationToken);
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
      ..['authorization'] = 'Bearer ${_options.apiKey}'
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
        final bytes = await _readBounded(response.stream, 64 * 1024, operation);
        throw _classifyHttp(
          response.statusCode,
          bytes,
          response.headers['retry-after'],
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
    _checkCancelled(cancellationToken);
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
        final bytes = await _readBounded(response.stream, 64 * 1024, operation);
        throw _classifyHttp(
          response.statusCode,
          bytes,
          response.headers['retry-after'],
        );
      }
      final bytes = await _readBounded(
        response.stream,
        8 * 1024 * 1024,
        operation,
      );
      return _decodeCatalog(bytes);
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

  _Operation _startOperation(OpenCodeCancellationToken? token) {
    _ensureOpen();
    late final _Operation operation;
    operation = _Operation(() {
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
    _Operation operation,
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
      rethrow;
    } catch (_) {
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
    _Operation operation,
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
  http.BaseClient executor,
) => OpenCodeAuthClient._(options, executor);

final class _Operation {
  _Operation(this._onFinished);

  final void Function() _onFinished;
  final Completer<void> _abort = Completer<void>.sync();
  final Completer<void> _finished = Completer<void>.sync();
  void Function()? onAbort;

  bool get isAborted => _abort.isCompleted;
  Future<void> get whenAborted => _abort.future;
  Future<void> get whenFinished => _finished.future;

  void abort() {
    if (_abort.isCompleted) return;
    _abort.complete();
    onAbort?.call();
  }

  void finish() {
    if (_finished.isCompleted) return;
    _finished.complete();
    _onFinished();
  }
}

void _checkCancelled(OpenCodeCancellationToken? token) {
  if (token?.isCancelled ?? false) {
    throw const OpenCodeCancelledException();
  }
}

Future<List<int>> _readBounded(
  Stream<List<int>> stream,
  int limit,
  _Operation operation,
) {
  final result = <int>[];
  final completed = Completer<List<int>>.sync();
  StreamSubscription<List<int>>? subscription;

  void cancelSubscription() {
    final cancellation = subscription?.cancel();
    if (cancellation != null) {
      unawaited(cancellation.catchError((Object _) {}));
    }
  }

  operation.onAbort = () {
    if (!completed.isCompleted) {
      completed.completeError(const OpenCodeCancelledException());
      cancelSubscription();
    }
  };
  subscription = stream.listen(
    (chunk) {
      if (completed.isCompleted) return;
      if (result.length + chunk.length > limit) {
        completed.completeError(const OpenCodeResponseLimitException());
        operation.abort();
        cancelSubscription();
        return;
      }
      result.addAll(chunk);
    },
    onError: (Object _, StackTrace stackTrace) {
      if (!completed.isCompleted) {
        completed.completeError(
          operation.isAborted
              ? const OpenCodeCancelledException()
              : const OpenCodeNetworkException(),
          stackTrace,
        );
      }
    },
    onDone: () {
      if (!completed.isCompleted) completed.complete(result);
    },
    cancelOnError: true,
  );
  if (operation.isAborted) operation.onAbort?.call();
  return completed.future;
}

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

List<OpenCodeModel> _decodeCatalog(List<int> bytes) {
  Object? decoded;
  try {
    decoded = jsonDecode(utf8.decode(bytes));
  } catch (_) {
    throw const OpenCodeProtocolException();
  }
  if (decoded is! Map<String, Object?> ||
      decoded['object'] != 'list' ||
      decoded['data'] is! List<Object?>) {
    throw const OpenCodeProtocolException();
  }
  final models = <OpenCodeModel>[];
  for (final item in decoded['data']! as List<Object?>) {
    if (item is! Map<String, Object?>) {
      throw const OpenCodeProtocolException();
    }
    final id = item['id'];
    final object = item['object'];
    final created = item['created'];
    final ownedBy = item['owned_by'];
    if (id is! String ||
        id.isEmpty ||
        (object != null && object is! String) ||
        (created != null && created is! int) ||
        (ownedBy != null && ownedBy is! String)) {
      throw const OpenCodeProtocolException();
    }
    models.add(
      OpenCodeModel(
        id: id,
        object: object as String?,
        created: created as int?,
        ownedBy: ownedBy as String?,
      ),
    );
  }
  return List<OpenCodeModel>.unmodifiable(models);
}

OpenCodeAuthException _classifyHttp(
  int statusCode,
  List<int> body,
  String? retryAfter,
) {
  String? type;
  String? code;
  try {
    final decoded = jsonDecode(utf8.decode(body));
    if (decoded is Map<String, Object?>) {
      final error = decoded['error'];
      if (error is Map<String, Object?>) {
        if (error['type'] is String) type = error['type']! as String;
        if (error['code'] is String) code = error['code']! as String;
      }
    }
  } catch (_) {
    return OpenCodeHttpException(statusCode);
  }
  if (type == null && code == null) return OpenCodeHttpException(statusCode);
  final categories = <String>{?type, ?code};
  const auth = {'AuthError', 'authentication_error', 'invalid_api_key'};
  const quota = {
    'CreditsError',
    'MonthlyLimitError',
    'UserLimitError',
    'GoUsageLimitError',
    'FreeUsageLimitError',
    'BlackUsageLimitError',
    'insufficient_quota',
  };
  const rate = {'RateLimitError', 'rate_limit_error'};
  const model = {'ModelError'};
  const policy = {'RegionError', 'DataPolicyError'};
  final matches = <String>{
    if (categories.any(auth.contains)) 'auth',
    if (categories.any(quota.contains)) 'quota',
    if (categories.any(rate.contains)) 'rate',
    if (categories.any(model.contains)) 'model',
    if (categories.any(policy.contains)) 'policy',
  };
  if (matches.length != 1) return OpenCodeHttpException(statusCode);
  return switch (matches.single) {
    'auth' => const OpenCodeAuthenticationException(),
    'quota' => const OpenCodeQuotaException(),
    'rate' => OpenCodeRateLimitException(
      retryAfter: _parseRetryAfter(retryAfter),
    ),
    'model' => const OpenCodeModelException(),
    'policy' => const OpenCodePolicyException(),
    _ => OpenCodeHttpException(statusCode),
  };
}

Duration? _parseRetryAfter(String? value) {
  if (value == null ||
      value.isEmpty ||
      value.length > 128 ||
      value.contains(',')) {
    return null;
  }
  final seconds = int.tryParse(value);
  if (seconds != null) {
    if (seconds < 0 || seconds > 86400) return null;
    return Duration(seconds: seconds);
  }
  try {
    final date = HttpDate.parse(value).toUtc();
    final delta = date.difference(DateTime.now().toUtc());
    if (delta.isNegative) return null;
    return Duration(seconds: math.min(delta.inSeconds, 86400));
  } catch (_) {
    return null;
  }
}
