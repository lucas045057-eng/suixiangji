import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wealthmate_flutter/data/finance_repository.dart';
import 'package:wealthmate_flutter/data/local_repository.dart';
import 'package:wealthmate_flutter/data/sync_queue.dart';
import 'package:wealthmate_flutter/domain/models.dart';
import 'package:wealthmate_flutter/state/finance_store.dart';
import 'package:wealthmate_flutter/ui/dashboard_page.dart';
import 'package:wealthmate_flutter/ui/theme.dart';
import 'package:wealthmate_flutter/ui/widgets/transaction_form.dart';

class TransactionMemory implements KeyValueStore {
  @override
  Future<String?> read(String key) async => null;

  @override
  Future<void> write(String key, String value) async {}
}

FinanceStore transactionStore() {
  return FinanceStore(
    repository: FinanceRepository(
        local: LocalRepository(TransactionMemory()), queue: SyncQueue()),
    initialState: FinanceState(
      currentMonth: '2026-09',
      defaultAccountId: 'alipay',
      accounts: const [
        Account(id: 'alipay', name: '支付宝', type: AccountType.asset)
      ],
      categories: const [Category(id: 'food', name: '餐饮')],
    ),
  );
}

void main() {
  testWidgets('dashboard renders the cash-flow metrics', (tester) async {
    final store = transactionStore();
    await tester.pumpWidget(MaterialApp(
        theme: wealthMateTheme(),
        home: DashboardPage(store: store, openBudgets: () {})));

    expect(find.text('本月收入'), findsOneWidget);
    expect(find.text('本月支出'), findsOneWidget);
    expect(find.text('当前净资产'), findsOneWidget);
  });

  testWidgets('natural language composer keeps a draft until confirmation',
      (tester) async {
    final store = transactionStore();
    await tester.pumpWidget(MaterialApp(
        theme: wealthMateTheme(),
        home: Scaffold(body: TransactionForm(store: store, smartMode: true))));

    await tester.enterText(find.byType(TextFormField), '今天中午外卖 32 元，支付宝');
    await tester.tap(find.text('生成待确认草稿'));
    await tester.pumpAndSettle();

    expect(store.state.transactions, isEmpty);
    expect(find.text('已整理成待确认草稿'), findsOneWidget);
    expect(find.text('修改'), findsOneWidget);
    expect(find.text('确认入账'), findsOneWidget);

    await tester.tap(find.text('修改'));
    await tester.pumpAndSettle();

    expect(find.text('修改快捷记'), findsOneWidget);

    await tester.tap(find.text('保存修改'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认入账'));
    await tester.pumpAndSettle();

    expect(store.state.transactions, hasLength(1));
  });

  testWidgets(
      'recent transaction opens a detail view with time and conversion fields',
      (tester) async {
    final store = transactionStore();
    await store.addTransaction(const FinanceTransaction(
        id: 'detail-tx',
        date: '2026-09-03',
        occurredAt: '2026-09-03T18:42:00+08:00',
        type: TransactionType.expense,
        amount: 32,
        currency: 'USD',
        cnyAmount: 230.4,
        exchangeRate: 7.2,
        exchangeRateDate: '2026-09-03',
        exchangeRateSource: 'Frankfurter',
        categoryId: 'food',
        accountId: 'alipay',
        note: '晚餐'));
    await tester.pumpWidget(MaterialApp(
        theme: wealthMateTheme(),
        home: DashboardPage(store: store, openBudgets: () {})));

    await tester.scrollUntilVisible(find.text('晚餐'), 400,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('晚餐'));
    await tester.pumpAndSettle();

    expect(find.text('账目详情'), findsOneWidget);
    expect(find.text('2026-09-03 18:42'), findsOneWidget);
    expect(find.textContaining('32'), findsWidgets);
    expect(find.textContaining('230.4'), findsWidgets);
    expect(find.textContaining('Frankfurter'), findsOneWidget);
  });
}
