import 'dart:convert';
import 'dart:io' show HttpDate;

/// Base type for all failures intentionally exposed by this package.
sealed class OpenCodeAuthException implements Exception {
  const OpenCodeAuthException(this.code);

  final String code;

  @override
  String toString() => 'OpenCodeAuthException($code)';
}

final class OpenCodeConfigurationException extends OpenCodeAuthException {
  const OpenCodeConfigurationException(super.code);

  @override
  String toString() => 'OpenCodeConfigurationException($code)';
}

final class UnsupportedProtocolException extends OpenCodeAuthException {
  const UnsupportedProtocolException() : super('unsupported_protocol');

  @override
  String toString() => 'UnsupportedProtocolException(unsupported_protocol)';
}

final class OpenCodeAuthenticationException extends OpenCodeAuthException {
  const OpenCodeAuthenticationException() : super('authentication');

  @override
  String toString() => 'OpenCodeAuthenticationException(authentication)';
}

final class OpenCodeQuotaException extends OpenCodeAuthException {
  const OpenCodeQuotaException() : super('quota');

  @override
  String toString() => 'OpenCodeQuotaException(quota)';
}

final class OpenCodeRateLimitException extends OpenCodeAuthException {
  const OpenCodeRateLimitException({this.retryAfter}) : super('rate_limit');

  final Duration? retryAfter;

  @override
  String toString() => 'OpenCodeRateLimitException(rate_limit)';
}

final class OpenCodeModelException extends OpenCodeAuthException {
  const OpenCodeModelException() : super('model');

  @override
  String toString() => 'OpenCodeModelException(model)';
}

final class OpenCodePolicyException extends OpenCodeAuthException {
  const OpenCodePolicyException() : super('policy');

  @override
  String toString() => 'OpenCodePolicyException(policy)';
}

final class OpenCodeRedirectException extends OpenCodeAuthException {
  const OpenCodeRedirectException(this.statusCode) : super('redirect');

  final int statusCode;

  @override
  String toString() => 'OpenCodeRedirectException(redirect)';
}

final class OpenCodeNetworkException extends OpenCodeAuthException {
  const OpenCodeNetworkException() : super('network');

  @override
  String toString() => 'OpenCodeNetworkException(network)';
}

final class OpenCodeCancelledException extends OpenCodeAuthException {
  const OpenCodeCancelledException() : super('cancelled');

  @override
  String toString() => 'OpenCodeCancelledException(cancelled)';
}

final class OpenCodeRequestLimitException extends OpenCodeAuthException {
  const OpenCodeRequestLimitException() : super('request_limit');

  @override
  String toString() => 'OpenCodeRequestLimitException(request_limit)';
}

final class OpenCodeResponseLimitException extends OpenCodeAuthException {
  const OpenCodeResponseLimitException() : super('response_limit');

  @override
  String toString() => 'OpenCodeResponseLimitException(response_limit)';
}

final class OpenCodeProtocolException extends OpenCodeAuthException {
  const OpenCodeProtocolException() : super('protocol');

  @override
  String toString() => 'OpenCodeProtocolException(protocol)';
}

final class OpenCodeHttpException extends OpenCodeAuthException {
  const OpenCodeHttpException(this.statusCode) : super('http_unknown');

  final int statusCode;

  @override
  String toString() => 'OpenCodeHttpException(http_unknown)';
}

final class OpenCodeClosedException extends OpenCodeAuthException {
  const OpenCodeClosedException() : super('closed');

  @override
  String toString() => 'OpenCodeClosedException(closed)';
}

OpenCodeAuthException classifyOpenCodeHttpFailure(
  int statusCode,
  List<int> body,
  String? retryAfter,
  DateTime Function() clock,
) {
  final values = <String>[];
  try {
    final decoded = jsonDecode(utf8.decode(body));
    if (decoded is! Map<String, Object?> ||
        decoded['error'] is! Map<String, Object?>) {
      return OpenCodeHttpException(statusCode);
    }
    final error = decoded['error']! as Map<String, Object?>;
    for (final field in <String>['type', 'code']) {
      if (!error.containsKey(field)) continue;
      final value = error[field];
      if (value is! String || value.isEmpty || value.length > 128) {
        return OpenCodeHttpException(statusCode);
      }
      values.add(value);
    }
  } catch (_) {
    return OpenCodeHttpException(statusCode);
  }
  if (values.isEmpty) return OpenCodeHttpException(statusCode);
  final categories = values.map(_errorCategory).toSet();
  if (categories.contains(null) || categories.length != 1) {
    return OpenCodeHttpException(statusCode);
  }
  return switch (categories.single) {
    'auth' => const OpenCodeAuthenticationException(),
    'quota' => const OpenCodeQuotaException(),
    'rate' => OpenCodeRateLimitException(
      retryAfter: _parseRetryAfter(retryAfter, clock),
    ),
    'model' => const OpenCodeModelException(),
    'policy' => const OpenCodePolicyException(),
    _ => OpenCodeHttpException(statusCode),
  };
}

String? _errorCategory(String value) => switch (value) {
  'AuthError' || 'authentication_error' || 'invalid_api_key' => 'auth',
  'CreditsError' ||
  'MonthlyLimitError' ||
  'UserLimitError' ||
  'GoUsageLimitError' ||
  'FreeUsageLimitError' ||
  'BlackUsageLimitError' ||
  'insufficient_quota' => 'quota',
  'RateLimitError' || 'rate_limit_error' => 'rate',
  'ModelError' => 'model',
  'RegionError' || 'DataPolicyError' => 'policy',
  _ => null,
};

Duration? _parseRetryAfter(String? value, DateTime Function() clock) {
  if (value == null || value.isEmpty || value.length > 128) return null;
  final seconds = int.tryParse(value);
  if (seconds != null) {
    return seconds < 0 || seconds > 86400 ? null : Duration(seconds: seconds);
  }
  try {
    final delta = HttpDate.parse(value).toUtc().difference(clock().toUtc());
    if (delta.isNegative || delta > const Duration(days: 1)) return null;
    return Duration(seconds: delta.inSeconds);
  } catch (_) {
    return null;
  }
}
