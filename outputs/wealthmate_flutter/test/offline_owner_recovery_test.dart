import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:wealthmate_flutter/data/api_client.dart';
import 'package:wealthmate_flutter/data/finance_repository.dart';
import 'package:wealthmate_flutter/data/local_repository.dart';
import 'package:wealthmate_flutter/data/sync_queue.dart';
import 'package:wealthmate_flutter/data/token_store.dart';
import 'package:wealthmate_flutter/domain/models.dart';
import 'package:wealthmate_flutter/state/finance_store.dart';

const userAId = 'offline-owner-user-a';
const userBId = 'offline-owner-user-b';

class MemoryKeyValueStore implements KeyValueStore {
  final Map<String, String> values = {};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;
}

class MemoryTokenStore implements TokenStore {
  String? token;
  String? lastVerifiedUserId;

  @override
  Future<String?> read() async => token;

  @override
  Future<void> write(String value) async => token = value;

  @override
  Future<void> clear() async => token = null;

  @override
  Future<String?> readLastVerifiedUserId() async => lastVerifiedUserId;

  @override
  Future<void> writeLastVerifiedUserId(String userId) async =>
      lastVerifiedUserId = userId;

  @override
  Future<void> clearLastVerifiedUserId() async => lastVerifiedUserId = null;
}

class ToggleNetworkClient extends http.BaseClient {
  ToggleNetworkClient({this.online = true});

  bool online;
  int profileRequestCount = 0;
  int pushRequestCount = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (!online) throw const SocketException('offline');
    if (request.url.path == '/auth/me') {
      profileRequestCount++;
      return _jsonResponse(
        200,
        {
          'id': userAId,
          'username': 'offline-owner-user-a',
          'display_name': 'User A',
          'quick_memories': const <Object?>[],
        },
        request,
      );
    }
    if (request.url.path == '/sync/push') {
      pushRequestCount++;
      return _jsonResponse(
        200,
        {
          'accepted': const <Object?>[],
          'conflicts': const <Object?>[],
          'server_version': 50,
        },
        request,
      );
    }
    return _jsonResponse(404, {'detail': 'unexpected path'}, request);
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
}

class UnauthorizedClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    return http.StreamedResponse(
      Stream<List<int>>.value(utf8.encode('{"detail":"登录已失效"}')),
      401,
      request: request,
      headers: const {'content-type': 'application/json'},
    );
  }
}

FinanceState ownerAState() => const FinanceState(
      accounts: [
        Account(
          id: 'offline-owner-a-account',
          name: 'User A Account',
          type: AccountType.asset,
        ),
      ],
      categories: [
        Category(id: 'offline-owner-a-category', name: 'User A Category'),
      ],
      transactions: [
        FinanceTransaction(
          id: 'offline-owner-a-transaction',
          date: '2026-09-05',
          type: TransactionType.expense,
          amount: 12.34,
          accountId: 'offline-owner-a-account',
          categoryId: 'offline-owner-a-category',
        ),
      ],
      syncState: SyncState(serverVersion: 50),
    );

const pendingOperation = SyncOperation(
  clientOpId: 'offline-pending-A',
  entity: 'transactions',
  entityId: 'offline-pending-A',
  type: SyncOperationType.upsert,
  payload: {
    'id': 'offline-pending-A',
    'date': '2026-09-05',
    'type': 'expense',
    'amount': 1.23,
    'account_id': 'offline-owner-a-account',
    'category_id': 'offline-owner-a-category',
  },
);

FinanceRepository repositoryFor(
  MemoryKeyValueStore storage,
  http.Client client,
  String? token, {
  MemoryTokenStore? tokenStore,
}) {
  return FinanceRepository(
    local: LocalRepository(storage),
    queue: SyncQueue(),
    api: ApiClient(
      baseUrl: 'http://offline-owner-recovery.test',
      token: token,
      client: client,
      tokenStore: tokenStore,
    ),
  );
}

