part of 'auth.dart';

enum OpenCodeEndpointBinding { subscriptionGo, custom }

const _subscriptionGoRoot = 'https://opencode.ai/zen/go/v1';

final class OpenCodeAuthOptions {
  OpenCodeAuthOptions({
    required String apiKey,
    required this.client,
    required String userAgent,
    this.maxRequestBytes = openCodeAbsoluteMaxRequestBytes,
    this.maxResponseBytes = 8 * 1024 * 1024,
  }) : _apiKey = _validateApiKey(apiKey),
       userAgent = _validateUserAgent(userAgent),
       _serviceRoot = _validateRoot(_subscriptionGoRoot),
       endpointBinding = OpenCodeEndpointBinding.subscriptionGo {
    _validateLimits(maxRequestBytes, maxResponseBytes);
  }

  OpenCodeAuthOptions.custom({
    required String apiKey,
    required this.client,
    required String userAgent,
    required String serviceRoot,
    this.maxRequestBytes = openCodeAbsoluteMaxRequestBytes,
    this.maxResponseBytes = 8 * 1024 * 1024,
  }) : _apiKey = _validateApiKey(apiKey),
       userAgent = _validateUserAgent(userAgent),
       _serviceRoot = _validateRoot(serviceRoot),
       endpointBinding = OpenCodeEndpointBinding.custom {
    _validateLimits(maxRequestBytes, maxResponseBytes);
  }

  final String _apiKey;
  final IOClient client;
  final String userAgent;
  final Uri _serviceRoot;
  final OpenCodeEndpointBinding endpointBinding;
  final int maxRequestBytes;
  final int maxResponseBytes;

  @override
  String toString() =>
      'OpenCodeAuthOptions(endpointBinding: $endpointBinding, '
      'maxRequestBytes: $maxRequestBytes, maxResponseBytes: '
      '$maxResponseBytes)';
}

void _validateLimits(int maxRequestBytes, int maxResponseBytes) {
  if (maxRequestBytes <= 0 ||
      maxRequestBytes > openCodeAbsoluteMaxRequestBytes) {
    throw const OpenCodeConfigurationException('max_request_bytes');
  }
  if (maxResponseBytes <= 0 ||
      maxResponseBytes > openCodeAbsoluteMaxResponseBytes) {
    throw const OpenCodeConfigurationException('max_response_bytes');
  }
}

String _validateApiKey(String value) {
  if (value.isEmpty || value.trim() != value || _hasAsciiControl(value)) {
    throw const OpenCodeConfigurationException('api_key');
  }
  return value;
}

String _validateUserAgent(String value) {
  if (value.isEmpty ||
      value.length > 256 ||
      value.trim().isEmpty ||
      !_isVisibleAscii(value, allowSpace: true)) {
    throw const OpenCodeConfigurationException('user_agent');
  }
  return value;
}

Uri _validateRoot(String encoded) {
  final lower = encoded.toLowerCase();
  Uri value;
  try {
    value = Uri.parse(encoded);
  } on FormatException {
    throw const OpenCodeConfigurationException('service_root');
  }
  if (!value.isAbsolute ||
      encoded.trim() != encoded ||
      _hasAsciiControl(encoded) ||
      value.scheme.toLowerCase() != 'https' ||
      value.host.isEmpty ||
      value.userInfo.isNotEmpty ||
      value.hasQuery ||
      value.hasFragment ||
      lower.contains('%2f') ||
      lower.contains('%5c') ||
      lower.contains('%2e') ||
      RegExp(r'(^|/)\.\.?(?:/|$)').hasMatch(value.path) ||
      value.pathSegments.any((segment) {
        final decoded = Uri.decodeComponent(segment).toLowerCase();
        return decoded == '.' ||
            decoded == '..' ||
            decoded.contains('/') ||
            decoded.contains('\\');
      }) ||
      value.path.contains('\\') ||
      value.path.contains('//') ||
      value.path.endsWith('//')) {
    throw const OpenCodeConfigurationException('service_root');
  }
  final path = value.path == '/'
      ? ''
      : value.path.endsWith('/')
      ? value.path.substring(0, value.path.length - 1)
      : value.path;
  return value.replace(
    scheme: value.scheme.toLowerCase(),
    host: value.host.toLowerCase(),
    path: path,
  );
}

bool _hasAsciiControl(String value) =>
    value.codeUnits.any((unit) => unit < 0x20 || unit == 0x7f);

bool _isVisibleAscii(String value, {required bool allowSpace}) => value
    .codeUnits
    .every((unit) => unit >= (allowSpace ? 0x20 : 0x21) && unit <= 0x7e);
