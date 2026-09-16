import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:wealthmate_flutter/data/api_client.dart';
import 'package:wealthmate_flutter/data/finance_repository.dart';
import 'package:wealthmate_flutter/data/local_repository.dart';
import 'package:wealthmate_flutter/data/sync_queue.dart';
import 'package:wealthmate_flutter/data/token_store.dart';
import 'package:wealthmate_flutter/domain/models.dart';
import 'package:wealthmate_flutter/main.dart';
import 'package:wealthmate_flutter/state/finance_store.dart';
import 'package:wealthmate_flutter/ui/app_shell.dart';

class _MemoryKeyValueStore implements KeyValueStore {
  final Map<String, String> values = {};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;
}

class _MemoryTokenStore implements TokenStore {
  String? value;
  String? lastVerifiedUserId;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String token) async => value = token;

  @override
  Future<void> clear() async => value = null;

  @override
  Future<String?> readLastVerifiedUserId() async => lastVerifiedUserId;

  @override
  Future<void> writeLastVerifiedUserId(String userId) async =>
      lastVerifiedUserId = userId;

  @override
  Future<void> clearLastVerifiedUserId() async => lastVerifiedUserId = null;
}

class _UnauthorizedClient extends http.BaseClient {
  final List<String> paths = [];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    paths.add(request.url.path);
    return http.StreamedResponse(
      Stream<List<int>>.value(utf8.encode('{"detail":"登录已失效"}')),
      401,
      request: request,
      headers: const {'content-type': 'application/json'},
    );
  }
}

class _AuthenticatedClient extends http.BaseClient {
  final List<String> paths = [];
  final List<int> pullCursors = [];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    paths.add(request.url.path);
    if (request.url.path == '/auth/me') {
      return _jsonResponse(
        200,
        {
          'id': 'user-b',
          'username': 'user-b',
          'display_name': 'User B',
          'quick_memories': const <Object?>[],
        },
        request,
      );
    }
    if (request.url.path == '/sync/pull') {
      pullCursors.add(int.parse(request.url.queryParameters['since_version']!));
      return _jsonResponse(
        200,
        {
          'items': const <Object?>[],
          'accounts': const <Object?>[],
          'categories': const <Object?>[],
          'budgets': const <Object?>[],
          'server_version': 7,
        },
        request,
      );
    }
    return _jsonResponse(404, {'detail': 'unexpected path'}, request);
  }
}

http.StreamedResponse _jsonResponse(
    int status, Map<String, Object?> body, http.BaseRequest request) {
  return http.StreamedResponse(
    Stream<List<int>>.value(utf8.encode(jsonEncode(body))),
    status,
    request: request,
    headers: const {'content-type': 'application/json'},
  );
}

class _CountingFinanceStore extends FinanceStore {
  _CountingFinanceStore({
    required super.repository,
    super.initialState,
  });

  int syncCalls = 0;

  @override
  Future<void> sync() async {
    syncCalls++;
    await super.sync();
  }
}

FinanceState _stateAtVersionSeven() => const FinanceState(
      accounts: [
        Account(
          id: 'user-b-account',
          name: 'User B account',
          type: AccountType.asset,
        ),
      ],
      syncState: SyncState(serverVersion: 7),
    );

FinanceRepository _repository(ApiClient api) => FinanceRepository(
      local: LocalRepository(_MemoryKeyValueStore()),
      queue: SyncQueue(),
      api: api,
    );

ApiClient _unauthorizedApi(_UnauthorizedClient client) => ApiClient(
      baseUrl: 'http://dc01-auth-control-flow.test',
      token: 'stale-token',
      tokenStore: _MemoryTokenStore()..value = 'stale-token',
      client: client,
    );

ApiClient _authenticatedApi(_AuthenticatedClient client) => ApiClient(
      baseUrl: 'http://dc01-auth-control-flow.test',
      token: 'valid-token',
      tokenStore: _MemoryTokenStore()..value = 'valid-token',
      client: client,
    );

