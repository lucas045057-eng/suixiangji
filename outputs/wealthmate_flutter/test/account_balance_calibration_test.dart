import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wealthmate_flutter/core/database/local_state_session.dart';
import 'package:wealthmate_flutter/data/local_repository.dart';
import 'package:wealthmate_flutter/data/sync_queue.dart';
import 'package:wealthmate_flutter/domain/models.dart';
import 'package:wealthmate_flutter/features/assets/data/assets_repository.dart';
import 'package:wealthmate_flutter/features/assets/domain/asset_rules.dart';
import 'package:wealthmate_flutter/features/assets/state/asset_store.dart';
import 'package:wealthmate_flutter/ui/account_detail_page.dart';

class _MemoryStore implements KeyValueStore {
  final values = <String, String>{};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;
}

AssetStore _store(FinanceState initialState) {
  final session = LocalStateSession(
    local: LocalRepository(_MemoryStore()),
    queue: SyncQueue(),
  );
  return AssetStore(
    repository: AssetsRepository(session: session),
    initialState: initialState,
  );
}

void main() {
  test('CNY calibration changes opening balance by a two-decimal delta', () {
    const account = Account(
      id: 'cny',
      name: '人民币账户',
      type: AccountType.asset,
      openingBalance: 100,
    );

    final calibrated = AssetRules.calibrateBalance(account, 1.235);

    expect(calibrated.openingBalance, 101.24);
    expect(calibrated.openingCnyAmount, isNull);
  });

  test('foreign calibration changes only the CNY display opening', () {
    const account = Account(
      id: 'usd',
      name: '美元账户',
      type: AccountType.asset,
      currency: 'USD',
      openingBalance: 100,
      openingCnyAmount: 700,
      exchangeRate: 7,
      exchangeRateDate: '2026-09-10',
      exchangeRateSource: 'manual',
    );

    final calibrated = AssetRules.calibrateBalance(account, 45.678);

    expect(calibrated.openingBalance, 100);
    expect(calibrated.openingCnyAmount, 745.68);
    expect(calibrated.exchangeRate, 7);
    expect(calibrated.exchangeRateDate, '2026-09-10');
    expect(calibrated.exchangeRateSource, 'manual');
  });

  test('calibration rejects non-finite and zero changes', () {
    const account = Account(
      id: 'cny',
      name: '人民币账户',
      type: AccountType.asset,
      openingBalance: 100,
    );

    expect(() => AssetRules.calibrateBalance(account, 0), throwsArgumentError);
    expect(() => AssetRules.calibrateBalance(account, double.nan),
        throwsArgumentError);
    expect(() => AssetRules.calibrateBalance(account, double.infinity),
        throwsArgumentError);
    expect(
        () => AssetRules.calibrateBalance(account, 0.004), throwsArgumentError);
  });

  test('store calibration upserts only the account and preserves ledger data',
      () async {
    const transaction = FinanceTransaction(
      id: 'existing',
      date: '2026-09-15',
      type: TransactionType.expense,
      amount: 20,
      accountId: 'cny',
    );
    final store = _store(const FinanceState(
      currentMonth: '2026-09',
      accounts: [
        Account(
          id: 'cny',
          name: '人民币账户',
          type: AccountType.asset,
          openingBalance: 100,
        ),
      ],
      transactions: [transaction],
    ));
    final transactionsBefore = store.state.transactions;

    await store.calibrateBalance(store.accounts.single, 25.005);

    expect(store.accounts.single.openingBalance, 125.01);
    expect(store.state.transactions, same(transactionsBefore));
    expect(store.accountBalances.single.balance, 105.01);
    expect(store.repository.queue.pending(), hasLength(1));
    expect(store.repository.queue.pending().single.entity, 'accounts');
    expect(
        store.repository.queue.pending().single.type, SyncOperationType.upsert);
    expect(store.repository.queue.pending().single.entityId, 'cny');
    expect(
        store.repository.queue
            .pending()
            .any((operation) => operation.entity == 'transactions'),
        isFalse);
  });

  testWidgets('saving account configuration keeps a prior calibration',
      (tester) async {
    final store = _store(const FinanceState(
      accounts: [
        Account(
          id: 'cny',
          name: '人民币账户',
          type: AccountType.asset,
          openingBalance: 100,
        ),
      ],
    ));

    await tester.pumpWidget(MaterialApp(
      home: AccountDetailPage(store: store, account: store.accounts.single),
    ));
    await tester.drag(find.byType(ListView), const Offset(0, -500));
    await tester.pumpAndSettle();
    await tester.tap(find.text('余额校准'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, '125');
    await tester.tap(find.text('保存校准'));
    await tester.pumpAndSettle();

    expect(store.accounts.single.openingBalance, 125);
    await tester.tap(find.text('保存账户配置'));
    await tester.pumpAndSettle();

    expect(store.accounts.single.openingBalance, 125);
  });
}
