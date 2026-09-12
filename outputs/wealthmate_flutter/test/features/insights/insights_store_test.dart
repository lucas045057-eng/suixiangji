import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wealthmate_flutter/core/database/local_state_session.dart';
import 'package:wealthmate_flutter/data/local_repository.dart';
import 'package:wealthmate_flutter/data/sync_queue.dart';
import 'package:wealthmate_flutter/domain/models.dart';
import 'package:wealthmate_flutter/features/insights/data/insights_repository.dart';
import 'package:wealthmate_flutter/features/insights/domain/insight_rules.dart';
import 'package:wealthmate_flutter/features/insights/state/insights_store.dart';

class InsightsMemory implements KeyValueStore {
  final Map<String, String> values = <String, String>{};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }
}

FinanceState insightState({
  List<Account> accounts = const <Account>[],
  List<FinanceTransaction> transactions = const <FinanceTransaction>[],
  List<Budget> budgets = const <Budget>[],
  List<Goal> goals = const <Goal>[],
}) {
  return FinanceState(
    currentMonth: '2026-09',
    accounts: accounts,
    transactions: transactions,
    budgets: budgets,
    goals: goals,
    categories: const <Category>[
      Category(id: 'food', name: '餐饮'),
      Category(id: 'transport', name: '交通'),
    ],
  );
}

FinanceTransaction insightTx({
  required String id,
  required TransactionType type,
  required double amount,
  String date = '2026-09-01',
  String? occurredAt,
  String? categoryId,
  String? accountId,
  String currency = 'CNY',
  double? cnyAmount,
  String? deletedAt,
}) {
  return FinanceTransaction(
    id: id,
    date: date,
    occurredAt: occurredAt,
    type: type,
    amount: amount,
    categoryId: categoryId,
    accountId: accountId,
    currency: currency,
    cnyAmount: cnyAmount,
    deletedAt: deletedAt,
  );
}

void main() {
  test('InsightRules zero-fills daily and multi-day expense series', () {
    final state = insightState(
      transactions: <FinanceTransaction>[
        insightTx(
          id: 'morning',
          type: TransactionType.expense,
          amount: 12,
          date: '2026-09-03',
          occurredAt: '2026-09-03T09:20:00+08:00',
        ),
      ],
    );

    final day = InsightRules.periodExpenseSeries(
      state,
      DateTimeRange(start: DateTime(2026, 9, 3), end: DateTime(2026, 9, 3)),
    );
    final days = InsightRules.periodExpenseSeries(
      state,
      DateTimeRange(start: DateTime(2026, 9, 1), end: DateTime(2026, 9, 3)),
    );

    expect(day, hasLength(24));
    expect(day[9].expense, 12);
    expect(day[8].expense, 0);
    expect(days, hasLength(3));
    expect(days.map((point) => point.expense), <double>[0, 0, 12]);
  });

  test('InsightRules aggregates converted expenses by category and account', () {
    final state = insightState(
      transactions: <FinanceTransaction>[
        insightTx(
          id: 'food-1',
          type: TransactionType.expense,
          amount: 30,
          categoryId: 'food',
          accountId: 'cash',
        ),
        insightTx(
          id: 'food-2',
          type: TransactionType.expense,
          amount: 20,
          categoryId: 'food',
          accountId: 'bank',
          date: '2026-09-02',
        ),
        insightTx(
          id: 'pending',
          type: TransactionType.expense,
          amount: 99,
          currency: 'USD',
          categoryId: 'food',
          accountId: 'cash',
        ),
        insightTx(
          id: 'deleted',
          type: TransactionType.expense,
          amount: 100,
          categoryId: 'transport',
          deletedAt: '2026-09-04T00:00:00Z',
        ),
      ],
    );
    final range = DateTimeRange(
      start: DateTime(2026, 9, 1),
      end: DateTime(2026, 9, 3),
    );

    expect(InsightRules.expenseByCategory(state, range), <String, double>{
      'food': 50,
    });
    expect(InsightRules.expenseByAccount(state, range), <String, double>{
      'cash': 30,
      'bank': 20,
    });
  });

  test('InsightRules preserves savings, budget, wealth, and missing FX metrics', () {
    final state = insightState(
      accounts: const <Account>[
        Account(
          id: 'asset',
          name: '现金',
          type: AccountType.asset,
          openingBalance: 100,
          isLiquid: true,
        ),
        Account(
          id: 'liability',
          name: '信用卡',
          type: AccountType.liability,
          openingBalance: 200,
        ),
      ],
      transactions: <FinanceTransaction>[
        insightTx(
          id: 'income',
          type: TransactionType.income,
          amount: 1000,
          accountId: 'asset',
          categoryId: 'food',
        ),
        insightTx(
          id: 'expense',
          type: TransactionType.expense,
          amount: 200,
          accountId: 'liability',
          categoryId: 'food',
        ),
        insightTx(
          id: 'missing-fx',
          type: TransactionType.expense,
          amount: 10,
          currency: 'USD',
          accountId: 'asset',
          categoryId: 'food',
        ),
      ],
      budgets: const <Budget>[
        Budget(id: 'food-budget', month: '2026-09', categoryId: 'food', limit: 250),
      ],
      goals: const <Goal>[
        Goal(id: 'emergency', name: '应急金', target: 1000, liquidAccountIds: <String>['asset']),
      ],
    );

    final metrics = InsightRules.deriveMetrics(state, '2026-09');

    expect(metrics.income, 1000);
    expect(metrics.expense, 200);
    expect(metrics.savings, 800);
    expect(metrics.savingsRate, .8);
    expect(metrics.budgetProgress.single.spent, 200);
    expect(metrics.assetTotal, 1100);
    expect(metrics.liabilityTotal, 400);
    expect(metrics.netWorth, 700);
    expect(metrics.emergencyFund, 1100);
    expect(metrics.goalProgress, 1);
    expect(metrics.pendingConversionCount, 1);
  });

  test('InsightsStore invalidates derived metrics after a new snapshot', () {
    final initial = insightState(
      transactions: <FinanceTransaction>[
        insightTx(
          id: 'expense',
          type: TransactionType.expense,
          amount: 20,
          categoryId: 'food',
        ),
      ],
    );
    final store = InsightsStore(
      repository: InsightsRepository(
        session: LocalStateSession(
          local: LocalRepository(InsightsMemory()),
          queue: SyncQueue(),
        ),
      ),
      initialState: initial,
    );

    expect(store.metrics.expense, 20);
    store.adoptState(initial.copyWith(transactions: <FinanceTransaction>[
      insightTx(
        id: 'expense',
        type: TransactionType.expense,
        amount: 35,
        categoryId: 'food',
      ),
    ]));

    expect(store.metrics.expense, 35);
  });

  test('InsightsStore generates a deterministic local report without queue writes', () async {
    final memory = InsightsMemory();
    final session = LocalStateSession(
      local: LocalRepository(memory),
      queue: SyncQueue(),
    );
    final store = InsightsStore(
      repository: InsightsRepository(session: session),
      initialState: insightState(
        transactions: <FinanceTransaction>[
          insightTx(
            id: 'expense',
            type: TransactionType.expense,
            amount: 32,
            categoryId: 'food',
          ),
        ],
      ),
    );

    await store.generateMonthlyReport();

    final saved = await session.load();
    expect(saved?.reports.single.summary, contains('32'));
    expect(await session.pendingOperations(), isEmpty);
    expect(saved?.transactions, hasLength(1));
  });
}
