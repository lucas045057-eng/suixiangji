import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:wealthmate_flutter/data/api_client.dart';
import 'package:wealthmate_flutter/data/token_store.dart';

class MemoryTokenStore implements TokenStore {
  String? value;
  var clearCount = 0;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String token) async => value = token;

  @override
  Future<void> clear() async {
    value = null;
    clearCount++;
  }
}

class ResponseClient extends http.BaseClient {
  ResponseClient(this.statusCode, this.body);

  final int statusCode;
  final String body;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final stream = Stream<List<int>>.fromIterable([utf8.encode(body)]);
    return http.StreamedResponse(stream, statusCode,
        headers: const {'content-type': 'application/json'});
  }
}

void main() {
  test('login persists a token and a new client restores it', () async {
    final tokenStore = MemoryTokenStore();
    final api = ApiClient(
      baseUrl: 'http://example.test',
      tokenStore: tokenStore,
      client: ResponseClient(200, jsonEncode({'access_token': 'jwt-1'})),
    );

    await api.login('demo', 'password');
    expect(api.token, 'jwt-1');
    expect(tokenStore.value, 'jwt-1');

    final restarted =
        ApiClient(baseUrl: 'http://example.test', tokenStore: tokenStore);
    final restored = await restarted.restoreToken();

    expect(restored, isTrue);
    expect(restarted.token, 'jwt-1');
  });

  test('an authenticated 401 clears the token and notifies the app', () async {
    final tokenStore = MemoryTokenStore()..value = 'stale-jwt';
    var expired = false;
    final api = ApiClient(
      baseUrl: 'http://example.test',
      token: 'stale-jwt',
      tokenStore: tokenStore,
      client: ResponseClient(401, '{"detail":"登录已失效"}'),
      onAuthExpired: () async => expired = true,
    );

    await expectLater(api.fetchProfile(), throwsA(isA<ApiFailure>()));

    expect(api.token, isNull);
    expect(tokenStore.value, isNull);
    expect(tokenStore.clearCount, 1);
    expect(expired, isTrue);
  });

  test('logout clears only the stored authentication token', () async {
    final tokenStore = MemoryTokenStore()..value = 'jwt-2';
    final api = ApiClient(
      baseUrl: 'http://example.test',
      token: 'jwt-2',
      tokenStore: tokenStore,
    );

    await api.logout();

    expect(api.token, isNull);
    expect(tokenStore.value, isNull);
    expect(tokenStore.clearCount, 1);
  });
}
