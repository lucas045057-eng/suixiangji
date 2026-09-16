import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:wealthmate_flutter/data/api_client.dart';
import 'package:wealthmate_flutter/data/drift_database.dart';
import 'package:wealthmate_flutter/data/finance_repository.dart';
import 'package:wealthmate_flutter/data/local_repository.dart';
import 'package:wealthmate_flutter/data/sync_queue.dart';
import 'package:wealthmate_flutter/data/token_store.dart';
import 'package:wealthmate_flutter/domain/models.dart';
import 'package:wealthmate_flutter/state/finance_store.dart';
import 'package:wealthmate_flutter/ui/app_shell.dart';

const _userId = 'startup-cursor-user';
const _transactionId = 'startup-cursor-transaction';
const _clientOpId = 'startup-cursor-op-001';

class MemoryKeyValueStore implements KeyValueStore {
  final Map<String, String> values = {};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;
}

class MemoryTokenStore implements TokenStore {
  @override
  Future<String?> read() async => 'startup-cursor-token';

  @override
  Future<void> write(String value) async {}

  @override
  Future<void> clear() async {}

  @override
  Future<String?> readLastVerifiedUserId() async => _userId;

  @override
  Future<void> writeLastVerifiedUserId(String userId) async {}

  @override
  Future<void> clearLastVerifiedUserId() async {}
}

class StartupCursorClient extends http.BaseClient {
  StartupCursorClient({this.remoteServerVersion = 8});

