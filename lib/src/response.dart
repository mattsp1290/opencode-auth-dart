import 'dart:async';

final class OpenCodeStreamResponse {
  OpenCodeStreamResponse({
    required this.statusCode,
    required this.contentType,
    required this.stream,
    required Future<void> Function() onCancel,
  }) : _onCancel = onCancel; // ignore: prefer_initializing_formals

  final int statusCode;
  final String? contentType;
  final Stream<List<int>> stream;
  final Future<void> Function() _onCancel;
  Future<void>? _cancelFuture;

  Future<void> cancel() => _cancelFuture ??= _onCancel();

  @override
  String toString() =>
      'OpenCodeStreamResponse(statusCode: $statusCode, contentType: '
      '${contentType == null ? 'absent' : 'present'})';
}
