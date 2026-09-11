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
  const ApiFailure(this.kind, this.message);

  final ApiFailureKind kind;
  final String message;

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
        final failure = _failureForStatus(response.statusCode, path);
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

  ApiFailure _failureForStatus(int statusCode, String path) {
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
}
