import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:wealthmate_flutter/data/api_client.dart';
import 'package:wealthmate_flutter/data/finance_repository.dart';
import 'package:wealthmate_flutter/data/drift_database.dart';
import 'package:wealthmate_flutter/data/local_repository.dart';
import 'package:wealthmate_flutter/data/sync_queue.dart';
import 'package:wealthmate_flutter/domain/models.dart';

class MemoryKeyValueStore implements KeyValueStore {
  final Map<String, String> values = {};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;
}

class SyncPushClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final body = jsonEncode({
      'accepted': [
        {
          'client_op_id': 'tx-1',
          'entity_id': 'tx-1',
          'server_version': 7,
          'created': true,
        }
      ],
      'conflicts': const [],
      'server_version': 7,
    });
    return http.StreamedResponse(
      Stream<List<int>>.value(utf8.encode(body)),
      200,
      request: request,
      headers: const {'content-type': 'application/json'},
    );
  }
}

FinanceTransaction repositoryTransaction(
    {int? serverVersion, String note = '午餐'}) {
  return FinanceTransaction(
    id: 'tx-1',
    date: '2026-09-01',
    type: TransactionType.expense,
    amount: 32,
    categoryId: 'food',
    accountId: 'alipay',
    note: note,
    serverVersion: serverVersion,
  );
}

