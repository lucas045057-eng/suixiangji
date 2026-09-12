import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wealthmate_flutter/data/finance_repository.dart';
import 'package:wealthmate_flutter/data/local_repository.dart';
import 'package:wealthmate_flutter/data/sync_queue.dart';
import 'package:wealthmate_flutter/domain/models.dart';
import 'package:wealthmate_flutter/state/finance_store.dart';
import 'package:wealthmate_flutter/ui/dashboard_page.dart';
import 'package:wealthmate_flutter/ui/theme.dart';
import 'package:wealthmate_flutter/ui/transaction_detail_page.dart';
import 'package:wealthmate_flutter/ui/widgets/transaction_form.dart';

class TransactionConversionMemory implements KeyValueStore {
  final Map<String, String> values = {};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;
}

const cnyAccount = Account(
  id: 'wallet',
  name: '测试账户',
  type: AccountType.asset,
);

const cnyCategory = Category(id: 'food', name: '餐饮');

FinanceTransaction cnyTransaction({
  double amount = 91.91,
  double? cnyAmount,
  String note = '旧备注',
}) {
  return FinanceTransaction(
    id: 'tx-cny-conversion',
    date: '2026-09-07',
    type: TransactionType.expense,
    amount: amount,
    currency: 'CNY',
    cnyAmount: cnyAmount ?? amount,
    exchangeRate: 1.0,
    exchangeRateDate: '2026-09-07',
    exchangeRateSource: 'CNY fixed rate',
    conversionStatus: 'ready',
    categoryId: 'food',
    accountId: 'wallet',
    note: note,
    clientOpId: 'create-cny-conversion',
    serverVersion: 27,
    updatedAt: '2026-09-07T10:00:00Z',
  );
}

const usdTransaction = FinanceTransaction(
  id: 'tx-foreign-conversion',
  date: '2026-09-07',
  type: TransactionType.expense,
  amount: 10,
  currency: 'USD',
  cnyAmount: 72,
  exchangeRate: 7.2,
  exchangeRateDate: '2026-09-07',
  exchangeRateSource: 'Frankfurter',
  conversionStatus: 'ready',
  categoryId: 'food',
  accountId: 'wallet',
  note: '美元旧备注',
  clientOpId: 'create-foreign-conversion',
  serverVersion: 27,
  updatedAt: '2026-09-07T10:00:00Z',
);

FinanceStore conversionStore(
  FinanceTransaction transaction, {
  TransactionConversionMemory? memory,
}) {
  return FinanceStore(
    repository: FinanceRepository(
      local: LocalRepository(memory ?? TransactionConversionMemory()),
      queue: SyncQueue(),
    ),
    initialState: FinanceState(
      currentMonth: '2026-09',
      accounts: const [cnyAccount],
      categories: const [cnyCategory],
      transactions: [transaction],
    ),
  );
}

Future<FinanceTransaction> editTransaction(
  WidgetTester tester,
  FinanceStore store, {
  String? amount,
  String? note,
}) async {
  await tester.pumpWidget(MaterialApp(
    theme: wealthMateTheme(),
    home: TransactionDetailPage(
      store: store,
      transaction: store.state.transactions.single,
    ),
  ));
  await tester.tap(find.byTooltip('编辑'));
  await tester.pumpAndSettle();

  final fields = find.byType(TextFormField);
  expect(fields, findsNWidgets(4));
  if (amount != null) await tester.enterText(fields.at(0), amount);
  if (note != null) await tester.enterText(fields.at(3), note);
  final saveButton = find.text('保存修改');
  await tester.ensureVisible(saveButton);
  await tester.tap(saveButton);
  await tester.pumpAndSettle();
  return store.state.transactions.single;
}

Future<FinanceTransaction> createCnyTransaction(
    WidgetTester tester, FinanceStore store, String amount) async {
  await tester.pumpWidget(MaterialApp(
    key: ValueKey('create-$amount'),
    theme: wealthMateTheme(),
    home: Scaffold(body: TransactionForm(store: store)),
  ));
  final fields = find.byType(TextFormField);
  await tester.enterText(fields.at(0), amount);
  await tester.enterText(fields.at(3), 'CNY create $amount');
  final saveButton = find.text('确认入账');
  await tester.ensureVisible(saveButton);
  await tester.tap(saveButton);
  await tester.pumpAndSettle();
  return store.state.transactions.last;
}

