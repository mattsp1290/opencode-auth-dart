import 'dart:async';

import 'package:http/http.dart' as http;

/// Test-only executor instrumentation. It retains only counts and header
/// equality inputs; callers must not print the captured values.
final class CountingClient extends http.BaseClient {
  CountingClient(this._delegate);

  final http.BaseClient _delegate;
  final List<String?> _sessions = <String?>[];
  final List<String?> _userAgents = <String?>[];
  Completer<void>? _barrier;
  Completer<void>? _heldDispatchStarted;
  bool _closed = false;
  int dispatchCount = 0;

  bool get hasStableSession =>
      _sessions.isNotEmpty && _sessions.every((value) => value == _sessions[0]);

  bool get hasStableUserAgent =>
      _userAgents.isNotEmpty &&
      _userAgents.every((value) => value == _userAgents[0]);

  void holdNextResponse() {
    if (_barrier != null) throw StateError('A response is already held.');
    _barrier = Completer<void>();
    _heldDispatchStarted = Completer<void>();
  }

  Future<void> get heldDispatchStarted {
    final started = _heldDispatchStarted;
    if (started == null) throw StateError('No held dispatch is configured.');
    return started.future;
  }

  void releaseHeldResponse() {
    final barrier = _barrier;
    if (barrier == null || barrier.isCompleted) return;
    barrier.complete();
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    dispatchCount += 1;
    _sessions.add(request.headers['x-opencode-session']);
    _userAgents.add(request.headers['user-agent']);
    final sent = _delegate.send(request);
    final barrier = _barrier;
    if (barrier != null) {
      _heldDispatchStarted?.complete();
      _barrier = null;
      await barrier.future;
    }
    return sent;
  }

  @override
  void close() {
    if (_closed) return;
    _closed = true;
    releaseHeldResponse();
    _delegate.close();
  }
}
