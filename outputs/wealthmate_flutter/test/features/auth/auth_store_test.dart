import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:wealthmate_flutter/data/api_client.dart';
import 'package:wealthmate_flutter/data/token_store.dart';
import 'package:wealthmate_flutter/features/auth/data/auth_repository.dart';
import 'package:wealthmate_flutter/features/auth/data/auth_remote_data_source.dart';
import 'package:wealthmate_flutter/features/auth/state/auth_store.dart';

class _AuthMemoryTokenStore implements TokenStore {
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
  Future<void> writeLastVerifiedUserId(String userId) async {
    lastVerifiedUserId = userId;
  }

  @override
  Future<void> clearLastVerifiedUserId() async {
    lastVerifiedUserId = null;
  }
}

class _AuthResponseClient extends http.BaseClient {
  _AuthResponseClient(this.responses);

  final List<_AuthResponse> responses;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final response = responses.removeAt(0);
    return http.StreamedResponse(
      Stream<List<int>>.value(utf8.encode(jsonEncode(response.body))),
      response.statusCode,
      request: request,
      headers: const {'content-type': 'application/json'},
    );
  }
}

class _DeferredAuthResponseClient extends http.BaseClient {
  final List<Completer<_AuthResponse>> pending = [];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final completer = Completer<_AuthResponse>();
    pending.add(completer);
    final response = await completer.future;
    return http.StreamedResponse(
      Stream<List<int>>.value(utf8.encode(jsonEncode(response.body))),
      response.statusCode,
      request: request,
      headers: const {'content-type': 'application/json'},
    );
  }

  Future<void> waitForRequests(int count) async {
    while (pending.length < count) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  void respondAt(int index, _AuthResponse response) {
    pending.removeAt(index).complete(response);
  }
}

class _AuthResponse {
  const _AuthResponse(this.statusCode, this.body);

  final int statusCode;
  final Map<String, Object?> body;
}

AuthStore _authStore({
  required _AuthMemoryTokenStore tokenStore,
  required List<_AuthResponse> responses,
  String? token,
}) {
  final api = ApiClient(
    baseUrl: 'http://auth.test',
    token: token,
    tokenStore: tokenStore,
    client: _AuthResponseClient(responses),
  );
  return AuthStore(
    repository: AuthRepository(
      remote: AuthRemoteDataSource(api: api),
    ),
  );
}

Map<String, Object?> _profile({String accessToken = 'jwt-profile'}) => {
      'id': 'user-1',
      'username': 'demo',
      'display_name': 'Demo User',
      'access_token': accessToken,
      'quick_memories': const <Object?>[],
    };

void main() {
  test('login persists the token and exposes the verified profile', () async {
    final tokenStore = _AuthMemoryTokenStore();
    final auth = _authStore(
      tokenStore: tokenStore,
      responses: [
        const _AuthResponse(200, {'access_token': 'jwt-login'}),
        _AuthResponse(200, _profile()),
      ],
    );

    expect(await auth.login('demo', 'password'), isTrue);
    expect(auth.isAuthenticated, isTrue);
    expect(auth.profile?.id, 'user-1');
    expect(tokenStore.value, 'jwt-login');
  });

  test('profile update replaces the auth session and rotates a token',
      () async {
    final tokenStore = _AuthMemoryTokenStore()..value = 'jwt-old';
    final auth = _authStore(
      tokenStore: tokenStore,
      token: 'jwt-old',
      responses: [_AuthResponse(200, _profile(accessToken: 'jwt-new'))],
    );

    expect(await auth.updateProfile(displayName: 'New Name'), isTrue);
    expect(auth.profile?.displayName, 'Demo User');
    expect(tokenStore.value, 'jwt-new');
  });

  test('password change delegates to auth repository and rotates a token',
      () async {
    final tokenStore = _AuthMemoryTokenStore()..value = 'jwt-old';
    final auth = _authStore(
      tokenStore: tokenStore,
      token: 'jwt-old',
      responses: [_AuthResponse(200, _profile(accessToken: 'jwt-password'))],
    );

    expect(await auth.changePassword('old-password', 'new-password'), isTrue);
    expect(tokenStore.value, 'jwt-password');
  });

  test('logout clears the persisted token and in-memory profile', () async {
    final tokenStore = _AuthMemoryTokenStore()..value = 'jwt-old';
    final auth = _authStore(
      tokenStore: tokenStore,
      token: 'jwt-old',
      responses: const [],
    );

    await auth.logout();

    expect(auth.isAuthenticated, isFalse);
    expect(auth.profile, isNull);
    expect(tokenStore.value, isNull);
    expect(tokenStore.clearCount, 1);
  });

  test('unauthorized profile load clears the auth session', () async {
    final tokenStore = _AuthMemoryTokenStore()..value = 'jwt-stale';
    final auth = _authStore(
      tokenStore: tokenStore,
      token: 'jwt-stale',
      responses: [
        const _AuthResponse(401, {'detail': '登录已失效'})
      ],
    );

    expect(await auth.loadProfile(), isFalse);
    expect(auth.isAuthenticated, isFalse);
    expect(auth.profile, isNull);
    expect(tokenStore.value, isNull);
  });

  test('stale A auth response cannot overwrite B session or rotated token',
      () async {
    final tokenStore = _AuthMemoryTokenStore()..value = 'jwt-a-old';
    final client = _DeferredAuthResponseClient();
    final api = ApiClient(
      baseUrl: 'http://auth.test',
      token: 'jwt-a-old',
      tokenStore: tokenStore,
      client: client,
    );
    final auth = AuthStore(
      repository: AuthRepository(
        remote: AuthRemoteDataSource(api: api),
      ),
    );

    final staleA = auth.updateProfile(displayName: 'A');
    await client.waitForRequests(1);

    await auth.logout();
    final loginB = auth.login('user-b', 'password');
    await client.waitForRequests(2);
    client.respondAt(1, const _AuthResponse(200, {
      'access_token': 'jwt-b',
    }));
    await client.waitForRequests(2);
    client.respondAt(1, _AuthResponse(200, _profile(accessToken: 'jwt-b')));

    expect(await loginB, isTrue);
    expect(auth.profile?.id, 'user-1');
    expect(api.token, 'jwt-b');
    expect(tokenStore.value, 'jwt-b');

    client.respondAt(0, _AuthResponse(200, _profile(accessToken: 'jwt-a-new')));

    expect(await staleA, isFalse);
    expect(auth.profile?.id, 'user-1');
    expect(api.token, 'jwt-b');
    expect(tokenStore.value, 'jwt-b');
  });
}
