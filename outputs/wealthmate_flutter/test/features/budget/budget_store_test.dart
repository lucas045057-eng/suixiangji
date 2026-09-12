import 'package:flutter_test/flutter_test.dart';
import 'package:wealthmate_flutter/core/database/local_state_session.dart';
import 'package:wealthmate_flutter/data/finance_repository.dart';
import 'package:wealthmate_flutter/data/local_repository.dart';
import 'package:wealthmate_flutter/data/sync_queue.dart';
import 'package:wealthmate_flutter/domain/models.dart';
import 'package:wealthmate_flutter/features/budget/data/budget_repository.dart';
import 'package:wealthmate_flutter/features/budget/domain/budget_rules.dart';
import 'package:wealthmate_flutter/features/budget/state/budget_store.dart';
import 'package:wealthmate_flutter/state/finance_store.dart';

class _MemoryStore implements KeyValueStore {
  final Map<String, String> values = <String, String>{};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }
}

FinanceState _state({
  String month = '2026-09',
  List<Budget> budgets = const <Budget>[],
  List<FinanceTransaction> transactions = const <FinanceTransaction>[],
}) {
  return FinanceState(
    currentMonth: month,
    categories: const [
      Category(id: 'food', name: '餐饮'),
      Category(id: 'transport', name: '交通'),
    ],
    budgets: budgets,
    transactions: transactions,
  );
}

BudgetStore _store({FinanceState? initialState}) {
  final local = LocalRepository(_MemoryStore());
  final queue = SyncQueue();
  final session = LocalStateSession(local: local, queue: queue);
  return BudgetStore(
    repository: BudgetRepository(session: session),
    initialState: initialState,
  );
}

BudgetStore _storeWithSession(
  LocalStateSession session, {
  FinanceState? initialState,
}) {
  return BudgetStore(
    repository: BudgetRepository(session: session),
    initialState: initialState,
  );
}

