import 'package:flutter_test/flutter_test.dart';
import 'package:wealthmate_flutter/data/finance_repository.dart';
import 'package:wealthmate_flutter/data/api_client.dart';
import 'package:wealthmate_flutter/data/local_repository.dart';
import 'package:wealthmate_flutter/data/sync_queue.dart';
import 'package:wealthmate_flutter/domain/models.dart';
import 'package:wealthmate_flutter/state/finance_store.dart';

class StoreMemory implements KeyValueStore {
  String? value;

  @override
  Future<String?> read(String key) async => value;

  @override
  Future<void> write(String key, String value) async => this.value = value;
}

FinanceState storeState() => FinanceState(
      currentMonth: '2026-09',
      accounts: const [
        Account(
            id: 'alipay', name: '支付宝', type: AccountType.asset, isLiquid: true)
      ],
      categories: const [Category(id: 'food', name: '餐饮')],
      goals: const [
        Goal(
            id: 'emergency',
            name: '应急金',
            target: 1000,
            liquidAccountIds: ['alipay'])
      ],
    );

FinanceRepository storeRepository() => FinanceRepository(
      local: LocalRepository(StoreMemory()),
      queue: SyncQueue(),
    );

void main() {
  test('low-confidence drafts cannot be confirmed', () async {
    final store =
        FinanceStore(repository: storeRepository(), initialState: storeState());
    final draft = const AgentDraft(
      amount: 32,
      type: TransactionType.expense,
      categoryId: 'food',
      accountId: 'alipay',
      date: '2026-09-01',
      note: '午餐',
      confidence: .72,
    );

    final posted = await store.confirmDraft(draft);

    expect(posted, isFalse);
    expect(store.state.transactions, isEmpty);
  });

  test('accepted draft appends a transaction and updates metrics', () async {
    final store =
        FinanceStore(repository: storeRepository(), initialState: storeState());
    final draft = const AgentDraft(
      amount: 32,
      type: TransactionType.expense,
      categoryId: 'food',
      accountId: 'alipay',
      date: '2026-09-01',
      note: '午餐',
      confidence: .98,
    );

    final posted = await store.confirmDraft(draft);

    expect(posted, isTrue);
    expect(store.state.transactions, hasLength(1));
    expect(store.metrics.expense, 32);
  });

  test('createDraft completes the account from the recent category habit',
      () async {
    final store = FinanceStore(
      repository: storeRepository(),
      initialState: storeState().copyWith(transactions: const [
        FinanceTransaction(
            id: 'recent-food',
            date: '2026-09-03',
            type: TransactionType.expense,
            amount: 28,
            categoryId: 'food',
            accountId: 'alipay'),
      ]),
    );

    await store.createDraft('今天吃饭吃了30元', now: DateTime(2026, 9, 4, 10));

    expect(store.draft?.amount, 30);
    expect(store.draft?.categoryId, 'food');
    expect(store.draft?.accountId, 'alipay');
    expect(store.draft?.missingFacts, isEmpty);
  });

  test('edited draft can be confirmed and teaches the quick memory',
      () async {
    final store = FinanceStore(
        repository: storeRepository(), initialState: storeState());

    await store.createDraft('今天吃饭吃了30元', now: DateTime(2026, 9, 4, 10));
    final original = store.draft!;
    store.updateDraft(original.copyWith(
        accountId: 'alipay', confidence: .98, missingFacts: const []));

    final posted = await store.confirmDraft(store.draft!);

    expect(posted, isTrue);
    expect(store.state.transactions.single.accountId, 'alipay');
    expect(store.state.quickMemories.single.categoryId, 'food');
    expect(store.state.quickMemories.single.accountId, 'alipay');
  });

  test('deleting a transaction creates a soft-delete sync operation', () async {
    final store =
        FinanceStore(repository: storeRepository(), initialState: storeState());
    await store.addTransaction(const FinanceTransaction(
      id: 'tx-1',
      date: '2026-09-01',
      type: TransactionType.expense,
      amount: 32,
      categoryId: 'food',
      accountId: 'alipay',
    ));

    await store.deleteTransaction('tx-1');

    expect(store.state.transactions.single.deletedAt, isNotNull);
    expect(
        store.repository.queue.pending().single.type, SyncOperationType.delete);
  });

  test('sync explains local demo mode when API configuration is absent',
      () async {
    final store =
        FinanceStore(repository: storeRepository(), initialState: storeState());

    await store.sync();

    expect(store.state.syncState.error, '离线演示/待配置');
  });

  test('custom category can be renamed without changing its identity',
      () async {
    final store =
        FinanceStore(repository: storeRepository(), initialState: storeState());

    await store.addCategory(name: '宠物', type: TransactionType.expense);
    final created =
        store.state.categories.singleWhere((item) => item.name == '宠物');
    await store.updateCategory(created.id, name: '宠物照护', active: true);

    final renamed =
        store.state.categories.singleWhere((item) => item.id == created.id);
    expect(renamed.name, '宠物照护');
    expect(renamed.id, created.id);
  });

  test(
      'archived category remains resolvable for history but is inactive for new forms',
      () async {
    final store =
        FinanceStore(repository: storeRepository(), initialState: storeState());
    await store.addCategory(name: '旧分类', type: TransactionType.expense);
    final category =
        store.state.categories.singleWhere((item) => item.name == '旧分类');
    await store.addTransaction(FinanceTransaction(
        id: 'old-tx',
        date: '2026-09-01',
        type: TransactionType.expense,
        amount: 10,
        categoryId: category.id,
        accountId: 'alipay'));

    await store.archiveCategory(category.id);

    expect(
        store.state.categories
            .singleWhere((item) => item.id == category.id)
            .active,
        isFalse);
    expect(store.state.transactions.single.categoryId, category.id);
    expect(
        store.activeCategories.any((item) => item.id == category.id), isFalse);
  });

  test('account configuration updates locally and queues one account upsert',
      () async {
    final store =
        FinanceStore(repository: storeRepository(), initialState: storeState());
    final account = store.state.accounts.single;

    await store.updateAccount(
        account.copyWith(name: '我的支付宝', accountKind: AccountKind.alipay));

    expect(store.state.accounts.single.name, '我的支付宝');
    expect(store.state.accounts.single.accountKind, AccountKind.alipay);
    expect(store.repository.queue.pending(), hasLength(1));
    expect(store.repository.queue.pending().single.entity, 'accounts');
    expect(store.repository.queue.pending().single.payload['account_kind'],
        'alipay');
  });

  test('account configuration rejects duplicate display names', () async {
    final store = FinanceStore(
      repository: storeRepository(),
      initialState: storeState().copyWith(accounts: const [
        Account(
            id: 'alipay', name: '支付宝', type: AccountType.asset),
        Account(id: 'bank', name: '银行卡', type: AccountType.asset),
      ]),
    );

    await store.updateAccount(store.state.accounts.last.copyWith(name: '支付宝'));

    expect(store.state.accounts.last.name, '银行卡');
    expect(store.message, '账户名称不能重复');
  });

  test(
      'budget edits keep one record and budget alerts are deduplicated by threshold',
      () async {
    final initial = storeState().copyWith(
      transactions: [
        const FinanceTransaction(
            id: 'warning',
            date: '2026-09-01',
            type: TransactionType.expense,
            amount: 80,
            categoryId: 'food',
            accountId: 'alipay'),
        const FinanceTransaction(
            id: 'exhausted',
            date: '2026-09-02',
            type: TransactionType.expense,
            amount: 100,
            categoryId: 'transport',
            accountId: 'alipay'),
        const FinanceTransaction(
            id: 'over',
            date: '2026-09-03',
            type: TransactionType.expense,
            amount: 120,
            categoryId: 'shopping',
            accountId: 'alipay'),
      ],
      budgets: const [
        Budget(
            id: 'food-budget',
            month: '2026-09',
            categoryId: 'food',
            limit: 100),
        Budget(
            id: 'transport-budget',
            month: '2026-09',
            categoryId: 'transport',
            limit: 100),
        Budget(
            id: 'shopping-budget',
            month: '2026-09',
            categoryId: 'shopping',
            limit: 100),
        Budget(
            id: 'food-alert-budget',
            month: '2026-09',
            categoryId: 'food',
            limit: 100),
      ],
    );
    final store =
        FinanceStore(repository: storeRepository(), initialState: initial);

    await store.upsertBudget(
        id: 'food-budget', month: '2026-10', categoryId: 'food', limit: 200);
    expect(store.state.budgets.where((item) => item.id == 'food-budget'),
        hasLength(1));
    expect(
        store.state.budgets
            .singleWhere((item) => item.id == 'food-budget')
            .month,
        '2026-10');

    final firstAlerts = await store.checkBudgetAlerts();
    expect(
        firstAlerts.map((item) => item.level),
        containsAll(<BudgetAlertLevel>[
          BudgetAlertLevel.warning,
          BudgetAlertLevel.exhausted,
          BudgetAlertLevel.over
        ]));
    expect(await store.checkBudgetAlerts(), isEmpty);
  });

  test(
      'manual exchange rate is stored with source and date and updates foreign account conversion',
      () async {
    final store = FinanceStore(
      repository: storeRepository(),
      initialState: storeState().copyWith(accounts: const [
        Account(
            id: 'usd',
            name: '美元账户',
            type: AccountType.asset,
            currency: 'USD',
            openingBalance: 100)
      ]),
    );

    await store.saveManualExchangeRate(
        baseCurrency: 'USD',
        rate: 7.25,
        rateDate: '2026-09-03',
        source: '手动核验');

    expect(store.state.exchangeRates.single.rate, 7.25);
    expect(store.state.exchangeRates.single.source, '手动核验');
    expect(store.state.accounts.single.openingCnyAmount, 725);
  });

  test('failed exchange refresh keeps the previous verified rate', () async {
    final state = storeState().copyWith(exchangeRates: const [
      ExchangeRateSnapshot(
          baseCurrency: 'USD',
          quoteCurrency: 'CNY',
          rate: 7.2,
          rateDate: '2026-09-01',
          source: 'previous')
    ]);
    final store = FinanceStore(
        repository: FinanceRepository(
            local: LocalRepository(StoreMemory()),
            queue: SyncQueue(),
            api:
                ApiClient(baseUrl: 'http://127.0.0.1:1', token: 'unreachable')),
        initialState: state);

    await store.refreshExchangeRate('USD');

    expect(store.state.exchangeRates.single.rate, 7.2);
    expect(store.state.exchangeRates.single.source, 'previous');
  });

  test(
      'repeated metric reads reuse the derived result until finance state changes',
      () async {
    final store =
        FinanceStore(repository: storeRepository(), initialState: storeState());
    final first = store.metrics;
    final second = store.metrics;
    expect(identical(first, second), isTrue);

    await store.upsertBudget(month: '2026-09', categoryId: 'food', limit: 900);
    expect(store.state.transactions, hasLength(0));
    expect(identical(first, store.metrics), isFalse);
  });
}
