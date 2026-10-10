import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wealthmate_flutter/domain/models.dart';
import 'package:wealthmate_flutter/features/insights/domain/insight_rules.dart';
import 'package:wealthmate_flutter/features/budget/domain/budget_rules.dart'
    as budgets;
import 'package:wealthmate_flutter/features/budget/data/budget_repository.dart';
import 'package:wealthmate_flutter/features/budget/state/budget_store.dart';
import 'package:wealthmate_flutter/core/database/local_state_session.dart';
import 'package:wealthmate_flutter/data/local_repository.dart';
import 'package:wealthmate_flutter/data/sync_queue.dart';
import 'v105_assets_closure_test.dart' show Memory;
import 'package:wealthmate_flutter/domain/transaction_query.dart';
import 'package:wealthmate_flutter/data/finance_repository.dart';
import 'package:wealthmate_flutter/state/finance_store.dart';
import 'package:wealthmate_flutter/ui/stats_page.dart';
import 'package:wealthmate_flutter/ui/ledger_page.dart';
import 'package:wealthmate_flutter/ui/widgets/bar_chart.dart';
import 'package:wealthmate_flutter/ui/widgets/line_chart.dart';
import 'package:wealthmate_flutter/ui/widgets/pie_chart.dart';

const bills = [
  FinanceTransaction(
      id: 'meal',
      date: '2026-09-30',
      occurredAt: '2026-10-01T12:00:00',
      type: TransactionType.expense,
      amount: 16,
      categoryId: 'food'),
  FinanceTransaction(
      id: 'uncat',
      date: '2026-09-02',
      type: TransactionType.expense,
      amount: 4),
  FinanceTransaction(
      id: 'usd',
      date: '2026-09-03',
      type: TransactionType.expense,
      amount: 2,
      currency: 'USD',
      cnyAmount: 14,
      categoryId: 'food'),
  FinanceTransaction(
      id: 'pending',
      date: '2026-09-03',
      type: TransactionType.expense,
      amount: 2,
      currency: 'HKD',
      conversionStatus: 'pending'),
  FinanceTransaction(
      id: 'salary',
      date: '2026-09-01',
      type: TransactionType.income,
      amount: 1000),
  FinanceTransaction(
      id: 'refund',
      date: '2026-09-01',
      type: TransactionType.income,
      amount: 5,
      note: '退款'),
  FinanceTransaction(
      id: 'transfer',
      date: '2026-09-01',
      type: TransactionType.transfer,
      amount: 100),
  FinanceTransaction(
      id: 'deleted',
      date: '2026-09-01',
      type: TransactionType.expense,
      amount: 100,
      deletedAt: '2026-09-02'),
  FinanceTransaction(
      id: 'oct',
      date: '2026-10-01',
      type: TransactionType.expense,
      amount: 200),
];

