import 'dart:async';

/// A package-owned, non-erroring cancellation signal.
final class OpenCodeCancellationToken {
  OpenCodeCancellationToken._(this._completer);

  final Completer<void> _completer;
  bool _isCancelled = false;

  bool get isCancelled => _isCancelled;
  Future<void> get whenCancelled => _completer.future;
}

/// Creates and controls an [OpenCodeCancellationToken].
final class OpenCodeCancellationSource {
  OpenCodeCancellationSource() : _completer = Completer<void>.sync() {
    token = OpenCodeCancellationToken._(_completer);
  }

  final Completer<void> _completer;
  late final OpenCodeCancellationToken token;

  void cancel() {
    if (token._isCancelled) return;
    token._isCancelled = true;
    _completer.complete();
  }
}