Future<MemoryTokenStore> persistOwnerStateAndQueue(
    MemoryKeyValueStore storage) async {
  final tokenStore = MemoryTokenStore()
    ..token = 'token-a'
    ..lastVerifiedUserId = userAId;
  final repository = repositoryFor(storage, ToggleNetworkClient(), 'token-a',
      tokenStore: tokenStore);
  await repository.ensureLocalOwner(userAId);
  await repository.save(ownerAState());
  repository.queue.enqueue(pendingOperation);
  await repository.persistQueue();
  return tokenStore;
}

void main() {
  test('test_same_owner_can_restore_local_state_when_app_restarts_offline',
      () async {
    final storage = MemoryKeyValueStore();
    final onlineClient = ToggleNetworkClient();
    final tokenStore = MemoryTokenStore()..token = 'token-a';
    final onlineRepository =
        repositoryFor(storage, onlineClient, 'token-a', tokenStore: tokenStore);
    final onlineStore = FinanceStore(repository: onlineRepository);

    await onlineStore.loadProfile();
    expect(onlineRepository.localOwnerUserId, userAId);
    expect(tokenStore.lastVerifiedUserId, userAId);
    await onlineRepository.save(ownerAState());

    final offlineClient = ToggleNetworkClient(online: false);
    final restartedRepository =
        repositoryFor(storage, offlineClient, null, tokenStore: tokenStore);
    expect(await restartedRepository.api!.restoreToken(), isTrue);
    expect(restartedRepository.api!.lastVerifiedUserId, userAId);
    expect((await restartedRepository.local.load())?.accounts, hasLength(1));
    final restartedStore = FinanceStore(repository: restartedRepository);
    await restartedStore.load();
    await restartedStore.loadProfile();

    expect(await restartedRepository.local.loadOwnerUserId(), userAId);
    expect(restartedStore.state.accounts.map((item) => item.id),
        contains('offline-owner-a-account'));
    expect(restartedStore.state.transactions.map((item) => item.id),
        contains('offline-owner-a-transaction'));
    expect(restartedStore.state.syncState.serverVersion, 50);
  });

  test('test_pending_queue_can_restore_and_stays_offline_after_restart',
      () async {
    final storage = MemoryKeyValueStore();
    final tokenStore = await persistOwnerStateAndQueue(storage);

    final offlineClient = ToggleNetworkClient(online: false);
    final restartedRepository =
        repositoryFor(storage, offlineClient, null, tokenStore: tokenStore);
    expect(await restartedRepository.api!.restoreToken(), isTrue);
    final restartedStore = FinanceStore(repository: restartedRepository);
    await restartedStore.load();
    await restartedStore.loadProfile();
    await restartedStore.sync();

    expect(offlineClient.pushRequestCount, 0);
    expect(restartedRepository.queue.pending(), hasLength(1));
    expect(restartedRepository.queue.pending().single.entityId,
        'offline-pending-A');
  });

  test('test_offline_restart_does_not_restore_state_for_unverifiable_user_b',
      () async {
    final storage = MemoryKeyValueStore();
    final tokenStore = await persistOwnerStateAndQueue(storage);
    tokenStore
      ..token = 'token-b'
      ..lastVerifiedUserId = userBId;

    final offlineClient = ToggleNetworkClient(online: false);
    final restartedRepository =
        repositoryFor(storage, offlineClient, null, tokenStore: tokenStore);
    expect(await restartedRepository.api!.restoreToken(), isTrue);
    final restartedStore = FinanceStore(repository: restartedRepository);
    await restartedStore.load();
    await restartedStore.loadProfile();

    expect(await restartedRepository.local.loadOwnerUserId(), userAId);
    expect(restartedStore.state.accounts, isEmpty);
    expect(restartedStore.state.transactions, isEmpty);
    expect(restartedRepository.queue.pending(), isEmpty);
  });

  test('test_unowned_legacy_data_is_not_restored_during_offline_start',
      () async {
    final storage = MemoryKeyValueStore();
    final tokenStore = MemoryTokenStore()
      ..token = 'token-a'
      ..lastVerifiedUserId = userAId;
    final legacyRepository = repositoryFor(
        storage, ToggleNetworkClient(online: false), 'token-a',
        tokenStore: tokenStore);
    await legacyRepository.save(ownerAState());
    legacyRepository.queue.enqueue(pendingOperation);
    await legacyRepository.persistQueue();

    final restartedRepository = repositoryFor(
        storage, ToggleNetworkClient(online: false), null,
        tokenStore: tokenStore);
    expect(await restartedRepository.api!.restoreToken(), isTrue);
    final restartedStore = FinanceStore(repository: restartedRepository);
    await restartedStore.load();

    expect(await restartedRepository.local.loadOwnerUserId(), isNull);
    expect(restartedStore.state.accounts, isEmpty);
    expect(restartedStore.state.transactions, isEmpty);
    expect(restartedRepository.queue.pending(), isEmpty);
  });

  test('test_owner_without_token_does_not_enter_authenticated_online_state',
      () async {
    final storage = MemoryKeyValueStore();
    final tokenStore = await persistOwnerStateAndQueue(storage);
    tokenStore.token = null;

    final api = ApiClient(
      baseUrl: 'http://offline-owner-recovery.test',
      tokenStore: tokenStore,
      client: ToggleNetworkClient(online: false),
    );
    final repository = FinanceRepository(
      local: LocalRepository(storage),
      queue: SyncQueue(),
      api: api,
    );
    final store = FinanceStore(repository: repository);
    await store.load();

    expect(api.token, isNull);
    expect(store.isDemoMode, isFalse);
    expect(store.state.accounts, isEmpty);
    expect(store.state.transactions, isEmpty);
    expect(repository.queue.pending(), isEmpty);
  });

  test('test_network_failure_preserves_verified_session_and_local_state',
      () async {
    final storage = MemoryKeyValueStore();
    final tokenStore = await persistOwnerStateAndQueue(storage);
    final offlineRepository = repositoryFor(
        storage, ToggleNetworkClient(online: false), null,
        tokenStore: tokenStore);
    expect(await offlineRepository.api!.restoreToken(), isTrue);
    final store = FinanceStore(repository: offlineRepository);

    await store.load();
    await store.loadProfile();

    expect(offlineRepository.api!.token, 'token-a');
    expect(offlineRepository.api!.lastVerifiedUserId, userAId);
    expect(await offlineRepository.local.loadOwnerUserId(), userAId);
    expect(store.state.transactions, hasLength(1));
    expect(offlineRepository.queue.pending(), hasLength(1));
  });

  test('test_logout_clears_credentials_but_preserves_local_owner_state_queue',
      () async {
    final storage = MemoryKeyValueStore();
    final tokenStore = await persistOwnerStateAndQueue(storage);
    final api = ApiClient(
      baseUrl: 'http://offline-owner-recovery.test',
      token: 'token-a',
      tokenStore: tokenStore,
    );

    await api.logout();

    final local = LocalRepository(storage);
    expect(api.token, isNull);
    expect(api.lastVerifiedUserId, isNull);
    expect(tokenStore.token, isNull);
    expect(tokenStore.lastVerifiedUserId, isNull);
    expect(await local.loadOwnerUserId(), userAId);
    expect((await local.load())?.transactions, hasLength(1));
    expect((await local.loadQueue()), hasLength(1));
  });

  test('test_401_clears_credentials_but_preserves_local_owner_state_queue',
      () async {
    final storage = MemoryKeyValueStore();
    final tokenStore = await persistOwnerStateAndQueue(storage);
    final api = ApiClient(
      baseUrl: 'http://offline-owner-recovery.test',
      token: 'token-a',
      tokenStore: tokenStore,
      client: UnauthorizedClient(),
    );

    await expectLater(api.fetchProfile(), throwsA(isA<ApiFailure>()));

    final local = LocalRepository(storage);
    expect(api.token, isNull);
    expect(api.lastVerifiedUserId, isNull);
    expect(tokenStore.token, isNull);
    expect(tokenStore.lastVerifiedUserId, isNull);
    expect(await local.loadOwnerUserId(), userAId);
    expect((await local.load())?.transactions, hasLength(1));
    expect((await local.loadQueue()), hasLength(1));
  });
}