void main() {
  test('local repository round-trips accounts and transactions as JSON',
      () async {
    final repository = FinanceRepository(
      local: LocalRepository(MemoryKeyValueStore()),
      queue: SyncQueue(),
    );
    final state = FinanceState(
      currentMonth: '2026-09',
      accounts: const [
        Account(id: 'alipay', name: '支付宝', type: AccountType.asset)
      ],
      transactions: [repositoryTransaction()],
    );

    await repository.save(state);
    final loaded = await repository.load();

    expect(loaded?.accounts.single.name, '支付宝');
    expect(loaded?.transactions.single.amount, 32);
  });

  test('sync queue keeps one operation for a repeated client operation id', () {
    final queue = SyncQueue();
    final first = SyncOperation(
      clientOpId: 'op-1',
      entity: 'transactions',
      entityId: 'tx-1',
      type: SyncOperationType.upsert,
      payload: repositoryTransaction().toJson(),
    );

    queue.enqueue(first);
    queue.enqueue(first);

    expect(queue.pending(), hasLength(1));
    expect(queue.pending().single.clientOpId, 'op-1');
  });

  test('ten offline transactions stay visible and queued locally', () async {
    final repository = FinanceRepository(
      local: LocalRepository(MemoryKeyValueStore()),
      queue: SyncQueue(),
    );
    var state = const FinanceState(currentMonth: '2026-09');

    for (var index = 1; index <= 10; index++) {
      state = await repository.applyLocal(
          state,
          FinanceTransaction(
            id: 'offline-tx-$index',
            clientOpId: 'offline-op-$index',
            date: '2026-09-04',
            type: TransactionType.expense,
            amount: index.toDouble(),
            note: '离线测试 $index',
          ));
    }

    expect(state.transactions, hasLength(10));
    expect(repository.queue.pending(), hasLength(10));
  });

  test('local repository persists pending sync operations across reloads',
      () async {
    final storage = MemoryKeyValueStore();
    final queue = SyncQueue();
    queue.enqueue(SyncOperation(
      clientOpId: 'op-queue',
      entity: 'transactions',
      entityId: 'tx-1',
      type: SyncOperationType.upsert,
      payload: repositoryTransaction().toJson(),
    ));
    final local = LocalRepository(storage);

    await local.saveQueue(queue);
    final loaded = await local.loadQueue();

    expect(loaded.single.clientOpId, 'op-queue');
  });

  test('recreated repository restores the complete pending operation',
      () async {
    final storage = MemoryKeyValueStore();
    final firstRepository = FinanceRepository(
      local: LocalRepository(storage),
      queue: SyncQueue(),
    );
    firstRepository.queue.enqueue(SyncOperation(
      clientOpId: 'restart:tx-1',
      entity: 'transactions',
      entityId: 'tx-1',
      type: SyncOperationType.upsert,
      payload: repositoryTransaction().toJson(),
      createdAt: '2026-09-04T10:00:00+08:00',
    ));
    await firstRepository.persistQueue();

    final restartedRepository = FinanceRepository(
      local: LocalRepository(storage),
      queue: SyncQueue(),
    );
    await restartedRepository.load();

    final operation = restartedRepository.queue.pending().single;
    expect(operation.clientOpId, 'restart:tx-1');
    expect(operation.entityId, 'tx-1');
    expect(operation.payload['amount'], 32);
    expect(operation.createdAt, '2026-09-04T10:00:00+08:00');
  });

  test('a real Drift SQLite file keeps the queue after database recreation',
      () async {
    final directory = await Directory.systemTemp.createTemp('suixiangji-sync-');
    final file = File('${directory.path}${Platform.pathSeparator}sync.sqlite');
    final firstDatabase = AppDatabase(NativeDatabase(file));
    final firstRepository = FinanceRepository(
      local: LocalRepository(DriftKeyValueStore(firstDatabase)),
      queue: SyncQueue(),
    );
    firstRepository.queue.enqueue(SyncOperation(
      clientOpId: 'sqlite-restart:tx-1',
      entity: 'transactions',
      entityId: 'tx-1',
      type: SyncOperationType.upsert,
      payload: repositoryTransaction().toJson(),
    ));
    await firstRepository.persistQueue();
    await firstDatabase.close();

    final restartedDatabase = AppDatabase(NativeDatabase(file));
    final restartedRepository = FinanceRepository(
      local: LocalRepository(DriftKeyValueStore(restartedDatabase)),
      queue: SyncQueue(),
    );
    await restartedRepository.load();

    expect(restartedRepository.queue.pending().single.clientOpId,
        'sqlite-restart:tx-1');
    await restartedDatabase.close();
    await directory.delete(recursive: true);
  });

  test('push applies the accepted server version to the local transaction',
      () async {
    final transaction = repositoryTransaction();
    final repository = FinanceRepository(
      local: LocalRepository(MemoryKeyValueStore()),
      queue: SyncQueue(),
      api: ApiClient(
        baseUrl: 'http://example.test',
        token: 'test-token',
        client: SyncPushClient(),
      ),
    );
    await repository.ensureLocalOwner('repository-test-user');
    repository.queue.enqueue(SyncOperation(
      clientOpId: transaction.clientOpId,
      entity: 'transactions',
      entityId: transaction.id,
      type: SyncOperationType.upsert,
      payload: transaction.toJson(),
    ));

    final next =
        await repository.pushPending(FinanceState(transactions: [transaction]));

    expect(next.transactions.single.serverVersion, 7);
    expect(repository.queue.pending(), isEmpty);
  });

  test('an empty local repository merges all supported pulled entities', () {
    final repository = FinanceRepository(
      local: LocalRepository(MemoryKeyValueStore()),
      queue: SyncQueue(),
    );
    final empty = const FinanceState(currentMonth: '2026-09');
    final account = const Account(
      id: 'remote-account',
      name: '远端账户',
      type: AccountType.asset,
      serverVersion: 2,
    );
    final category = const Category(
      id: 'remote-category',
      name: '远端分类',
    );
    final transaction = repositoryTransaction(serverVersion: 4);
    final budget = const Budget(
      id: 'remote-budget',
      month: '2026-09',
      categoryId: 'remote-category',
      limit: 500,
      serverVersion: 3,
    );

    final merged = repository.mergePulledBudgets(
        repository.mergePulledCategories(
            repository.mergePulledAccounts(
                repository.mergePulled(empty, [transaction]), [account]),
            [category]),
        [budget]);

    expect(merged.accounts.single.id, 'remote-account');
    expect(merged.categories.single.id, 'remote-category');
    expect(merged.transactions.single.id, 'tx-1');
    expect(merged.budgets.single.id, 'remote-budget');
  });

  test('stale remote update is recorded as a conflict', () {
    final repository = FinanceRepository(
        local: LocalRepository(MemoryKeyValueStore()), queue: SyncQueue());
    final local = FinanceState(
      currentMonth: '2026-09',
      transactions: [repositoryTransaction(serverVersion: 4)],
    );
    final remote = repositoryTransaction(serverVersion: 3, note: '远端修改');

    final merged = repository.mergePulled(local, [remote]);

    expect(merged.transactions.single.note, '午餐');
    expect(merged.conflicts, contains('transactions:tx-1'));
  });
}