void main() {
  testWidgets(
      'RED: auth/me 401 must not continue from AppShell into business sync',
      (tester) async {
    final client = _UnauthorizedClient();
    final api = _unauthorizedApi(client);
    final repository = _repository(api);
    await repository.ensureLocalOwner('user-b');
    final store = _CountingFinanceStore(
      repository: repository,
      initialState: _stateAtVersionSeven(),
    );
    api.onAuthExpired = store.clearAuthenticatedSession;

    await tester.pumpWidget(MaterialApp(home: AppShell(store: store)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(client.paths, ['/auth/me']);
    expect(store.syncCalls, 0);
  });

  test('RED: auth/me 401 must preserve the in-memory server cursor', () async {
    final client = _UnauthorizedClient();
    final api = _unauthorizedApi(client);
    final repository = _repository(api);
    await repository.ensureLocalOwner('user-b');
    final store = FinanceStore(
      repository: repository,
      initialState: _stateAtVersionSeven(),
    );
    api.onAuthExpired = store.clearAuthenticatedSession;

    await store.loadProfile();

    expect(store.state.syncState.serverVersion, 7);
    expect(client.paths, ['/auth/me']);
  });

  test('RED: auth/me 401 must preserve local owner state and pending queue',
      () async {
    final client = _UnauthorizedClient();
    final tokenStore = _MemoryTokenStore()
      ..value = 'stale-token'
      ..lastVerifiedUserId = 'user-b';
    final api = ApiClient(
      baseUrl: 'http://dc01-auth-control-flow.test',
      token: 'stale-token',
      tokenStore: tokenStore,
      client: client,
    );
    final repository = _repository(api);
    await repository.ensureLocalOwner('user-b');
    repository.queue.enqueue(const SyncOperation(
      clientOpId: 'dc01-pending-op',
      entity: 'transactions',
      entityId: 'dc01-pending-tx',
      type: SyncOperationType.upsert,
      payload: {'id': 'dc01-pending-tx'},
    ));
    final store = FinanceStore(
      repository: repository,
      initialState: const FinanceState(
        transactions: [
          FinanceTransaction(
            id: 'dc01-pending-tx',
            date: '2026-09-06',
            type: TransactionType.expense,
            amount: 7,
            note: 'DC01 pending',
          ),
        ],
        syncState: SyncState(serverVersion: 7),
      ),
    );
    api.onAuthExpired = store.clearAuthenticatedSession;

    await store.loadProfile();

    expect(api.token, isNull);
    expect(api.lastVerifiedUserId, isNull);
    expect(tokenStore.value, isNull);
    expect(tokenStore.lastVerifiedUserId, isNull);
    expect(repository.localOwnerUserId, 'user-b');
    expect(store.state.transactions.map((item) => item.id),
        contains('dc01-pending-tx'));
    expect(store.state.syncState.serverVersion, 7);
    expect(repository.queue.pending().single.clientOpId, 'dc01-pending-op');
    expect(client.paths, ['/auth/me']);
  });

  testWidgets('authenticated profile load continues into sync exactly once',
      (tester) async {
    final client = _AuthenticatedClient();
    final api = _authenticatedApi(client);
    final repository = _repository(api);
    await repository.ensureLocalOwner('user-b');
    final store = _CountingFinanceStore(
      repository: repository,
      initialState: _stateAtVersionSeven(),
    );

    await tester.pumpWidget(MaterialApp(home: AppShell(store: store)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(store.syncCalls, 1);
    expect(client.paths, ['/auth/me', '/sync/pull']);
  });

  testWidgets(
      'persisted session restores its owner cursor through the auth gate',
      (tester) async {
    final localStore = _MemoryKeyValueStore();
    final persisted = FinanceRepository(
      local: LocalRepository(localStore),
      queue: SyncQueue(),
    );
    await persisted.ensureLocalOwner('user-b');
    await persisted.save(_stateAtVersionSeven());

    final tokenStore = _MemoryTokenStore()
      ..value = 'restored-token'
      ..lastVerifiedUserId = 'user-b';
    final client = _AuthenticatedClient();
    final api = ApiClient(
      baseUrl: 'http://dc01-auth-control-flow.test',
      tokenStore: tokenStore,
      client: client,
    );
    expect(await api.restoreToken(), isTrue);
    final repository = FinanceRepository(
      local: LocalRepository(localStore),
      queue: SyncQueue(),
      api: api,
    );
    final store = FinanceStore(repository: repository);

    await tester.pumpWidget(WealthMateApp(
      store: store,
      api: api,
      auth: store.authStore,
    ));
    await tester.pumpAndSettle();

    expect(repository.localOwnerUserId, 'user-b');
    expect(store.state.syncState.serverVersion, 7);
    expect(client.paths, ['/auth/me', '/sync/pull']);
    expect(client.pullCursors, [7]);
  });
}