void main() {
  testWidgets(
      'selected month charts and budget retain same future-dated bill scope',
      (tester) async {
    final store = FinanceStore(
        repository: FinanceRepository(
            local: LocalRepository(Memory()), queue: SyncQueue()),
        initialState:
            const FinanceState(currentMonth: '2026-10', transactions: [
          FinanceTransaction(
              id: 'today',
              date: '2026-10-09',
              type: TransactionType.expense,
              amount: 16),
          FinanceTransaction(
              id: 'future',
              date: '2026-10-30',
              type: TransactionType.expense,
              amount: 20)
        ], budgets: [
          Budget(
              id: 'total',
              month: '2026-10',
              categoryId: '__total__',
              limit: 100)
        ]));
    addTearDown(store.dispose);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: StatsPage(
                insights: store.insights,
                ledger: store.ledger,
                now: DateTime(2026, 10, 9)))));
    final values =
        tester.widget<WealthLineChart>(find.byType(WealthLineChart)).values;
    expect(values.fold<double>(0, (a, b) => a + b),
        budgets.progressForMonth(store.state, '2026-10').single.spent);
  });
  test('average uses selected elapsed days, leap months and future zero', () {
    expect(
        dailyAverage(90, DateTime(2026, 10, 1), DateTime(2026, 10, 31),
            DateTime(2026, 10, 9)),
        10);
    expect(
        dailyAverage(290, DateTime(2024, 2, 1), DateTime(2024, 2, 29),
            DateTime(2026, 10, 9)),
        10);
    expect(
        dailyAverage(50, DateTime(2027, 1, 1), DateTime(2027, 1, 31),
            DateTime(2026, 10, 9)),
        0);
    const state = FinanceState(transactions: bills);
    expect(
        TransactionQuery(
            start: DateTime(2026, 9, 1),
            end: DateTime(2026, 9, 30),
            type: TransactionType.expense,
            categoryIds: {'food'}).select(state).map((r) => r.id),
        ['meal', 'usd']);
  });
  testWidgets(
      'category chart opens exact dated ledger rows and returns to selected month',
      (tester) async {
    final store = FinanceStore(
        repository: FinanceRepository(
            local: LocalRepository(Memory()), queue: SyncQueue()),
        initialState: const FinanceState(
            currentMonth: '2026-09',
            categories: [Category(id: 'food', name: '餐饮')],
            transactions: bills));
    addTearDown(store.dispose);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: StatsPage(
                insights: store.insights,
                ledger: store.ledger,
                now: DateTime(2026, 10, 9)))));
    expect(find.byType(SpendingBarChart), findsNothing);
    expect(find.byType(ExpensePieChart), findsNothing);
    await tester.tap(find.text('柱状'));
    await tester.pumpAndSettle();
    expect(find.byType(WealthLineChart), findsNothing);
    await tester.scrollUntilVisible(find.text('分类支出柱状图'), 200);
    final categoryRow = find.descendant(
        of: find.byType(SpendingBarChart), matching: find.text('餐饮'));
    await tester.ensureVisible(categoryRow);
    await tester.tap(categoryRow);
    await tester.pumpAndSettle();
    expect(find.byType(LedgerPage), findsOneWidget);
    expect(find.text('2026-09-30 · 餐饮 · 请选择账户 · CNY'), findsOneWidget);
    expect(find.textContaining('2026-10-01'), findsNothing);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(StatsPage), findsOneWidget);
  });
  test(
      'charts, monthly metrics and total/category budget share transaction date and snapshot',
      () {
    const state = FinanceState(transactions: bills, budgets: [
      Budget(
          id: 'total', month: '2026-09', categoryId: '__total__', limit: 100),
      Budget(
          id: 'food-budget', month: '2026-09', categoryId: 'food', limit: 50),
    ]);
    final range =
        DateTimeRange(start: DateTime(2026, 9, 1), end: DateTime(2026, 9, 30));
    final chart = InsightRules.expenseByCategory(state, range);
    expect(chart['food'], 30);
    expect(chart['uncategorized'], 4);
    expect(
        InsightRules.periodExpenseSeries(state, range)
            .fold<double>(0, (s, p) => s + p.expense),
        34);
    final metrics = InsightRules.deriveMetrics(state, '2026-09');
    expect(metrics.expense, 34);
    expect(metrics.income, 1005); // refunds follow the existing income contract
    expect(metrics.pendingConversionCount, 1);
    final progress = budgets.progressForMonth(state, '2026-09');
    expect(progress.first.spent, 34);
    expect(progress.last.spent, 30);
  });

  test(
      'editing the same monthly total preserves identity and base sync version',
      () async {
    final memory = Memory();
    final queue = SyncQueue();
    final store = BudgetStore(
        repository: BudgetRepository(
            session: LocalStateSession(
                local: LocalRepository(memory), queue: queue)),
        initialState: const FinanceState(currentMonth: '2026-09', budgets: [
          Budget(
              id: 'total',
              month: '2026-09',
              categoryId: '__total__',
              limit: 100,
              serverVersion: 9)
        ]));
    await store.upsertBudget(
        month: '2026-09', categoryId: '__total__', limit: 200);
    expect(store.budgets.length, 1);
    expect(store.budgets.single.id, 'total');
    expect(queue.pending().single.payload['server_version'], 9);
    expect((await LocalRepository(memory).load())!.budgets.single.limit, 200);
  });
}
