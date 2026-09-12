import 'package:flutter_test/flutter_test.dart';
import 'package:wealthmate_flutter/core/database/local_state_session.dart';
import 'package:wealthmate_flutter/data/finance_repository.dart';
import 'package:wealthmate_flutter/data/local_repository.dart';
import 'package:wealthmate_flutter/data/sync_queue.dart';
import 'package:wealthmate_flutter/domain/models.dart';
import 'package:wealthmate_flutter/features/assets/data/assets_repository.dart';
import 'package:wealthmate_flutter/features/assets/state/asset_store.dart';

class _AssetMemory implements KeyValueStore {
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

class _SentinelAssetsRepository extends AssetsRepository {
  _SentinelAssetsRepository({required super.session, required this.result});

  final FinanceState result;

  @override
  Future<FinanceState> saveAccount(Account account,
          {FinanceState? baseState}) async =>
      result;
}

AssetStore _assetStore(_AssetMemory memory, FinanceState state) {
  final queue = SyncQueue();
  final session = LocalStateSession(
    local: LocalRepository(memory),
    queue: queue,
  );
  return AssetStore(
    repository: AssetsRepository(session: session),
    initialState: state,
  );
}

void main() {
  test('account writes reject duplicate names and never mutate transactions',
      () async {
    final memory = _AssetMemory();
    const transaction = FinanceTransaction(
      id: 'existing-tx',
      date: '2026-09-10',
      type: TransactionType.expense,
      amount: 12,
      accountId: 'wallet',
    );
    final store = _assetStore(
      memory,
      const FinanceState(
        currentMonth: '2026-09',
        accounts: [
          Account(id: 'wallet', name: '钱包', type: AccountType.asset),
          Account(id: 'bank', name: '银行卡', type: AccountType.asset),
        ],
        transactions: [transaction],
      ),
    );

    await store.updateAccount(store.accounts.last.copyWith(name: '  钱包  '));

    expect(store.accounts.last.name, '银行卡');
    expect(store.message, '账户名称不能重复');
    expect(store.state.transactions, same(store.state.transactions));
    expect(store.repository.queue.pending(), isEmpty);

    final transactionsBefore = store.state.transactions;
    await store.updateAccount(store.accounts.last.copyWith(name: '储蓄卡'));

    expect(store.accounts.last.name, '储蓄卡');
    expect(store.state.transactions, same(transactionsBefore));
    expect(store.repository.queue.pending(), hasLength(1));
    expect(store.repository.queue.pending().single.entity, 'accounts');
    expect(memory.writes, greaterThan(0));
  });

  test('only an active asset account can become the default account', () async {
    final store = _assetStore(
      _AssetMemory(),
      const FinanceState(accounts: [
        Account(id: 'wallet', name: '钱包', type: AccountType.asset),
        Account(id: 'credit', name: '信用卡', type: AccountType.liability),
        Account(
          id: 'archived',
          name: '已归档',
          type: AccountType.asset,
          deletedAt: '2026-09-01T00:00:00Z',
        ),
      ]),
    );

    await store.setDefaultAccount('credit');
    await store.setDefaultAccount('archived');
    expect(store.state.defaultAccountId, isNull);

    await store.setDefaultAccount('wallet');
    expect(store.state.defaultAccountId, 'wallet');
  });

  test('manual FX preserves its snapshot and updates only matching accounts',
      () async {
    final memory = _AssetMemory();
    const transaction = FinanceTransaction(
      id: 'usd-tx',
      date: '2026-09-10',
      type: TransactionType.expense,
      amount: 10,
      currency: 'USD',
      accountId: 'usd',
    );
    final store = _assetStore(
      memory,
      const FinanceState(
        accounts: [
          Account(
            id: 'usd',
            name: '美元账户',
            type: AccountType.asset,
            currency: 'USD',
            openingBalance: 100,
          ),
          Account(
            id: 'eur',
            name: '欧元账户',
            type: AccountType.asset,
            currency: 'EUR',
            openingBalance: 50,
          ),
        ],
        transactions: [transaction],
      ),
    );
    final transactionsBefore = store.state.transactions;

    await store.saveManualExchangeRate(
      baseCurrency: 'usd',
      rate: 7.25,
      rateDate: '2026-09-03',
      source: ' 手动核验 ',
    );

    final snapshot = store.exchangeRates.single;
    expect(snapshot.baseCurrency, 'USD');
    expect(snapshot.quoteCurrency, 'CNY');
    expect(snapshot.rate, 7.25);
    expect(snapshot.rateDate, '2026-09-03');
    expect(snapshot.source, '手动核验');
    expect(snapshot.updatedAt, isNotNull);
    final usd = store.accounts.singleWhere((item) => item.id == 'usd');
    expect(usd.openingCnyAmount, 725);
    expect(usd.exchangeRate, 7.25);
    expect(usd.exchangeRateDate, '2026-09-03');
    expect(usd.exchangeRateSource, '手动核验');
    expect(
        store.accounts.singleWhere((item) => item.id == 'eur').openingCnyAmount,
        isNull);
    expect(store.state.transactions, same(transactionsBefore));
    expect(
        (await store.repository.load())!.exchangeRates.single.source, '手动核验');
  });

  test('net-worth selectors preserve asset liability and missing-rate rules',
      () {
    final store = _assetStore(
      _AssetMemory(),
      const FinanceState(
        currentMonth: '2026-09',
        accounts: [
          Account(
            id: 'cash',
            name: '现金',
            type: AccountType.asset,
            openingBalance: 1000,
          ),
          Account(
            id: 'credit',
            name: '信用卡',
            type: AccountType.liability,
            openingBalance: 200,
          ),
          Account(
            id: 'usd',
            name: '美元',
            type: AccountType.asset,
            currency: 'USD',
            openingBalance: 100,
          ),
        ],
        transactions: [
          FinanceTransaction(
            id: 'cash-expense',
            date: '2026-09-01',
            type: TransactionType.expense,
            amount: 100,
            accountId: 'cash',
          ),
          FinanceTransaction(
            id: 'credit-expense',
            date: '2026-09-02',
            type: TransactionType.expense,
            amount: 50,
            accountId: 'credit',
          ),
          FinanceTransaction(
            id: 'pending-usd',
            date: '2026-09-03',
            type: TransactionType.expense,
            amount: 10,
            currency: 'USD',
            accountId: 'usd',
          ),
        ],
      ),
    );

    expect(store.assetTotal, 900);
    expect(store.liabilityTotal, 250);
    expect(store.netWorth, 650);
    expect(store.pendingConversionCount, 1);
    expect(
      store.accountBalances
          .singleWhere((item) => item.account.id == 'usd')
          .balance,
      0,
    );
  });

  test('FinanceRepository delegates account compatibility writes to Assets',
      () async {
    final memory = _AssetMemory();
    final queue = SyncQueue();
    final session = LocalStateSession(
      local: LocalRepository(memory),
      queue: queue,
    );
    const delegated = FinanceState(currentMonth: 'delegated-by-assets');
    final repository = FinanceRepository(
      local: LocalRepository(memory),
      queue: queue,
      session: session,
      assetsRepository:
          _SentinelAssetsRepository(session: session, result: delegated),
    );

    final result = await repository.applyLocalAccount(
      const FinanceState(),
      const Account(id: 'wallet', name: '钱包', type: AccountType.asset),
    );

    expect(identical(result, delegated), isTrue);
  });
}
