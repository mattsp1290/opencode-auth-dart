import 'dart:async';

import 'cancellation.dart';
import 'errors.dart';

/// Source-internal operation state shared by dispatch and response readers.
final class OpenCodeOperation {
  OpenCodeOperation(this._onFinished);

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

void throwIfOpenCodeCancelled(OpenCodeCancellationToken? token) {
  if (token?.isCancelled ?? false) throw const OpenCodeCancelledException();
}

Future<List<int>> readOpenCodeBounded(
  Stream<List<int>> stream,
  int limit,
  OpenCodeOperation operation,
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
