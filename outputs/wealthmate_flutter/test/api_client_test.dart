import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:wealthmate_flutter/core/network/http_client_factory.dart';
import 'package:wealthmate_flutter/data/api_client.dart';
import 'package:wealthmate_flutter/data/token_store.dart';

class MemoryTokenStore implements TokenStore {
  String? value;
  String? lastVerifiedUserId;
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

  @override
  Future<String?> readLastVerifiedUserId() async => lastVerifiedUserId;

  @override
  Future<void> writeLastVerifiedUserId(String userId) async =>
      lastVerifiedUserId = userId;

  @override
  Future<void> clearLastVerifiedUserId() async => lastVerifiedUserId = null;
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

class CloseTrackingClient extends ResponseClient {
  CloseTrackingClient() : super(200, '{}');

  var closeCalls = 0;

  @override
  void close() {
    closeCalls++;
    super.close();
  }
}

void main() {
  test('ApiClient closes an internally created client exactly once', () {
    final client = CloseTrackingClient();
    final factory = PlatformHttpClientFactory(
      transportKind: HttpTransportKind.packageHttp,
      clientBuilder: () => client,
    );
    final api = ApiClient(
      baseUrl: 'http://example.test',
      clientFactory: factory,
    );

    api.close();
    api.close();

    expect(api.client, same(client));
    expect(client.closeCalls, 1);
  });

  test('ApiClient does not close an externally injected client', () {
    final client = CloseTrackingClient();
    final api = ApiClient(
      baseUrl: 'http://example.test',
      client: client,
    );

    api.close();

    expect(client.closeCalls, 0);
  });

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
    final tokenStore = MemoryTokenStore()
      ..value = 'stale-jwt'
      ..lastVerifiedUserId = 'user-a';
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
    expect(tokenStore.lastVerifiedUserId, isNull);
    expect(tokenStore.clearCount, 1);
    expect(expired, isTrue);
  });

  test('logout clears the access token and verified user identity', () async {
    final tokenStore = MemoryTokenStore()
      ..value = 'jwt-2'
      ..lastVerifiedUserId = 'user-a';
    final api = ApiClient(
      baseUrl: 'http://example.test',
      token: 'jwt-2',
      tokenStore: tokenStore,
    );

    await api.logout();

    expect(api.token, isNull);
    expect(tokenStore.value, isNull);
    expect(tokenStore.lastVerifiedUserId, isNull);
    expect(tokenStore.clearCount, 1);
  });
}
