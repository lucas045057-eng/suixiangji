import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wealthmate_flutter/core/database/local_state_session.dart';
import 'package:wealthmate_flutter/data/finance_repository.dart';
import 'package:wealthmate_flutter/data/local_repository.dart';
import 'package:wealthmate_flutter/data/sync_queue.dart';
import 'package:wealthmate_flutter/domain/models.dart';
import 'package:wealthmate_flutter/features/ledger/data/ledger_repository.dart';
import 'package:wealthmate_flutter/features/ledger/domain/ledger_rules.dart';
import 'package:wealthmate_flutter/features/ledger/state/ledger_store.dart';
import 'package:wealthmate_flutter/state/finance_store.dart';
import 'package:wealthmate_flutter/ui/dashboard_page.dart';
import 'package:wealthmate_flutter/ui/ledger_page.dart';
import 'package:wealthmate_flutter/ui/theme.dart';
import 'package:wealthmate_flutter/ui/transaction_detail_page.dart';
import 'package:wealthmate_flutter/ui/widgets/ui_helpers.dart';

class _Memory implements KeyValueStore {
  @override
  Future<String?> read(String key) async => null;

  @override
  Future<void> write(String key, String value) async {}
}

LedgerStore ledgerStore(List<FinanceTransaction> transactions) {
  final session =
      LocalStateSession(local: LocalRepository(_Memory()), queue: SyncQueue());
  return LedgerStore(
    repository: LedgerRepository(session: session),
    initialState: FinanceState(
      currentMonth: '2026-10',
      defaultAccountId: 'alipay',
      accounts: const [
        Account(id: 'alipay', name: '支付宝', type: AccountType.asset)
      ],
      categories: const [Category(id: 'food', name: '餐饮')],
      transactions: transactions,
    ),
  );
}

FinanceTransaction entry({
  required String id,
  String date = '2026-10-30',
  String? occurredAt,
  TransactionType type = TransactionType.expense,
  double amount = 12,
}) =>
    FinanceTransaction(
      id: id,
      date: date,
      occurredAt: occurredAt,
      type: type,
      amount: amount,
      categoryId: 'food',
      accountId: 'alipay',
      note: '咖啡',
      cnyAmount: amount,
      exchangeRate: 1,
    );

void main() {
  test('recordedTime hides the midnight placeholder', () {
    expect(recordedTime('2026-10-30T14:32:00'), '14:32');
    expect(recordedTime('2026-10-30T00:00:00'), isNull);
    expect(recordedTime('2026-10-30T00:00:00Z'), isNull);
    expect(recordedTime(null), isNull);
    expect(recordedTime(''), isNull);
  });

  test('ledgerDate adds the year only across years', () {
    final now = DateTime(2026, 10, 30);
    expect(ledgerDate('2026-10-30', now: now), '10月30日');
    expect(ledgerDate('2025-12-31', now: now), '2025年12月31日');
    expect(ledgerFullDate('2026-10-30'), '2026年10月30日');
  });

  test('new transactions keep a real clock only when dated today', () {
    final clock = DateTime(2026, 10, 30, 14, 32);
    expect(LedgerRules.occurredAtFor('2026-10-30', clock),
        '2026-10-30T14:32:00');
    expect(LedgerRules.occurredAtFor('2026-10-28', clock),
        '2026-10-28T00:00:00');
  });

  testWidgets('ledger rows show the date and the recorded time', (tester) async {
    final ledger = ledgerStore([
      entry(id: 'a', occurredAt: '2026-10-30T14:32:00'),
      entry(id: 'b', occurredAt: '2026-10-28T00:00:00', date: '2026-10-28'),
    ]);
    await tester.pumpWidget(MaterialApp(
        theme: wealthMateTheme(), home: Scaffold(body: LedgerPage(ledger: ledger))));
    await tester.pumpAndSettle();

    expect(find.textContaining('10月30日 14:32'), findsOneWidget);
    // A back-dated record has no clock: show the date, never a fake 00:00.
    expect(find.textContaining('10月28日'), findsOneWidget);
    expect(find.textContaining('00:00'), findsNothing);
  });

  testWidgets('detail shows the full date with its time', (tester) async {
    final timed = entry(id: 'a', occurredAt: '2026-10-30T14:32:00');
    final ledger = ledgerStore([timed]);
    await tester.pumpWidget(MaterialApp(
        theme: wealthMateTheme(),
        home: TransactionDetailPage(ledger: ledger, transaction: timed)));
    await tester.pumpAndSettle();

    expect(find.text('2026年10月30日 14:32'), findsOneWidget);
  });

  testWidgets('detail marks a record without a clock time', (tester) async {
    final dated = entry(id: 'b', occurredAt: '2026-10-28T00:00:00',
        date: '2026-10-28');
    final ledger = ledgerStore([dated]);
    await tester.pumpWidget(MaterialApp(
        theme: wealthMateTheme(),
        home: TransactionDetailPage(ledger: ledger, transaction: dated)));
    await tester.pumpAndSettle();

    expect(find.text('2026年10月28日（时间未记录）'), findsOneWidget);
  });

  testWidgets('savings rate card shows a percentage, not a currency amount',
      (tester) async {
    final store = FinanceStore(
      repository: FinanceRepository(
          local: LocalRepository(_Memory()), queue: SyncQueue()),
      initialState: FinanceState(
        currentMonth: '2026-10',
        defaultAccountId: 'alipay',
        accounts: const [
          Account(id: 'alipay', name: '支付宝', type: AccountType.asset)
        ],
        categories: const [Category(id: 'food', name: '餐饮')],
        transactions: [
          entry(id: 'i', type: TransactionType.income, amount: 1000),
          entry(id: 'e', amount: 400),
        ],
      ),
    );
    await tester.pumpWidget(MaterialApp(
        theme: wealthMateTheme(),
        home: DashboardPage(
          ledger: store.ledger,
          budgetAlerts: store.budgetAlerts,
          draft: store.draft,
          isDemoMode: store.isDemoMode,
          message: store.message,
          onSync: store.sync,
          onUpdateDraft: store.updateDraft,
          onConfirmDraft: store.confirmDraft,
          openComposer: (_, {smart = false}) {},
          openBudgets: () {},
        )));
    await tester.pumpAndSettle();

    expect(find.text('60%'), findsOneWidget);
    expect(find.text('¥60'), findsNothing);
    // The money cards keep the currency format.
    expect(find.text('¥1000'), findsWidgets);
    expect(find.text('¥400'), findsWidgets);
  });
}
