import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:wealthmate_flutter/data/api_client.dart';
import 'package:wealthmate_flutter/data/finance_repository.dart';
import 'package:wealthmate_flutter/data/local_repository.dart';
import 'package:wealthmate_flutter/data/sync_queue.dart';
import 'package:wealthmate_flutter/data/token_store.dart';
import 'package:wealthmate_flutter/domain/models.dart';
import 'package:wealthmate_flutter/features/auth/data/auth_remote_data_source.dart';
import 'package:wealthmate_flutter/features/auth/data/auth_repository.dart';
import 'package:wealthmate_flutter/features/auth/state/auth_store.dart';
import 'package:wealthmate_flutter/state/finance_store.dart';

class _MemoryStore implements KeyValueStore {
  final values = <String, String>{};
  final blockedReads = <String>{};
  String? blockedWrite;

  @override
  Future<String?> read(String key) async {
    if (blockedReads.contains(key)) throw StateError('read failed');
    return values[key];
  }

  @override
  Future<void> write(String key, String value) async {
    if (blockedWrite == key) throw StateError('write failed');
    values[key] = value;
  }
}

class _MemoryTokenStore implements TokenStore {
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

class _AccountClient extends http.BaseClient {
  _AccountClient({this.deleteStatus = 200});

  int deleteStatus;
  final deleteStarted = Completer<void>();
  final deleteResponse = Completer<http.Response>();

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request.method == 'DELETE') {
      if (!deleteStarted.isCompleted) deleteStarted.complete();
      final response = deleteResponse.isCompleted
          ? await deleteResponse.future
          : http.Response(
              deleteStatus == 200
                  ? '{"deleted":true}'
                  : '{"detail":"wrong password"}',
              deleteStatus);
      return _response(request, response.statusCode, response.body);
    }
    final userId = request.headers['authorization']?.split(' ').last ?? 'A';
    return _response(
      request,
      200,
      jsonEncode({
        'id': userId,
        'username': userId,
        'display_name': userId,
        'quick_memories': const <Object?>[],
      }),
    );
  }

  http.StreamedResponse _response(
      http.BaseRequest request, int status, String body) {
    return http.StreamedResponse(
      Stream<List<int>>.value(utf8.encode(body)),
      status,
      request: request,
      headers: const {'content-type': 'application/json'},
    );
  }
}

const _stateA = FinanceState(
  accounts: [Account(id: 'A-account', name: 'A account', type: AccountType.asset)],
  transactions: [
    FinanceTransaction(
      id: 'A-transaction',
      date: '2026-09-10',
      type: TransactionType.expense,
      amount: 12,
      accountId: 'A-account',
    ),
  ],
  syncState: SyncState(serverVersion: 3),
);

const _operationA = SyncOperation(
  clientOpId: 'A-operation',
  entity: 'transactions',
  entityId: 'A-transaction',
  type: SyncOperationType.upsert,
  payload: {'id': 'A-transaction'},
);

FinanceStore _store(
    _MemoryStore storage, _MemoryTokenStore tokens, _AccountClient client) {
  final api = ApiClient(
    baseUrl: 'http://phase1r.test',
    tokenStore: tokens,
    client: client,
  );
  final repository = FinanceRepository(
    local: LocalRepository(storage),
    queue: SyncQueue(),
    api: api,
  );
  final auth = AuthStore(
    repository: AuthRepository(
      remote: AuthRemoteDataSource(api: api),
    ),
  );
  return FinanceStore(repository: repository, authStore: auth);
}

Future<void> _loginAndSeed(FinanceStore store, _MemoryTokenStore tokens,
    String userId) async {
  await store.repository.api!.saveToken(userId);
  expect(await store.loadProfile(), isTrue);
  await store.repository.save(_stateA);
  store.repository.queue.replace([_operationA]);
  await store.repository.persistQueue();
  await store.load();
  expect(tokens.token, userId);
}

