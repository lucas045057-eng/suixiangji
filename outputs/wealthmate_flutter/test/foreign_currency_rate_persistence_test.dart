import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wealthmate_flutter/data/finance_repository.dart';
import 'package:wealthmate_flutter/data/local_repository.dart';
import 'package:wealthmate_flutter/data/sync_queue.dart';
import 'package:wealthmate_flutter/domain/models.dart';
import 'package:wealthmate_flutter/state/finance_store.dart';
import 'package:wealthmate_flutter/ui/dashboard_page.dart';
import 'package:wealthmate_flutter/ui/theme.dart';
import 'package:wealthmate_flutter/ui/wealth_page.dart';

import 'core/two_device_sync_test.dart' as harness;

class _Memory implements KeyValueStore {
  final Map<String, String> values = {};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;
}

const _frozenUsdAccount = Account(
  id: 'usd',
  name: '美元账户',
  type: AccountType.asset,
  currency: 'USD',
  openingBalance: 100,
  openingCnyAmount: 700,
  exchangeRate: 7,
  exchangeRateDate: '2026-09-01',
  exchangeRateSource: '用户凭证',
);

const _pendingUsdExpense = FinanceTransaction(
  id: 'usd-expense',
  date: '2026-09-01',
  type: TransactionType.expense,
  amount: 10,
  currency: 'USD',
  accountId: 'usd',
  conversionStatus: 'pending',
);

const _state = FinanceState(
  currentMonth: '2026-09',
  accounts: [_frozenUsdAccount],
  transactions: [_pendingUsdExpense],
);

FinanceStore _store(FinanceState state, {KeyValueStore? memory}) {
  return FinanceStore(
    repository: FinanceRepository(
      local: LocalRepository(memory ?? _Memory()),
      queue: SyncQueue(),
    ),
    initialState: state,
  );
}

