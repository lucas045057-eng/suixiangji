import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

enum ApiFailureKind {
  cancelled,
  configuration,
  unauthorized,
  conflict,
  validation,
  network,
  server
}

class ApiFailure implements Exception {
  const ApiFailure(
    this.kind,
    this.message, {
    this.statusCode,
    this.code,
    this.detail,
    this.retryAfter,
  });

  final ApiFailureKind kind;
  final String message;

  /// HTTP status when the failure came from a response (never a detail leak).
  final int? statusCode;

  /// Machine code from the `{"detail": ..., "code": ...}` error contract.
  final String? code;

  /// Sanitized, display-safe `detail` text. Only ever shown as plain text.
  final String? detail;

  /// Parsed `Retry-After` header, when the server sent a usable value.
  final Duration? retryAfter;

  @override
  String toString() => message;
}

typedef TokenProvider = String? Function();

/// Shared JSON transport for feature remote data sources.
class ApiTransport {
  ApiTransport({
    required this.baseUrl,
    required this.client,
    required this.tokenProvider,
    this.onAuthExpired,
  });

  final String? baseUrl;
  final http.Client client;
  final TokenProvider tokenProvider;
  final FutureOr<void> Function()? onAuthExpired;

  Future<Map<String, Object?>> requestMap(
    String method,
    String path, {
    Map<String, Object?>? body,
    bool includeAuth = true,
  }) async {
    final root = baseUrl?.trim();
    if (root == null || root.isEmpty) {
      throw const ApiFailure(ApiFailureKind.configuration, '同步服务尚未配置');
    }
    final uri = Uri.parse(root.endsWith('/')
        ? '${root.substring(0, root.length - 1)}$path'
        : '$root$path');
    final headers = <String, String>{'content-type': 'application/json'};
    final token = tokenProvider();
    if (includeAuth && token != null && token.isNotEmpty) {
      headers['authorization'] = 'Bearer $token';
    }
    try {
      final response = switch (method) {
        'POST' => await client.post(
            uri,
            headers: headers,
            body: jsonEncode(body ?? const {}),
          ),
        'PATCH' => await client.patch(
            uri,
            headers: headers,
            body: jsonEncode(body ?? const {}),
          ),
        'DELETE' => await client.delete(
            uri,
            headers: headers,
            body: body == null ? null : jsonEncode(body),
          ),
        _ => await client.get(uri, headers: headers),
      };
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final failure = _failureForStatus(
          response.statusCode,
          path,
          error: _errorBody(response.body),
          retryAfter: _retryAfter(response.headers),
        );
        if (response.statusCode == 401 &&
            includeAuth &&
            token != null &&
            token.isNotEmpty &&
            tokenProvider() == token) {
          await onAuthExpired?.call();
        }
        throw failure;
      }
      final decoded = jsonDecode(response.body);
      return (decoded as Map).cast<String, Object?>();
    } on ApiFailure {
      rethrow;
    } on FormatException {
      throw const ApiFailure(ApiFailureKind.server, '同步服务返回了无法识别的数据');
    } catch (_) {
      throw const ApiFailure(ApiFailureKind.network, '暂时无法连接同步服务');
    }
  }

  ApiFailure _failureForStatus(
    int statusCode,
    String path, {
    ({String? code, String? detail})? error,
    Duration? retryAfter,
  }) {
    final base = _baseFailureForStatus(statusCode, path);
    return ApiFailure(
      base.kind,
      base.message,
      statusCode: statusCode,
      code: error?.code,
      detail: error?.detail,
      retryAfter: retryAfter,
    );
  }

  /// Same mapping as [requestMap], for transports that read the body as a
  /// stream (SSE). Keeps one source of truth for the error contract.
  static ApiFailure failureForResponse(
    int statusCode,
    String path, {
    String? body,
    Map<String, String> headers = const <String, String>{},
  }) {
    final error = body == null ? null : _errorBody(body);
    final base = _baseFailureForStatus(statusCode, path);
    return ApiFailure(
      base.kind,
      base.message,
      statusCode: statusCode,
      code: error?.code,
      detail: error?.detail,
      retryAfter: _retryAfter(headers),
    );
  }

  static ApiFailure _baseFailureForStatus(int statusCode, String path) {
    if (statusCode == 400 && path == '/auth/register') {
      return const ApiFailure(
          ApiFailureKind.validation, '邀请码无效、已过期或已用完，请联系邀请人');
    }
    if (statusCode == 403) {
      return ApiFailure(
        ApiFailureKind.validation,
        path == '/auth/me' || path == '/auth/password'
            ? '当前密码不正确，请重试'
            : '当前账号无权执行此操作',
      );
    }
    if (statusCode == 429) {
      return const ApiFailure(ApiFailureKind.validation, '操作太频繁，请稍后再试');
    }
    if (statusCode == 409 && (path == '/auth/register' || path == '/auth/me')) {
      return const ApiFailure(ApiFailureKind.conflict, '用户名已被使用，请换一个');
    }
    if (statusCode == 401 && path == '/auth/login') {
      return const ApiFailure(ApiFailureKind.unauthorized, '用户名或密码不正确');
    }
    if (statusCode == 401) {
      return const ApiFailure(ApiFailureKind.unauthorized, '登录已失效，请重新登录');
    }
    if (statusCode == 409) {
      return const ApiFailure(ApiFailureKind.conflict, '数据存在冲突，请在本机确认');
    }
    if (statusCode == 422) {
      return const ApiFailure(ApiFailureKind.validation, '提交的数据需要修正');
    }
    return const ApiFailure(ApiFailureKind.server, '同步服务暂时不可用');
  }

  /// Reads the machine code and display detail from a `{"detail","code"}` body.
  /// Anything unparseable is ignored: no raw body text ever reaches the UI.
  static ({String? code, String? detail}) _errorBody(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is! Map) return (code: null, detail: null);
      final code = decoded['code'];
      final detail = decoded['detail'];
      return (
        code: _safeCode(code),
        detail: detail is String ? _safeDetail(detail) : null,
      );
    } on FormatException {
      return (code: null, detail: null);
    }
  }

  static String? _safeCode(Object? value) {
    if (value is! String) return null;
    final code = value.trim();
    if (code.isEmpty || code.length > 64) return null;
    return RegExp(r'^[a-z][a-z0-9_]*$').hasMatch(code) ? code : null;
  }

  static String? _safeDetail(String value) {
    final collapsed = value
        .replaceAll(RegExp(r'[\u0000-\u001f\u007f]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (collapsed.isEmpty) return null;
    return collapsed.length <= 120 ? collapsed : '${collapsed.substring(0, 120)}…';
  }

  static Duration? _retryAfter(Map<String, String> headers) {
    final raw = headers['retry-after']?.trim();
    if (raw == null || raw.isEmpty) return null;
    final seconds = int.tryParse(raw);
    if (seconds == null || seconds < 0 || seconds > 86400) return null;
    return Duration(seconds: seconds);
  }
}
