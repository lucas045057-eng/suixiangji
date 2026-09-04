import 'package:flutter_test/flutter_test.dart';
import 'package:wealthmate_flutter/data/finance_repository.dart';
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
