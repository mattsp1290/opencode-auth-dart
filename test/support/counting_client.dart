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
    final response = await _delegate.send(request);
    final barrier = _barrier;
    if (barrier != null) {
      _barrier = null;
      await barrier.future;
    }
    return response;
  }

  @override
  void close() {
    if (_closed) return;
    _closed = true;
    releaseHeldResponse();
    _delegate.close();
  }
}