void main() {
  test('budget thresholds distinguish healthy, warning, exhausted, and over',
      () {
    expect(levelForRatio(.79), isNull);
    expect(levelForRatio(.8), BudgetAlertLevel.warning);
    expect(levelForRatio(1), BudgetAlertLevel.exhausted);
    expect(levelForRatio(1.01), BudgetAlertLevel.over);
  });

  test('budget progress filters by month and category facts', () {
    final store = _store(
      initialState: _state(
        budgets: const [
          Budget(
              id: 'sep-food', month: '2026-09', categoryId: 'food', limit: 100),
          Budget(
              id: 'sep-transport',
              month: '2026-09',
              categoryId: 'transport',
              limit: 100),
          Budget(
              id: 'oct-food', month: '2026-10', categoryId: 'food', limit: 100),
        ],
        transactions: const [
          FinanceTransaction(
              id: 'sep-food-tx',
              date: '2026-09-02',
              type: TransactionType.expense,
              amount: 80,
              categoryId: 'food'),
          FinanceTransaction(
              id: 'sep-transport-tx',
              date: '2026-09-03',
              type: TransactionType.expense,
              amount: 20,
              categoryId: 'transport'),
          FinanceTransaction(
              id: 'oct-food-tx',
              date: '2026-10-02',
              type: TransactionType.expense,
              amount: 90,
              categoryId: 'food'),
        ],
      ),
    );

    final progress = store.progressForMonth('2026-09');

    expect(progress, hasLength(2));
    expect(
        progress.firstWhere((item) => item.budget.id == 'sep-food').spent, 80);
    expect(
        progress.firstWhere((item) => item.budget.id == 'sep-transport').spent,
        20);
  });

  test('budget store exposes only active categories for budget selection', () {
    final store = _store(
      initialState: _state().copyWith(categories: const [
        Category(id: 'active', name: '可用'),
        Category(id: 'archived', name: '已归档', active: false),
      ]),
    );

    expect(store.activeCategories.map((item) => item.id), ['active']);
  });

  test(
      'budget upsert survives a recreated session with its full queue operation',
      () async {
    final memory = _MemoryStore();
    final firstLocal = LocalRepository(memory);
    final firstSession =
        LocalStateSession(local: firstLocal, queue: SyncQueue());
    final store = _storeWithSession(firstSession, initialState: _state());

    await store.upsertBudget(
        id: 'budget-food', month: '2026-09', categoryId: 'food', limit: 800);

    expect(store.budgets.single.id, 'budget-food');
    expect(store.budgets.single.limit, 800);
    final queued = await firstSession.pendingOperations();
    expect(queued, hasLength(1));
    expect(queued.single.clientOpId, startsWith('budget:budget-food:'));
    expect(queued.single.entity, 'budgets');
    expect(queued.single.type, SyncOperationType.upsert);
    expect(queued.single.entityId, 'budget-food');
    expect(queued.single.payload, store.budgets.single.toJson());

    final recreatedSession = LocalStateSession(
      local: LocalRepository(memory),
      queue: SyncQueue(),
    );
    final restored =
        await _storeWithSession(recreatedSession).repository.load();
    expect(restored?.budgets.single.id, 'budget-food');
    expect((await recreatedSession.pendingOperations()).single.payload,
        store.budgets.single.toJson());
  });

  test(
      'budget alerts use warning exhausted and over thresholds and deduplicate',
      () async {
    final store = _store(
      initialState: _state(
        budgets: const [
          Budget(
              id: 'warning-budget',
              month: '2026-09',
              categoryId: 'food',
              limit: 100),
          Budget(
              id: 'exhausted-budget',
              month: '2026-09',
              categoryId: 'transport',
              limit: 100),
          Budget(
              id: 'over-budget',
              month: '2026-09',
              categoryId: 'other',
              limit: 100),
        ],
        transactions: const [
          FinanceTransaction(
              id: 'warning-tx',
              date: '2026-09-02',
              type: TransactionType.expense,
              amount: 80,
              categoryId: 'food'),
          FinanceTransaction(
              id: 'exhausted-tx',
              date: '2026-09-02',
              type: TransactionType.expense,
              amount: 100,
              categoryId: 'transport'),
          FinanceTransaction(
              id: 'over-tx',
              date: '2026-09-02',
              type: TransactionType.expense,
              amount: 101,
              categoryId: 'other'),
        ],
      ),
    );

    final first = await store.checkBudgetAlerts();
    final second = await store.checkBudgetAlerts();

    expect(
      first.map((alert) => '${alert.budget.id}:${alert.level.name}'),
      containsAll(<String>[
        'warning-budget:warning',
        'exhausted-budget:exhausted',
        'over-budget:over',
      ]),
    );
    expect(second, isEmpty);
    expect(store.alerts, isEmpty);
  });

  test('finance store rejects a budget store backed by a foreign session', () {
    final mainSession = LocalStateSession(
      local: LocalRepository(_MemoryStore()),
      queue: SyncQueue(),
    );
    final foreignSession = LocalStateSession(
      local: LocalRepository(_MemoryStore()),
      queue: SyncQueue(),
    );
    final repository = FinanceRepository(
      local: mainSession.local,
      queue: mainSession.queue,
      session: mainSession,
    );

    expect(
      () => FinanceStore(
        repository: repository,
        budgetStore: BudgetStore(
          repository: BudgetRepository(session: foreignSession),
        ),
      ),
      throwsArgumentError,
    );
  });

  test('finance repository exposes the budget repository on the shared session',
      () {
    final queue = SyncQueue();
    final session =
        LocalStateSession(local: LocalRepository(_MemoryStore()), queue: queue);
    final repository = FinanceRepository(
      local: session.local,
      queue: queue,
      session: session,
    );

    expect(repository.budgetRepository.session, same(session));
  });

  test('budget view adopts ledger mutations from the shared finance state',
      () async {
    final initial = _state(
      budgets: const [
        Budget(
            id: 'food-budget',
            month: '2026-09',
            categoryId: 'food',
            limit: 100),
      ],
    );
    final local = LocalRepository(_MemoryStore());
    final repository = FinanceRepository(local: local, queue: SyncQueue());
    final finance = FinanceStore(repository: repository, initialState: initial);

    await finance.addTransaction(const FinanceTransaction(
      id: 'food-expense',
      date: '2026-09-02',
      type: TransactionType.expense,
      amount: 80,
      categoryId: 'food',
    ));

    expect(finance.budget.progress.single.spent, 80);
  });
}
