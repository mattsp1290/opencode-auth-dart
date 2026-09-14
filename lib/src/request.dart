import 'dart:collection';

import 'cancellation.dart';
import 'errors.dart';
import 'limits.dart';
import 'protocol.dart';

final class OpenCodeInferenceRequest {
  OpenCodeInferenceRequest({
    required OpenCodeProtocol protocol,
    required String conversationId,
    required List<int> body,
    Map<String, String> headers = const <String, String>{},
    this.cancellationToken,
  }) : protocol = _requireSupportedProtocol(protocol),
       conversationId = _validateConversationId(conversationId),
       body = _copyBody(body),
       headers = _copyHeaders(headers);

  final OpenCodeProtocol protocol;
  final String conversationId;
  final List<int> body;
  final Map<String, String> headers;
  final OpenCodeCancellationToken? cancellationToken;

  @override
  String toString() =>
      'OpenCodeInferenceRequest(protocol: $protocol, bodyBytes: ${body.length})';
}

OpenCodeProtocol _requireSupportedProtocol(OpenCodeProtocol value) {
  if (!value.isSupported) throw const UnsupportedProtocolException();
  return value;
}

String _validateConversationId(String value) {
  if (value.isEmpty ||
      value.length > 256 ||
      value.trim() != value ||
      value.codeUnits.any((unit) => unit < 0x21 || unit > 0x7e)) {
    throw const OpenCodeConfigurationException('conversation_id');
  }
  return value;
}

List<int> _copyBody(List<int> value) {
  if (value.length > openCodeAbsoluteMaxRequestBytes) {
    throw const OpenCodeRequestLimitException();
  }
  final result = List<int>.filled(value.length, 0);
  var index = 0;
  for (final byte in value) {
    if (byte < 0 || byte > 255) {
      throw const OpenCodeConfigurationException('body_octet');
    }
    if (index >= result.length) {
      throw const OpenCodeConfigurationException('body_length');
    }
    result[index++] = byte;
  }
  if (index != result.length) {
    throw const OpenCodeConfigurationException('body_length');
  }
  return List<int>.unmodifiable(result);
}

Map<String, String> _copyHeaders(Map<String, String> value) {
  final result = <String, String>{};
  for (final entry in value.entries) {
    final name = entry.key.toLowerCase();
    if (name != 'content-type' && name != 'accept') {
      throw const OpenCodeConfigurationException('header_name');
    }
    if (result.containsKey(name)) {
      throw const OpenCodeConfigurationException('header_duplicate');
    }
    final headerValue = entry.value;
    if (headerValue.isEmpty ||
        headerValue.length > 4096 ||
        headerValue.codeUnits.any((unit) => unit < 0x20 || unit > 0x7e)) {
      throw const OpenCodeConfigurationException('header_value');
    }
    result[name] = headerValue;
  }
  return UnmodifiableMapView(result);
}
