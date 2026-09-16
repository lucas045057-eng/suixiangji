import 'package:flutter_test/flutter_test.dart';
import 'package:wealthmate_flutter/core/database/local_state_session.dart';
import 'package:wealthmate_flutter/data/finance_repository.dart';
import 'package:wealthmate_flutter/data/local_repository.dart';
import 'package:wealthmate_flutter/data/sync_queue.dart';
import 'package:wealthmate_flutter/domain/models.dart';
import 'package:wealthmate_flutter/features/ledger/data/ledger_repository.dart';
import 'package:wealthmate_flutter/features/ledger/state/ledger_store.dart';

class _LedgerMemory implements KeyValueStore {
  final Map<String, String> values = <String, String>{};
  int writes = 0;

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    writes += 1;
    values[key] = value;
  }
}

class _SentinelLedgerRepository extends LedgerRepository {
  _SentinelLedgerRepository({required super.session, required this.result});

  final FinanceState result;

  @override
  Future<FinanceState> saveTransaction(FinanceTransaction transaction,
          {FinanceState? baseState}) async =>
      result;

  @override
  Future<FinanceState> saveCategory(Category category,
          {FinanceState? baseState}) async =>
      result;

  @override
  Future<FinanceState> deleteTransaction(String transactionId,
          {FinanceState? baseState, String? deletedAt}) async =>
      result;
}

LedgerStore _ledgerStore(_LedgerMemory memory) {
  final queue = SyncQueue();
  final session = LocalStateSession(
    local: LocalRepository(memory),
    queue: queue,
  );
  return LedgerStore(
    repository: LedgerRepository(session: session),
    initialState: const FinanceState(
      currentMonth: '2026-09',
      accounts: [
        Account(id: 'wallet', name: '钱包', type: AccountType.asset),
      ],
      categories: [
        Category(id: 'food', name: '餐饮'),
      ],
    ),
  );
}

void main() {
  test('LedgerStore keeps local CRUD and sync operation semantics', () async {
    final memory = _LedgerMemory();
    final store = _ledgerStore(memory);

    await store.addTransaction(const FinanceTransaction(
      id: 'tx-1',
      date: '2026-09-10',
      type: TransactionType.expense,
      amount: 32,
      categoryId: 'food',
      accountId: 'wallet',
    ));
    await store
        .updateTransaction(store.transactions.single.copyWith(amount: 36));

    expect(store.transactions, hasLength(1));
    expect(store.transactions.single.id, 'tx-1');
    expect(store.transactions.single.amount, 36);
    expect(store.repository.queue.pending(), hasLength(1));
    expect(store.repository.queue.pending().single.clientOpId, 'tx-1');

    await store.deleteTransaction('tx-1');
    final delete = store.repository.queue.pending().single;
    expect(store.transactions.single.deletedAt, isNotNull);
    expect(delete.type, SyncOperationType.delete);
    expect(delete.entityId, 'tx-1');
    expect(delete.clientOpId, isNot('tx-1'));

    await store.addCategory(name: '宠物', type: TransactionType.expense);
    final category =
        store.state.categories.singleWhere((item) => item.name == '宠物');
    await store.updateCategory(category.id, name: '宠物照护', active: true);
    await store.archiveCategory(category.id);

    expect(
        store.state.categories
            .singleWhere((item) => item.id == category.id)
            .name,
        '宠物照护');
    expect(store.activeCategories.map((item) => item.id),
        isNot(contains(category.id)));
    final categoryOperation = store.repository.queue
        .pending()
        .singleWhere((operation) => operation.entity == 'categories');
    expect(
        categoryOperation.clientOpId, startsWith('category:${category.id}:'));
    expect(memory.writes, greaterThan(0));
  });

  test('a synced transaction edit receives a new operation identity', () async {
    final memory = _LedgerMemory();
    final store = _ledgerStore(memory);
    await store.addTransaction(const FinanceTransaction(
      id: 'synced-tx',
      date: '2026-09-10',
      type: TransactionType.expense,
      amount: 10,
      categoryId: 'food',
      accountId: 'wallet',
      clientOpId: 'create-op',
      serverVersion: 7,
    ));
    store.repository.queue.replace(const []);

    await store
        .updateTransaction(store.transactions.single.copyWith(amount: 12));

    final operation = store.repository.queue.pending().single;
    expect(operation.entity, 'transactions');
    expect(operation.entityId, 'synced-tx');
    expect(operation.type, SyncOperationType.upsert);
    expect(operation.clientOpId, startsWith('edit-'));
    expect(operation.clientOpId, isNot('create-op'));
  });

  test(
      'LedgerStore rejects non-transfer transactions using the opposite category type',
      () async {
    final memory = _LedgerMemory();
    final queue = SyncQueue();
    final session = LocalStateSession(
      local: LocalRepository(memory),
      queue: queue,
    );
    final store = LedgerStore(
      repository: LedgerRepository(session: session),
      initialState: const FinanceState(
        currentMonth: '2026-09',
        accounts: [
          Account(id: 'wallet', name: '钱包', type: AccountType.asset),
        ],
        categories: [
          Category(id: 'salary', name: '工资', type: TransactionType.income),
        ],
      ),
    );

    await expectLater(
      store.addTransaction(const FinanceTransaction(
        id: 'tx-opposite-category',
        date: '2026-09-10',
        type: TransactionType.expense,
        amount: 12,
        categoryId: 'salary',
        accountId: 'wallet',
      )),
      throwsA(isA<ArgumentError>()),
    );
    expect(store.transactions, isEmpty);
    expect(store.repository.queue.pending(), isEmpty);
  });

  test('FinanceRepository delegates Ledger mutation compatibility methods',
      () async {
    final memory = _LedgerMemory();
    final queue = SyncQueue();
    final session = LocalStateSession(
      local: LocalRepository(memory),
      queue: queue,
    );
    const delegated = FinanceState(currentMonth: 'delegated-by-ledger');
    final repository = FinanceRepository(
      local: LocalRepository(memory),
      queue: queue,
      session: session,
      ledgerRepository:
          _SentinelLedgerRepository(session: session, result: delegated),
    );
    const original = FinanceState(
      categories: [Category(id: 'food', name: '餐饮')],
      transactions: [
        FinanceTransaction(
          id: 'tx-1',
          date: '2026-09-12',
          type: TransactionType.expense,
          amount: 10,
          categoryId: 'food',
          accountId: 'wallet',
        ),
      ],
    );

    expect(
      identical(
        await repository.applyLocalTransaction(
            original, original.transactions.single),
        delegated,
      ),
      isTrue,
    );
    expect(
      identical(
        await repository.applyLocalCategory(
            original, original.categories.single),
        delegated,
      ),
      isTrue,
    );
    expect(
      identical(await repository.softDelete(original, 'tx-1'), delegated),
      isTrue,
    );
  });
}
