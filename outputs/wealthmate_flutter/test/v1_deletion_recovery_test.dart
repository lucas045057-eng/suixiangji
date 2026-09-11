import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:wealthmate_flutter/data/api_client.dart';
import 'package:wealthmate_flutter/data/finance_repository.dart';
import 'package:wealthmate_flutter/data/local_repository.dart';
import 'package:wealthmate_flutter/data/sync_queue.dart';
import 'package:wealthmate_flutter/domain/models.dart';
import 'package:wealthmate_flutter/main.dart';
import 'package:wealthmate_flutter/state/finance_store.dart';

import 'offline_owner_recovery_test.dart' as fixtures;
import 'v1_session_partition_test.dart' show Harness;

class PartiallyFailingTokenStore extends fixtures.MemoryTokenStore {
  bool failNextTokenWrite = false;
  bool failNextVerifiedWrite = false;

  @override
  Future<void> write(String value) async {
    if (failNextTokenWrite) {
      failNextTokenWrite = false;
      token = value;
      throw StateError('token write interrupted after partial write');
    }
    await super.write(value);
  }

  @override
  Future<void> writeLastVerifiedUserId(String userId) async {
    if (failNextVerifiedWrite) {
      failNextVerifiedWrite = false;
      throw StateError('verified identity write interrupted');
    }
    await super.writeLastVerifiedUserId(userId);
  }
}

class PausingCompensationTokenStore extends PartiallyFailingTokenStore {
  int clearCount = 0;
  final compensationStarted = Completer<void>();
  final releaseCompensation = Completer<void>();

  @override
  Future<void> clear() async {
    clearCount++;
    if (clearCount == 2) {
      compensationStarted.complete();
      await releaseCompensation.future;
    }
    await super.clear();
  }
}

class FailingKeyValueStore extends fixtures.MemoryKeyValueStore {
  String? blockedKey;
  final Set<String> blockedKeys = <String>{};
  final Set<String> blockedReads = <String>{};

  @override
  Future<String?> read(String key) async {
    if (blockedReads.contains(key)) throw StateError('local read failed');
    return super.read(key);
  }

  @override
  Future<void> write(String key, String value) async {
    if (blockedKey == key || blockedKeys.contains(key)) {
      throw StateError('local cleanup write failed');
    }
    await super.write(key, value);
  }
}

