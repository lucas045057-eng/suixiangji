import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wealthmate_flutter/domain/models.dart';
import 'package:wealthmate_flutter/domain/finance_rules.dart';
import 'package:wealthmate_flutter/data/finance_repository.dart';
import 'package:wealthmate_flutter/data/local_repository.dart';
import 'package:wealthmate_flutter/data/sync_queue.dart';
import 'package:wealthmate_flutter/state/finance_store.dart';
import 'package:wealthmate_flutter/ui/widgets/transaction_form.dart';
import 'package:wealthmate_flutter/ui/app_shell.dart';
import 'v105_assets_closure_test.dart' show Memory;

void main() {
  test(
      'manual and quick-entry writes use dated FX snapshots and preserve historical conversions',
      () async {
    final store = FinanceStore(
        repository: FinanceRepository(
            local: LocalRepository(Memory()), queue: SyncQueue()),
        initialState: const FinanceState(exchangeRates: [
          ExchangeRateSnapshot(
              baseCurrency: 'USD',
              rate: 7,
              rateDate: '2026-10-09',
              source: 'manual')
        ], categories: [
          Category(id: 'food', name: '餐饮')
        ], accounts: [
          Account(id: 'cash', name: '卡', type: AccountType.asset)
        ]));
    addTearDown(store.dispose);
    await store.ledger.addTransaction(const FinanceTransaction(
        id: 'known',
        date: '2026-10-09',
        type: TransactionType.expense,
        amount: 2,
        currency: 'USD',
        accountId: 'cash',
        categoryId: 'food'));
    await store.ledger.addTransaction(const FinanceTransaction(
        id: 'old',
        date: '2026-09-01',
        type: TransactionType.expense,
        amount: 2,
        currency: 'USD',
        accountId: 'cash',
        categoryId: 'food'));
    await store.ledger.addTransaction(const FinanceTransaction(
        id: 'snapshot',
        date: '2026-10-09',
        type: TransactionType.income,
        amount: 2,
        currency: 'USD',
        cnyAmount: 13,
        exchangeRate: 6.5,
        accountId: 'cash'));
    expect(
        store.state.transactions.firstWhere((t) => t.id == 'known').cnyAmount,
        14);
    expect(
        store.repository.queue
            .pending()
            .firstWhere((op) => op.entityId == 'known')
            .payload['cny_amount'],
        14);
    expect(
        store.state.transactions
            .firstWhere((t) => t.id == 'old')
            .conversionStatus,
        'pending');
    expect(
        store.state.transactions
            .firstWhere((t) => t.id == 'snapshot')
            .cnyAmount,
        13);
  });
  testWidgets('home never invents a user named 林默', (tester) async {
    final store = FinanceStore(
        repository: FinanceRepository(
            local: LocalRepository(Memory()), queue: SyncQueue()),
        initialState: const FinanceState());
    addTearDown(store.dispose);
    await tester.pumpWidget(MaterialApp(home: AppShell(store: store)));
    expect(find.textContaining('林默'), findsNothing);
  });
  test('lunch resolves real category IDs and never selects archived default',
      () {
    final state = FinanceState.fromJson({
      'default_account_id': 'old',
      'preferred_currency': 'HKD',
      'categories': [const Category(id: 'custom-food', name: '餐饮').toJson()],
      'accounts': [
        const Account(
                id: 'old',
                name: '旧卡',
                type: AccountType.asset,
                archivedAt: '2026-10-09')
            .toJson(),
        const Account(
                id: 'cash',
                name: '现金',
                type: AccountType.asset,
                isDefaultPayment: true)
            .toJson(),
      ],
    });
    final draft = FinanceRules.completeNaturalLanguageDraft('我午饭吃了16块',
        now: DateTime(2026, 10, 9), state: state);
    expect(draft.amount, 16);
    expect(draft.categoryId, 'custom-food');
    expect(draft.accountId, 'cash');
    expect(draft.currency, 'HKD');
    expect(FinanceRules.canPostDraft(draft), isTrue);
    final explicit = FinanceRules.completeNaturalLanguageDraft('午饭16美元',
        now: DateTime(2026, 10, 9), state: state);
    expect(explicit.currency, 'USD');
  });
  testWidgets(
      'manual entry uses saved currency and offers common currency choices',
      (tester) async {
    final store = FinanceStore(
        repository: FinanceRepository(
            local: LocalRepository(Memory()), queue: SyncQueue()),
        initialState: FinanceState.fromJson({
          'preferred_currency': 'HKD',
          'common_currencies': ['CNY', 'HKD', 'USD'],
          'accounts': [
            const Account(id: 'cash', name: '现金', type: AccountType.asset)
                .toJson()
          ],
          'categories': [const Category(id: 'food', name: '餐饮').toJson()],
        }));
    addTearDown(store.dispose);
    await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: TransactionForm(store: store))));
    expect(find.text('HKD'), findsWidgets);
    expect(find.text('USD'), findsWidgets);
  });
}
