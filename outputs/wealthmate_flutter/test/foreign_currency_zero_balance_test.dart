import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wealthmate_flutter/data/finance_repository.dart';
import 'package:wealthmate_flutter/data/local_repository.dart';
import 'package:wealthmate_flutter/data/sync_queue.dart';
import 'package:wealthmate_flutter/domain/finance_rules.dart';
import 'package:wealthmate_flutter/domain/models.dart';
import 'package:wealthmate_flutter/features/assets/domain/asset_rules.dart';
import 'package:wealthmate_flutter/state/finance_store.dart';
import 'package:wealthmate_flutter/ui/account_detail_page.dart';
import 'package:wealthmate_flutter/ui/dashboard_page.dart';
import 'package:wealthmate_flutter/ui/theme.dart';
import 'package:wealthmate_flutter/ui/wealth_page.dart';

class _Memory implements KeyValueStore {
  final Map<String, String> values = {};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;
}

FinanceStore _store(FinanceState state) {
  final store = FinanceStore(
    repository: FinanceRepository(
      local: LocalRepository(_Memory()),
      queue: SyncQueue(),
    ),
    initialState: state,
  );
  addTearDown(store.dispose);
  return store;
}

const _usdWithStoredRate = Account(
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

void main() {
  test('a foreign opening without any rate is pending, never a zero balance',
      () {
    const state = FinanceState(accounts: [
      Account(
          id: 'cash',
          name: '人民币',
          type: AccountType.asset,
          openingBalance: 1000),
      Account(
          id: 'usd',
          name: '美元账户',
          type: AccountType.asset,
          currency: 'USD',
          openingBalance: 100),
    ]);

    final balances = AssetRules.accountBalances(state, const []);
    final usd = balances.singleWhere((item) => item.account.id == 'usd');
    final cash = balances.singleWhere((item) => item.account.id == 'cash');

    // The partial value may be 0, but it is flagged as unknown rather than
    // reported as the account's real balance.
    expect(usd.balance, 0);
    expect(usd.isPending, isTrue);
    expect(usd.pendingConversionCount, 1);
    expect(cash.isPending, isFalse);

    final metrics = FinanceRules.deriveMetrics(state, '2026-09');
    expect(metrics.hasPendingBalances, isTrue);
    expect(metrics.pendingAccountCount, 1);
    // Totals remain the known partial sum; the UI labels them as pending.
    expect(metrics.netWorth, 1000);
  });

  test('a stored dated rate fills a missing opening snapshot without a refresh',
      () {
    const state = FinanceState(accounts: [
      Account(
          id: 'usd',
          name: '美元账户',
          type: AccountType.asset,
          currency: 'USD',
          openingBalance: 100,
          exchangeRate: 7,
          exchangeRateDate: '2026-09-01',
          exchangeRateSource: '用户凭证'),
    ]);

    final usd = AssetRules.accountBalances(state, const []).single;

    expect(usd.balance, 700);
    expect(usd.isPending, isFalse);
    expect(FinanceRules.deriveMetrics(state, '2026-09').netWorth, 700);
  });

  test('a rate refresh never revalues a frozen opening or history', () {
    const state = FinanceState(
      accounts: [_usdWithStoredRate],
      transactions: [
        FinanceTransaction(
          id: 'spent',
          date: '2026-09-02',
          type: TransactionType.expense,
          amount: 10,
          currency: 'USD',
          cnyAmount: 70,
          exchangeRate: 7,
          exchangeRateDate: '2026-09-01',
          accountId: 'usd',
        ),
      ],
    );

    final next = AssetRules.applyExchangeRate(
        state,
        const ExchangeRateSnapshot(
            baseCurrency: 'USD',
            rate: 8,
            rateDate: '2026-10-01',
            source: '刷新'));

    expect(next.accounts.single.openingCnyAmount, 700);
    final usd = AssetRules.accountBalances(next, next.transactions).single;
    expect(usd.balance, 630);
    expect(usd.isPending, isFalse);
  });

  test('a new foreign account freezes the newest stored rate immediately',
      () async {
    final store = _store(const FinanceState(exchangeRates: [
      ExchangeRateSnapshot(
          baseCurrency: 'USD', rate: 7, rateDate: '2026-09-01', source: '旧快照'),
      ExchangeRateSnapshot(
          baseCurrency: 'USD',
          rate: 7.5,
          rateDate: '2026-09-05',
          source: '新快照'),
    ]));

    await store.addAccount(
        name: '美元账户',
        type: AccountType.asset,
        currency: 'USD',
        openingBalance: 100);

    final account = store.assets.accounts.single;
    expect(account.openingCnyAmount, 750);
    expect(account.exchangeRate, 7.5);
    expect(account.exchangeRateDate, '2026-09-05');
    expect(account.exchangeRateSource, '新快照');
    expect(store.assets.accountBalances.single.isPending, isFalse);
    expect(store.assets.netWorth, 750);
  });

  test('a new foreign account without any stored rate stays pending', () async {
    final store = _store(const FinanceState());

    await store.addAccount(
        name: '欧元账户',
        type: AccountType.asset,
        currency: 'EUR',
        openingBalance: 100);

    expect(store.assets.accounts.single.openingCnyAmount, isNull);
    expect(store.assets.accountBalances.single.isPending, isTrue);
  });

  test('an edited opening amount re-freezes at the account rate, not today\'s',
      () async {
    final store = _store(const FinanceState(
      accounts: [_usdWithStoredRate],
      exchangeRates: [
        ExchangeRateSnapshot(
            baseCurrency: 'USD',
            rate: 8,
            rateDate: '2026-10-01',
            source: '后来刷新'),
      ],
    ));

    final account = store.assets.accounts.single;
    await store.assets.updateAccount(account.copyWith(openingBalance: 200));

    final updated = store.assets.accounts.single;
    expect(updated.openingCnyAmount, 1400);
    expect(updated.exchangeRate, 7);
    expect(updated.exchangeRateDate, '2026-09-01');
  });

  test('changing currency drops the old snapshot and freezes the new rate',
      () async {
    final store = _store(const FinanceState(
      accounts: [_usdWithStoredRate],
      exchangeRates: [
        ExchangeRateSnapshot(
            baseCurrency: 'EUR',
            rate: 8,
            rateDate: '2026-09-02',
            source: '用户凭证'),
      ],
    ));

    final account = store.assets.accounts.single;
    await store.assets.updateAccount(account.copyWith(currency: 'EUR'));

    final eur = store.assets.accounts.single;
    expect(eur.openingCnyAmount, 800);
    expect(eur.exchangeRate, 8);
    expect(eur.exchangeRateSource, '用户凭证');
    expect(store.assets.accountBalances.single.isPending, isFalse);
    expect(store.assets.netWorth, 800);
  });

  test('changing currency without a stored rate becomes pending, not stale',
      () async {
    final store = _store(const FinanceState(accounts: [_usdWithStoredRate]));

    final account = store.assets.accounts.single;
    await store.assets.updateAccount(account.copyWith(currency: 'GBP'));

    final gbp = store.assets.accounts.single;
    expect(gbp.openingCnyAmount, isNull);
    expect(gbp.exchangeRate, isNull);
    expect(gbp.exchangeRateDate, isNull);
    expect(store.assets.accountBalances.single.isPending, isTrue);

    await store.assets.updateAccount(gbp.copyWith(currency: 'CNY'));
    final cny = store.assets.accounts.single;
    expect(cny.openingCnyAmount, isNull);
    expect(store.assets.accountBalances.single.isPending, isFalse);
    expect(store.assets.netWorth, 100);
  });

  test('an unconverted entry marks its own account pending, not every account',
      () {
    const state = FinanceState(
      accounts: [
        _usdWithStoredRate,
        Account(
            id: 'cash',
            name: '人民币',
            type: AccountType.asset,
            openingBalance: 1000),
      ],
      transactions: [
        FinanceTransaction(
          id: 'pending-usd',
          date: '2026-09-03',
          type: TransactionType.expense,
          amount: 10,
          currency: 'USD',
          accountId: 'usd',
        ),
      ],
    );

    final balances = AssetRules.accountBalances(state, state.transactions);
    final usd = balances.singleWhere((item) => item.account.id == 'usd');
    final cash = balances.singleWhere((item) => item.account.id == 'cash');

    expect(usd.balance, 700);
    expect(usd.isPending, isTrue);
    expect(usd.pendingConversionCount, 1);
    expect(cash.isPending, isFalse);
  });

  test('an entry with a dated stored rate replays instead of staying pending',
      () {
    const state = FinanceState(
      accounts: [_usdWithStoredRate],
      transactions: [
        FinanceTransaction(
          id: 'stored-rate-entry',
          date: '2026-09-03',
          type: TransactionType.expense,
          amount: 10,
          currency: 'USD',
          exchangeRate: 6,
          exchangeRateDate: '2026-09-03',
          accountId: 'usd',
        ),
      ],
    );

    final usd = AssetRules.accountBalances(state, state.transactions).single;
    expect(usd.balance, 640);
    expect(usd.isPending, isFalse);
  });

  testWidgets('the wealth page shows 待换算 for missing snapshots, never ¥0',
      (tester) async {
    final store = _store(const FinanceState(
      currentMonth: '2026-09',
      accounts: [
        Account(
            id: 'cash',
            name: '人民币',
            type: AccountType.asset,
            openingBalance: 1000),
        Account(
            id: 'usd',
            name: '美元账户',
            type: AccountType.asset,
            currency: 'USD',
            openingBalance: 100),
      ],
    ));

    await tester.pumpWidget(MaterialApp(
      theme: wealthMateTheme(),
      home: Scaffold(
        body: WealthPage(store: store.assets, ledger: store.ledger),
      ),
    ));
    await tester.pump();

    expect(find.text('待换算'), findsWidgets);
    expect(
        find.descendant(of: find.byType(FittedBox), matching: find.text('待换算')),
        findsOneWidget);
    // Only the CNY account row carries the known ¥1000. The headline and the
    // asset summary are marked pending instead of presenting the partial sum
    // as the complete net worth.
    expect(find.text('¥1000'), findsOneWidget);
    expect(find.textContaining('不会按 0 计入'), findsOneWidget);
  });

  testWidgets('the wealth page keeps a frozen foreign balance visible',
      (tester) async {
    final store = _store(const FinanceState(
      currentMonth: '2026-09',
      accounts: [_usdWithStoredRate],
    ));

    await tester.pumpWidget(MaterialApp(
      theme: wealthMateTheme(),
      home: Scaffold(
        body: WealthPage(store: store.assets, ledger: store.ledger),
      ),
    ));
    await tester.pump();

    expect(find.text('¥700'), findsWidgets);
    expect(find.text('待换算'), findsNothing);
  });

  testWidgets('the account page and dashboard never render an unknown as ¥0',
      (tester) async {
    const usd = Account(
      id: 'usd',
      name: '美元账户',
      type: AccountType.asset,
      currency: 'USD',
      openingBalance: 100,
    );
    final store = _store(const FinanceState(
      currentMonth: '2026-09',
      accounts: [usd],
    ));

    await tester.pumpWidget(MaterialApp(
      theme: wealthMateTheme(),
      home: AccountDetailPage(store: store.assets, account: usd),
    ));
    await tester.pump();

    expect(find.text('待换算'), findsOneWidget);
    expect(find.text('¥0'), findsNothing);

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

    expect(find.textContaining('当前净资产 待换算'), findsOneWidget);
    expect(find.text('部分账户待换算'), findsOneWidget);
    // The net-worth card is the only 待换算 on this screen; unrelated ¥0
    // metrics (income/expense/savings with no entries) are genuinely zero.
    expect(find.text('待换算'), findsOneWidget);
  });
}