  final int remoteServerVersion;
  final List<int> requestedSinceVersions = [];
  int pushRequestCount = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request.url.path == '/sync/push') {
      pushRequestCount++;
      return _jsonResponse(
        200,
        {
          'accepted': [
            {
              'client_op_id': _clientOpId,
              'entity_id': _transactionId,
              'server_version': remoteServerVersion,
            }
          ],
          'conflicts': const <Object?>[],
          'server_version': remoteServerVersion,
        },
        request,
      );
    }
    if (request.url.path == '/sync/pull') {
      requestedSinceVersions
          .add(int.parse(request.url.queryParameters['since_version']!));
      return _jsonResponse(
        200,
        {
          'items': const <Object?>[],
          'accounts': const <Object?>[],
          'categories': const <Object?>[],
          'budgets': const <Object?>[],
          'server_version': remoteServerVersion,
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

class StartupFlowClient extends http.BaseClient {
  final List<int> requestedSinceVersions = [];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request.url.path == '/auth/me') {
      return _jsonResponse(
        200,
        {
          'id': _userId,
          'username': 'startup-cursor-user',
          'display_name': 'Startup Cursor User',
          'quick_memories': const <Object?>[],
        },
        request,
      );
    }
    if (request.url.path == '/sync/pull') {
      final since = int.parse(request.url.queryParameters['since_version']!);
      requestedSinceVersions.add(since);
      return _jsonResponse(
        200,
        {
          'items': const <Object?>[],
          'accounts': const <Object?>[],
          'categories': const <Object?>[],
          'budgets': const <Object?>[],
          'server_version': 8,
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

class FailingPushClient extends http.BaseClient {
  int pushRequestCount = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request.url.path == '/sync/push') {
      pushRequestCount++;
      throw const SocketException('push unavailable');
    }
    return http.StreamedResponse(
      Stream<List<int>>.value(utf8.encode('{}')),
      404,
      request: request,
      headers: const {'content-type': 'application/json'},
    );
  }
}

FinanceRepository _repository(
    AppDatabase database, StartupCursorClient client) {
  return FinanceRepository(
    local: LocalRepository(DriftKeyValueStore(database)),
    queue: SyncQueue(),
    api: ApiClient(
      baseUrl: 'http://startup-cursor.test',
      token: 'startup-cursor-token',
      client: client,
    ),
  );
}

FinanceRepository _memoryRepository(StartupCursorClient client) {
  return FinanceRepository(
    local: LocalRepository(MemoryKeyValueStore()),
    queue: SyncQueue(),
    api: ApiClient(
      baseUrl: 'http://startup-cursor.test',
      token: 'startup-cursor-token',
      client: client,
    ),
  );
}

const _initialState = FinanceState(
  transactions: [
    FinanceTransaction(
      id: _transactionId,
      date: '2026-09-06',
      type: TransactionType.expense,
      amount: 10.11,
      accountId: 'startup-account',
      categoryId: 'startup-category',
      serverVersion: 7,
    ),
  ],
  syncState: SyncState(serverVersion: 7),
);

const _persistedRestartState = FinanceState(
  transactions: [
    FinanceTransaction(
      id: _transactionId,
      date: '2026-09-06',
      type: TransactionType.expense,
      amount: 10.11,
      accountId: 'startup-account',
      categoryId: 'startup-category',
      serverVersion: 8,
    ),
  ],
  syncState: SyncState(serverVersion: 8),
);

const _pendingOperation = SyncOperation(
  clientOpId: _clientOpId,
  entity: 'transactions',
  entityId: _transactionId,
  type: SyncOperationType.upsert,
  payload: {
    'id': _transactionId,
    'date': '2026-09-06',
    'type': 'expense',
    'amount': 10.11,
    'currency': 'CNY',
    'account_id': 'startup-account',
    'category_id': 'startup-category',
  },
);

void main() {
  test('empty pending queue does not reset server version', () async {
    final client = StartupCursorClient();
    final repository = _memoryRepository(client);
    await repository.ensureLocalOwner(_userId);

    const state = FinanceState(
      syncState: SyncState(
        serverVersion: 8,
        lastSyncedAt: '2026-09-06T10:00:00Z',
        isSyncing: true,
        error: 'stale runtime error',
      ),
    );
    final next = await repository.pushPending(state);

    expect(client.pushRequestCount, 0);
    expect(next.syncState.serverVersion, 8);
    expect(next.syncState.lastSyncedAt, '2026-09-06T10:00:00Z');
    expect(next.syncState.isSyncing, isFalse);
    expect(next.syncState.error, isNull);
  });

  test('fresh empty queue starts from server version zero', () async {
    final client = StartupCursorClient();
    final repository = _memoryRepository(client);
    await repository.ensureLocalOwner(_userId);

    final next = await repository.pushPending(const FinanceState());

    expect(client.pushRequestCount, 0);
    expect(next.syncState.serverVersion, 0);
  });

  test('failed push preserves server version and pending operation', () async {
    final client = FailingPushClient();
    final repository = FinanceRepository(
      local: LocalRepository(MemoryKeyValueStore()),
      queue: SyncQueue(),
      api: ApiClient(
        baseUrl: 'http://startup-cursor.test',
        token: 'startup-cursor-token',
        client: client,
      ),
    );
    await repository.ensureLocalOwner(_userId);
    repository.queue.enqueue(_pendingOperation);

    final result = await repository.pushPending(_initialState);

    expect(client.pushRequestCount, 1);
    expect(result.syncState.serverVersion, 7);
    expect(result.syncState.error, contains('暂时无法连接同步服务'));
    expect(repository.queue.pending().map((item) => item.clientOpId),
        contains(_clientOpId));
  });

  test('successful push persists entity version without advancing pull cursor',
      () async {
    final directory =
        await Directory.systemTemp.createTemp('suixiangji-startup-cursor-');
    final file =
        File('${directory.path}${Platform.pathSeparator}push-cursor.sqlite');
    AppDatabase? firstDatabase;
    AppDatabase? restartedDatabase;
    try {
      firstDatabase = AppDatabase(NativeDatabase(file));
      final client = StartupCursorClient();
      final firstRepository = _repository(firstDatabase, client);
      await firstRepository.ensureLocalOwner(_userId);
      await firstRepository.save(_initialState);
      firstRepository.queue.enqueue(_pendingOperation);
      await firstRepository.persistQueue();

      final afterPush = await firstRepository.pushPending(_initialState);

      expect(afterPush.syncState.serverVersion, 7);
      expect(afterPush.transactions.single.serverVersion, 8);
      expect(firstRepository.queue.pending(), isEmpty);
      expect(client.pushRequestCount, 1);

      await firstDatabase.close();
      firstDatabase = null;

      restartedDatabase = AppDatabase(NativeDatabase(file));
      final restartedRepository = _repository(
          restartedDatabase, StartupCursorClient(remoteServerVersion: 8));
      final restored = await restartedRepository.loadForUser(_userId);

      expect(restored?.syncState.serverVersion, 7);
      expect(restored?.transactions.single.serverVersion, 8);
    } finally {
      await firstDatabase?.close();
      await restartedDatabase?.close();
      await directory.delete(recursive: true);
    }
  });

  test('successful pull persists updated server version without manual save',
      () async {
    final directory =
        await Directory.systemTemp.createTemp('suixiangji-startup-cursor-');
    final file =
        File('${directory.path}${Platform.pathSeparator}pull-cursor.sqlite');
    AppDatabase? firstDatabase;
    AppDatabase? restartedDatabase;
    try {
      firstDatabase = AppDatabase(NativeDatabase(file));
      final client = StartupCursorClient();
      final firstRepository = _repository(firstDatabase, client);
      await firstRepository.ensureLocalOwner(_userId);
      await firstRepository.save(_initialState);

      final afterPull = await firstRepository.pullChanges(_initialState);

      expect(afterPull.syncState.serverVersion, 8);
      expect(client.requestedSinceVersions, [7]);

      await firstDatabase.close();
      firstDatabase = null;

      restartedDatabase = AppDatabase(NativeDatabase(file));
      final restartedRepository = _repository(
          restartedDatabase, StartupCursorClient(remoteServerVersion: 8));
      final restored = await restartedRepository.loadForUser(_userId);

      expect(restored?.syncState.serverVersion, 8);
    } finally {
      await firstDatabase?.close();
      await restartedDatabase?.close();
      await directory.delete(recursive: true);
    }
  });

  testWidgets('AppShell startup uses the persisted cursor before first pull',
      (tester) async {
    final storage = MemoryKeyValueStore();
    final client = StartupFlowClient();
    final repository = FinanceRepository(
      local: LocalRepository(storage),
      queue: SyncQueue(),
      api: ApiClient(
        baseUrl: 'http://startup-cursor.test',
        token: 'startup-cursor-token',
        client: client,
        tokenStore: MemoryTokenStore(),
      ),
    );
    await repository.ensureLocalOwner(_userId);
    await repository.save(_persistedRestartState);
    final store = FinanceStore(repository: repository);
    await store.load();

    await tester.pumpWidget(MaterialApp(home: AppShell(store: store)));
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pump();

    expect(client.requestedSinceVersions, [8]);
  });
}