void main() {
  testWidgets('RED-01 CNY edit recalculates cnyAmount from the new amount',
      (tester) async {
    final store = conversionStore(cnyTransaction());

    final saved = await editTransaction(tester, store, amount: '92.92');

    expect(saved.amount, 92.92);
    expect(saved.cnyAmount, 92.92);
    expect(saved.exchangeRate, 1.0);
  });

  testWidgets('RED-02 dashboard derived expense uses the edited CNY amount',
      (tester) async {
    final store = conversionStore(cnyTransaction());

    await editTransaction(tester, store, amount: '92.92');
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
      ),
    ));

    expect(store.metrics.expense, 92.92);
    expect(find.text('¥92.92'), findsAtLeastNWidgets(1));
    expect(find.text('¥91.91'), findsNothing);
  });

  testWidgets('RED-03 edit queue payload carries the recalculated CNY amount',
      (tester) async {
    final store = conversionStore(cnyTransaction());

    await editTransaction(tester, store, amount: '92.92');

    final operation = store.repository.queue.pending().single;
    expect(operation.payload['amount'], 92.92);
    expect(operation.payload['cny_amount'], 92.92);
  });

  testWidgets('RED-04 persisted state round-trips the recalculated CNY amount',
      (tester) async {
    final memory = TransactionConversionMemory();
    final store = conversionStore(cnyTransaction(), memory: memory);

    await editTransaction(tester, store, amount: '92.92');

    final restored = await FinanceRepository(
      local: LocalRepository(memory),
      queue: SyncQueue(),
    ).load();
    expect(restored, isNotNull);
    expect(restored!.transactions.single.amount, 92.92);
    expect(restored.transactions.single.cnyAmount, 92.92);
  });

  testWidgets(
      'RED-05 saving the same amount repairs an existing stale CNY derived value',
      (tester) async {
    final store = conversionStore(cnyTransaction(
      amount: 92.92,
      cnyAmount: 91.91,
    ));

    final saved = await editTransaction(tester, store, amount: '92.92');

    expect(saved.amount, 92.92);
    expect(saved.cnyAmount, 92.92);
  });

  testWidgets('RED-06 note-only save does not corrupt a correct CNY amount',
      (tester) async {
    final store = conversionStore(cnyTransaction(amount: 92.92));

    final saved = await editTransaction(
      tester,
      store,
      note: '只修改备注',
    );

    expect(saved.amount, 92.92);
    expect(saved.cnyAmount, 92.92);
    expect(saved.note, '只修改备注');
  });

  testWidgets('RED-07 every CNY manual create keeps cnyAmount equal to amount',
      (tester) async {
    final store = conversionStore(cnyTransaction());

    final first = await createCnyTransaction(tester, store, '12.34');
    expect(first.currency, 'CNY');
    expect(first.amount, 12.34);
    expect(first.cnyAmount, 12.34);
    expect(first.exchangeRate, 1.0);

    final second = await createCnyTransaction(tester, store, '56.78');
    expect(second.currency, 'CNY');
    expect(second.amount, 56.78);
    expect(second.cnyAmount, 56.78);
    expect(second.exchangeRate, 1.0);
  });

  testWidgets('RED-08 foreign edit recalculates using the existing rate',
      (tester) async {
    final store = conversionStore(usdTransaction);

    final saved = await editTransaction(tester, store, amount: '20');

    expect(saved.amount, 20);
    expect(saved.currency, 'USD');
    expect(saved.cnyAmount, 144.0);
    expect(saved.exchangeRate, 7.2);
  });

  testWidgets('RED-09 edit preserves identity and conversion metadata',
      (tester) async {
    final store = conversionStore(usdTransaction);

    final saved = await editTransaction(
      tester,
      store,
      amount: '20',
      note: '保留元数据',
    );

    expect(saved.id, usdTransaction.id);
    expect(saved.serverVersion, 27);
    expect(saved.accountId, usdTransaction.accountId);
    expect(saved.categoryId, usdTransaction.categoryId);
    expect(saved.exchangeRate, 7.2);
    expect(saved.exchangeRateDate, '2026-09-07');
    expect(saved.exchangeRateSource, 'Frankfurter');
    expect(saved.conversionStatus, 'ready');
  });
}