void main() {
  test('partial replacement token write fails closed without old identity',
      () async {
    final tokens = PartiallyFailingTokenStore()
      ..token = 'token-A'
      ..lastVerifiedUserId = 'user-A'
      ..failNextTokenWrite = true;
    final api = ApiClient(
        baseUrl: 'http://v1.test', token: 'token-A', tokenStore: tokens);

    await expectLater(api.saveToken('token-B'), throwsA(isA<ApiFailure>()));

    expect(api.token, isNull);
    expect(api.lastVerifiedUserId, isNull);
    expect(tokens.token, isNull);
    expect(tokens.lastVerifiedUserId, isNull);
  });

  test('verified identity write failure fails closed with no token identity',
      () async {
    final tokens = PartiallyFailingTokenStore()
      ..token = 'token-A'
      ..failNextVerifiedWrite = true;
    final api = ApiClient(
        baseUrl: 'http://v1.test',
        token: 'token-A',
        tokenStore: tokens,
        client: MockClient((request) async => http.Response(
            jsonEncode({
              'id': 'user-A',
              'username': 'alice',
              'display_name': 'Alice',
              'quick_memories': []
            }),
            200)));

    await expectLater(api.fetchProfile(), throwsA(isA<ApiFailure>()));

    expect(api.token, isNull);
    expect(api.lastVerifiedUserId, isNull);
    expect(tokens.token, isNull);
    expect(tokens.lastVerifiedUserId, isNull);
  });

  test('stale credential compensation cannot erase a newer session', () async {
    final tokens = PausingCompensationTokenStore()
      ..token = 'token-A'
      ..lastVerifiedUserId = 'user-A'
      ..failNextTokenWrite = true;
    final api = ApiClient(
        baseUrl: 'http://v1.test', token: 'token-A', tokenStore: tokens);

    final failedReplacement = api.saveToken('token-B');
    await tokens.compensationStarted.future;
    final newerSession = api.saveToken('token-C');
    await Future<void>.delayed(Duration.zero);
    tokens.releaseCompensation.complete();

    await expectLater(failedReplacement, throwsA(isA<ApiFailure>()));
    await newerSession;
    expect(api.token, 'token-C');
    expect(tokens.token, 'token-C');
    expect(api.lastVerifiedUserId, isNull);
    expect(tokens.lastVerifiedUserId, isNull);
  });

  test('late confirmed A deletion purges A only after B becomes current',
      () async {
    final deleteStarted = Completer<void>();
    final deleteResponse = Completer<http.Response>();
    final h = Harness(client: MockClient((request) async {
      if (request.method == 'DELETE') {
        deleteStarted.complete();
        return deleteResponse.future;
      }
      final id = request.headers['authorization']!.split(' ').last;
      return http.Response(
          jsonEncode({
            'id': id,
            'username': id,
            'display_name': id,
            'quick_memories': []
          }),
          200);
    }));
    var expired = 0;
    h.api.onAuthExpired = () => expired++;

    await h.login('A');
    await h.seed();
    final deletion = h.store.deleteAccount('password');
    await deleteStarted.future;

    await h.logout();
    await h.login('B');
    const bState = FinanceState(accounts: [
      Account(id: 'B-account', name: 'B account', type: AccountType.asset)
    ]);
    const bOperation = SyncOperation(
        clientOpId: 'B-operation',
        entity: 'accounts',
        entityId: 'B-account',
        type: SyncOperationType.upsert,
        payload: {'id': 'B-account'});
    await h.repository.save(bState);
    h.repository.queue.replace([bOperation]);
    await h.repository.persistQueue();
    await h.store.load();

    deleteResponse.complete(http.Response('{"deleted":true}', 200));
    expect(await deletion, isTrue);

    expect(expired, 0);
    expect(h.api.token, 'B');
    expect(h.tokens.token, 'B');
    expect(h.api.lastVerifiedUserId, 'B');
    expect(h.tokens.lastVerifiedUserId, 'B');
    expect(h.store.profile!.id, 'B');
    expect(h.store.state.toJson(), bState.toJson());
    expect(h.repository.queue.toJson(), [bOperation.toJson()]);
    expect(
        (await h.repository.local.forUser('A').load())!.transactions, isEmpty);
    expect(await h.repository.local.forUser('A').loadQueue(), isEmpty);
  });

  test('confirmed deletion fails closed and retries failed local cleanup',
      () async {
    final storage = FailingKeyValueStore();
    final h = Harness(
        storage: storage,
        client: MockClient((request) async {
          if (request.method == 'DELETE') {
            return http.Response('{"deleted":true}', 200);
          }
          final id = request.headers['authorization']!.split(' ').last;
          return http.Response(
              jsonEncode({
                'id': id,
                'username': id,
                'display_name': id,
                'quick_memories': []
              }),
              200);
        }));
    var expired = 0;
    h.api.onAuthExpired = () => expired++;

    await h.login('A');
    await h.seed();
    storage.blockedKey = '${LocalRepository.storageKey}:user:A';

    expect(await h.store.deleteAccount('password'), isTrue);

    expect(expired, 1);
    expect(h.api.token, isNull);
    expect(h.tokens.token, isNull);
    expect(h.store.profile, isNull);
    expect(h.store.message, contains('本机'));

    storage.blockedKey = null;
    expect(await h.store.retryPendingDeletionCleanup(), isTrue);
    expect(h.store.pendingDeletionCleanupUserId, isNull);
    expect(h.store.message, isNull);
    expect((await h.repository.local.forUser('A').load())!.toJson(),
        const FinanceState().toJson());
    expect(await h.repository.local.forUser('A').loadQueue(), isEmpty);
  });

  test('pending deleted account cannot restore its partition on restart',
      () async {
    final storage = FailingKeyValueStore();
    final legacy = LocalRepository(storage).forUser('A');
    await legacy.save(fixtures.ownerAState());
    await legacy.saveOwnerUserId('A');
    await legacy.markPendingAccountCleanup('A');
    storage.blockedKey = '${LocalRepository.storageKey}:user:A';
    final tokens = fixtures.MemoryTokenStore()
      ..token = 'token-A'
      ..lastVerifiedUserId = 'A';
    final api = ApiClient(
        baseUrl: 'http://v1.test',
        token: 'token-A',
        tokenStore: tokens,
        client: MockClient((request) async => http.Response(
            jsonEncode({
              'id': 'A',
              'username': 'Alice',
              'display_name': 'A',
              'quick_memories': []
            }),
            200)));
    final hRepository = FinanceRepository(
        local: LocalRepository(storage), queue: SyncQueue(), api: api);
    final store = FinanceStore(repository: hRepository);

    await store.load();

    expect(api.token, isNull);
    expect(tokens.token, isNull);
    expect(store.state.toJson(), const FinanceState().toJson());
    expect(store.profile, isNull);
    expect(store.pendingDeletionCleanupUserId, 'A');
  });

  test('a later deleted account cannot overwrite an earlier cleanup task',
      () async {
    final storage = FailingKeyValueStore();
    final client = MockClient((request) async {
      if (request.method == 'DELETE') {
        return http.Response('{"deleted":true}', 200);
      }
      final id = request.headers['authorization']!.split(' ').last;
      return http.Response(
          jsonEncode({
            'id': id,
            'username': id,
            'display_name': id,
            'quick_memories': []
          }),
          200);
    });
    final h = Harness(storage: storage, client: client);
    await h.login('A');
    await h.seed();
    storage.blockedKey = '${LocalRepository.storageKey}:user:A';
    expect(await h.store.deleteAccount('password'), isTrue);
    expect(h.store.pendingDeletionCleanupUserId, 'A');
    expect((await h.repository.local.forUser('A').load())!.transactions,
        isNotEmpty);

    final bTokens = fixtures.MemoryTokenStore();
    final bApi = ApiClient(
        baseUrl: 'http://v1.test', tokenStore: bTokens, client: client);
    final bRepository = FinanceRepository(
        local: LocalRepository(storage), queue: SyncQueue(), api: bApi);
    final bStore = FinanceStore(repository: bRepository);
    await bApi.saveToken('B');
    expect(await bStore.loadProfile(), isTrue);
    await bStore.load();
    expect(bStore.pendingDeletionCleanupUserId, 'A');
    expect(await bStore.deleteAccount('password'), isTrue);

    expect(bStore.pendingDeletionCleanupUserId, 'A');
    expect((await h.repository.local.forUser('A').load())!.transactions,
        isNotEmpty);
    storage.blockedKey = null;
    expect(await bStore.retryPendingDeletionCleanup(), isTrue);
    expect(bStore.pendingDeletionCleanupUserId, isNull);
    expect(
        (await h.repository.local.forUser('A').load())!.transactions, isEmpty);
  });

  test('cleanup marker survives a failed primary marker write across restart',
      () async {
    final storage = FailingKeyValueStore();
    final h = Harness(
        storage: storage,
        client: MockClient((request) async {
          if (request.method == 'DELETE') {
            return http.Response('{"deleted":true}', 200);
          }
          final id = request.headers['authorization']!.split(' ').last;
          return http.Response(
              jsonEncode({
                'id': id,
                'username': id,
                'display_name': id,
                'quick_memories': []
              }),
              200);
        }));
    await h.login('A');
    await h.seed();
    storage.blockedKeys.addAll([
      LocalRepository.pendingAccountCleanupKey,
      '${LocalRepository.storageKey}:user:A'
    ]);

    expect(await h.store.deleteAccount('password'), isTrue);
    expect(h.store.pendingDeletionCleanupUserId, 'A');

    final restartedApi = ApiClient(
        baseUrl: 'http://v1.test',
        tokenStore: h.tokens,
        client: MockClient((_) async => throw StateError('offline')));
    final restartedRepository = FinanceRepository(
        local: LocalRepository(storage), queue: SyncQueue(), api: restartedApi);
    final restartedStore = FinanceStore(repository: restartedRepository);
    await restartedStore.load();

    expect(restartedApi.token, isNull);
    expect(restartedStore.state.toJson(), const FinanceState().toJson());
    expect(restartedStore.pendingDeletionCleanupUserId, 'A');
  });

  test('pending A cleanup does not log out a verified B on restart', () async {
    final storage = fixtures.MemoryKeyValueStore();
    final local = LocalRepository(storage);
    await local.forUser('A').save(fixtures.ownerAState());
    await local.markPendingAccountCleanup('A');
    const bState = FinanceState(accounts: [
      Account(id: 'B-account', name: 'B account', type: AccountType.asset)
    ]);
    await local.forUser('B').save(bState);
    final tokens = fixtures.MemoryTokenStore()
      ..token = 'token-B'
      ..lastVerifiedUserId = 'B';
    final api = ApiClient(
        baseUrl: 'http://v1.test',
        tokenStore: tokens,
        client: MockClient((_) async => throw StateError('offline')));
    final repository =
        FinanceRepository(local: local, queue: SyncQueue(), api: api);
    final store = FinanceStore(repository: repository);

    await store.load();

    expect(api.token, 'token-B');
    expect(tokens.token, 'token-B');
    expect(api.lastVerifiedUserId, 'B');
    expect(store.state.toJson(), bState.toJson());
  });

  test('unknown cleanup marker state fails closed without loading any user',
      () async {
    final storage = FailingKeyValueStore();
    final local = LocalRepository(storage);
    await local.markPendingAccountCleanup('A');
    const bState = FinanceState(accounts: [
      Account(id: 'B-account', name: 'B account', type: AccountType.asset)
    ]);
    await local.forUser('B').save(bState);
    storage.blockedReads.addAll([
      LocalRepository.pendingAccountCleanupKey,
      LocalRepository.pendingAccountCleanupBackupKey
    ]);
    final tokens = fixtures.MemoryTokenStore()
      ..token = 'token-B'
      ..lastVerifiedUserId = 'B';
    final api = ApiClient(
        baseUrl: 'http://v1.test', token: 'token-B', tokenStore: tokens);
    final repository =
        FinanceRepository(local: local, queue: SyncQueue(), api: api);
    final store = FinanceStore(repository: repository);

    await store.load();

    expect(api.token, isNull);
    expect(tokens.token, isNull);
    expect(store.state.toJson(), const FinanceState().toJson());
    expect(store.pendingDeletionCleanupMessage, contains('读取'));
  });

  testWidgets('failed account cleanup is actionable from the login page',
      (tester) async {
    final storage = FailingKeyValueStore();
    final h = Harness(
        storage: storage,
        client: MockClient((request) async {
          if (request.method == 'DELETE') {
            return http.Response('{"deleted":true}', 200);
          }
          final id = request.headers['authorization']!.split(' ').last;
          return http.Response(
              jsonEncode({
                'id': id,
                'username': id,
                'display_name': id,
                'quick_memories': []
              }),
              200);
        }));
    await h.login('A');
    await h.seed();
    storage.blockedKey = '${LocalRepository.storageKey}:user:A';
    expect(await h.store.deleteAccount('password'), isTrue);

    await tester.pumpWidget(WealthMateApp(
        store: h.store, api: h.api, auth: h.store.authStore));
    await tester.pumpAndSettle();
    expect(find.text('账号已删除，但本机数据清理仍未完成，请重试本机清理'), findsOneWidget);
    expect(find.text('重试本机清理'), findsOneWidget);

    storage.blockedKey = null;
    await tester.tap(find.text('重试本机清理'));
    await tester.pumpAndSettle();
    expect(h.store.pendingDeletionCleanupUserId, isNull);
  });
}