void main() {
  test('wrong password preserves local state and queue', () async {
    final storage = _MemoryStore();
    final tokens = _MemoryTokenStore();
    final client = _AccountClient(deleteStatus: 403);
    final store = _store(storage, tokens, client);
    await _loginAndSeed(store, tokens, 'A');

    expect(await store.deleteAccount('wrong-password'), isFalse);
    expect(store.state.toJson(), _stateA.toJson());
    expect(store.repository.queue.toJson(), [_operationA.toJson()]);
    expect((await store.repository.local.forUser('A').load())!.toJson(),
        _stateA.toJson());
    expect((await store.repository.local.forUser('A').loadQueue())
        .map((operation) => operation.toJson()), [_operationA.toJson()]);
    expect(tokens.token, 'A');
  });

  test('remote success leaves a pending cleanup marker until local purge succeeds',
      () async {
    final storage = _MemoryStore();
    final tokens = _MemoryTokenStore();
    final client = _AccountClient();
    final store = _store(storage, tokens, client);
    await _loginAndSeed(store, tokens, 'A');
    storage.blockedWrite = '${LocalRepository.storageKey}:user:A';

    expect(await store.deleteAccount('password'), isTrue);
    expect(store.pendingDeletionCleanupUserId, 'A');
    expect(tokens.token, isNull);
    expect((await store.repository.local.forUser('A').load())!.toJson(),
        _stateA.toJson());

    storage.blockedWrite = null;
    expect(await store.retryPendingDeletionCleanup(), isTrue);
    expect(store.pendingDeletionCleanupUserId, isNull);
    expect((await store.repository.local.forUser('A').load())!.toJson(),
        const FinanceState().toJson());
    expect(await store.repository.local.forUser('A').loadQueue(), isEmpty);
  });

  test('startup retries pending cleanup and never restores a deleted account',
      () async {
    final storage = _MemoryStore();
    final local = LocalRepository(storage).forUser('A');
    await local.save(_stateA);
    await local.saveQueue(SyncQueue()..enqueue(_operationA));
    await local.saveOwnerUserId('A');
    await local.markPendingAccountCleanup('A');
    final tokens = _MemoryTokenStore()
      ..token = 'A'
      ..lastVerifiedUserId = 'A';
    final store = _store(storage, tokens, _AccountClient());

    await store.load();

    expect(tokens.token, isNull);
    expect(store.profile, isNull);
    expect(store.state, const FinanceState());
    expect(store.pendingDeletionCleanupUserId, isNull);
    expect((await LocalRepository(storage).forUser('A').load())!.toJson(),
        const FinanceState().toJson());
  });

  test('unreadable cleanup state fails closed', () async {
    final storage = _MemoryStore()
      ..blockedReads.addAll([
        LocalRepository.pendingAccountCleanupKey,
        LocalRepository.pendingAccountCleanupBackupKey,
      ]);
    final tokens = _MemoryTokenStore()
      ..token = 'A'
      ..lastVerifiedUserId = 'A';
    final store = _store(storage, tokens, _AccountClient());

    await store.load();

    expect(tokens.token, isNull);
    expect(store.state, const FinanceState());
    expect(store.pendingDeletionCleanupMessage, contains('读取'));
  });

  test('late confirmed A deletion purges A without changing current B',
      () async {
    final storage = _MemoryStore();
    final tokens = _MemoryTokenStore();
    final client = _AccountClient();
    final store = _store(storage, tokens, client);
    await _loginAndSeed(store, tokens, 'A');
    final deletion = store.deleteAccount('password');
    await client.deleteStarted.future;

    await store.authStore!.logout();
    store.clearAuthenticatedSession();
    await store.repository.api!.saveToken('B');
    expect(await store.loadProfile(), isTrue);
    const bState = FinanceState(
      accounts: [Account(id: 'B-account', name: 'B account', type: AccountType.asset)],
    );
    await store.repository.save(bState);
    await store.load();
    client.deleteResponse.complete(http.Response('{"deleted":true}', 200));

    expect(await deletion, isTrue);
    expect(tokens.token, 'B');
    expect(store.profile!.id, 'B');
    expect(store.state.toJson(), bState.toJson());
    expect(store.repository.queue.pending(), isEmpty);
    expect((await store.repository.local.forUser('A').load())!.toJson(),
        const FinanceState().toJson());
  });
}