void main() {
  test('saving a rate converts rateless pending entries and persists them',
      () async {
    final memory = _Memory();
    final store = _store(_state, memory: memory);
    addTearDown(store.dispose);

    await store.assets.saveManualExchangeRate(
        baseCurrency: 'USD', rate: 7.2, rateDate: '2026-10-09', source: '用户凭证');

    final transaction = store.state.transactions.single;
    expect(transaction.cnyAmount, 72);
    expect(transaction.exchangeRate, 7.2);
    expect(transaction.exchangeRateDate, '2026-10-09');
    expect(transaction.conversionStatus, 'ready');
    expect(transaction.clientOpId, isNot('usd-expense'));

    final balance = store.assets.accountBalances.single;
    expect(balance.balance, 628);
    expect(balance.isPending, isFalse);
    expect(store.assets.message, contains('已按该汇率折算 1 笔待换算账目'));

    // A converted entry is a real edit that must reach the server. Without
    // this operation the next full pull would return it as pending again.
    final queued = store.repository.queue.pending();
    expect(queued, hasLength(1));
    expect(queued.single.entity, 'transactions');
    expect(queued.single.entityId, 'usd-expense');
    expect(queued.single.clientOpId, transaction.clientOpId);
    expect(queued.single.payload['cny_amount'], 72);

    final persisted = (await LocalRepository(memory).load())!;
    expect(persisted.transactions.single.cnyAmount, 72);
    expect(persisted.transactions.single.conversionStatus, 'ready');

    // "Restart" from the same persisted partition: no second conversion.
    final restarted = _store(persisted, memory: memory);
    addTearDown(restarted.dispose);
    expect(restarted.assets.accountBalances.single.balance, 628);
    expect(restarted.assets.accountBalances.single.isPending, isFalse);
  });

  test(
      'first conversion writes both account and transaction snapshots and survives pull',
      () async {
    const account = Account(
        id: 'usd',
        name: '美元账户',
        type: AccountType.asset,
        currency: 'USD',
        openingBalance: 100,
        serverVersion: 1);
    const transaction = FinanceTransaction(
        id: 'usd-expense',
        date: '2026-09-01',
        type: TransactionType.expense,
        amount: 10,
        currency: 'USD',
        accountId: 'usd',
        conversionStatus: 'pending',
        serverVersion: 1);
    const initial = FinanceState(
      currentMonth: '2026-09',
      accounts: [account],
      categories: [Category(id: 'food', name: '餐饮')],
      transactions: [transaction],
      syncState: SyncState(serverVersion: 2),
    );

    final server = harness.MemorySyncServer();
    server.records['accounts']!['usd'] = {
      ...account.toJson(),
      'server_version': 1,
    };
    server.records['transactions']!['usd-expense'] = {
      ...transaction.toJson(),
      'server_version': 1,
    };
    final memory = harness.SyncMemory();
    final store =
        await harness.syncDevice(server, memory: memory, initial: initial);
    addTearDown(store.dispose);

    await store.assets.saveManualExchangeRate(
        baseCurrency: 'USD', rate: 7, rateDate: '2026-10-09', source: '用户凭证');

    expect(store.assets.accounts.single.openingCnyAmount, 700);
    expect(store.state.transactions.single.cnyAmount, 70);
    final queued = store.repository.queue.pending();
    expect(queued.map((op) => op.entity),
        containsAll(['accounts', 'transactions']));
    expect(
        queued
            .singleWhere((op) => op.entity == 'accounts')
            .payload['opening_cny_amount'],
        700);
    expect(
        queued
            .singleWhere((op) => op.entity == 'transactions')
            .payload['cny_amount'],
        70);

    await store.sync();

    expect(server.records['accounts']!['usd']!['opening_cny_amount'], 700);
    expect(server.records['transactions']!['usd-expense']!['cny_amount'], 70);

    final restarted = await harness.syncDevice(server, memory: memory);
    addTearDown(restarted.dispose);
    await restarted.sync();
    expect(
        restarted.assets.accounts
            .singleWhere((a) => a.id == 'usd')
            .openingCnyAmount,
        700);
    expect(restarted.state.transactions.single.cnyAmount, 70);
    expect(
        restarted.assets.accountBalances
            .singleWhere((item) => item.account.id == 'usd')
            .isPending,
        isFalse);

    // A brand-new device learns the converted values from the server.
    final fresh = await harness.syncDevice(
      server,
      memory: harness.SyncMemory(),
      initial: const FinanceState(syncState: SyncState(serverVersion: 0)),
    );
    addTearDown(fresh.dispose);
    await fresh.sync();
    final freshUsd = fresh.assets.accounts.singleWhere((a) => a.id == 'usd');
    expect(freshUsd.openingCnyAmount, 700);
    expect(fresh.state.transactions.single.cnyAmount, 70);
    final freshBalance = fresh.assets.accountBalances
        .singleWhere((item) => item.account.id == 'usd');
    expect(freshBalance.balance, 630);
    expect(freshBalance.isPending, isFalse);
  });

  test('a later rate does not revalue converted entries or frozen openings',
      () async {
    final memory = _Memory();
    final store = _store(_state, memory: memory);
    addTearDown(store.dispose);

    await store.assets.saveManualExchangeRate(
        baseCurrency: 'USD', rate: 7.2, rateDate: '2026-10-09', source: '用户凭证');
    store.repository.queue.replace(const []);
    await store.assets.saveManualExchangeRate(
        baseCurrency: 'USD', rate: 8, rateDate: '2026-10-10', source: '用户凭证');

    final account = store.assets.accounts.single;
    expect(account.openingCnyAmount, 700);
    expect(account.exchangeRate, 7);
    final transaction = store.state.transactions.single;
    expect(transaction.cnyAmount, 72);
    expect(transaction.exchangeRate, 7.2);
    expect(store.repository.queue.pending(), isEmpty);
    expect(store.assets.message, contains('不会被重估'));
  });

  testWidgets('home and wealth show the converted amount immediately',
      (tester) async {
    final store = _store(_state);
    addTearDown(store.dispose);

    await tester.pumpWidget(MaterialApp(
      theme: wealthMateTheme(),
      home: Scaffold(
        body: DashboardPage(
          ledger: store.ledger,
          insights: store.insights,
          isDemoMode: true,
          onSync: store.sync,
          openComposer: (_, {smart = false}) {},
          openBudgets: () {},
        ),
      ),
    ));
    await tester.pump();
    // An unconverted entry makes the net worth incomplete, never zero.
    expect(find.text('当前净资产'), findsOneWidget);
    expect(find.text('待换算'), findsWidgets);

    await store.assets.saveManualExchangeRate(
        baseCurrency: 'USD', rate: 7.2, rateDate: '2026-10-09', source: '用户凭证');
    await tester.pump();

    // 700 frozen opening − 10 USD × 7.2, rendered on the same frame.
    expect(find.text('¥628'), findsWidgets);
    expect(find.text('待换算'), findsNothing);

    await tester.pumpWidget(MaterialApp(
      theme: wealthMateTheme(),
      home: Scaffold(
        body: WealthPage(store: store.assets, ledger: store.ledger),
      ),
    ));
    await tester.pump();

    expect(find.text('¥628'), findsWidgets);
    expect(find.textContaining('待换算'), findsNothing);
  });
}
