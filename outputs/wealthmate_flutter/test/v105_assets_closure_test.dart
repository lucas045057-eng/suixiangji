import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:wealthmate_flutter/data/finance_repository.dart';
import 'package:wealthmate_flutter/state/finance_store.dart';
import 'package:wealthmate_flutter/ui/settings_page.dart';
import 'package:wealthmate_flutter/core/database/local_state_session.dart';
import 'package:wealthmate_flutter/data/local_repository.dart';
import 'package:wealthmate_flutter/data/sync_queue.dart';
import 'package:wealthmate_flutter/domain/models.dart';
import 'package:wealthmate_flutter/features/assets/data/assets_repository.dart';
import 'package:wealthmate_flutter/features/assets/state/asset_store.dart';

class Memory implements KeyValueStore {
  final values = <String, String>{};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async => values[key] = value;
}

AssetStore makeStore(Memory memory, FinanceState state) => AssetStore(
    repository: AssetsRepository(
        session: LocalStateSession(
            local: LocalRepository(memory), queue: SyncQueue())),
    initialState: state);

const accounts = [
  Account(
      id: 'hkd',
      name: '港币卡',
      type: AccountType.asset,
      currency: 'HKD',
      openingBalance: 100,
      serverVersion: 4),
  Account(
      id: 'usd',
      name: '美元卡',
      type: AccountType.asset,
      currency: 'USD',
      openingBalance: 50,
      serverVersion: 5),
];

void main() {
  test(
      'UR-004/016 archive and purpose survive local reopen without deleting history',
      () async {
    final memory = Memory();
    const bill = FinanceTransaction(
        id: 'history',
        date: '2026-09-01',
        type: TransactionType.expense,
        amount: 10,
        accountId: 'hkd');
    final store = makeStore(
        memory, const FinanceState(accounts: accounts, transactions: [bill]));
    final archived = Account.fromJson({
      ...accounts.first.toJson(),
      'note': '工资卡',
      'archived_at': '2026-10-09T10:00:00'
    });
    await store.updateAccount(archived);
    expect(store.activeAccounts.map((a) => a.id), ['usd']);
    expect(store.state.transactions.single.accountId, 'hkd');
    final payload = store.repository.queue.pending().single.payload;
    expect(payload['archived_at'], '2026-10-09T10:00:00');
    expect(payload['note'], '工资卡');
    expect(payload['deleted_at'], isNull);
    final reopened = await LocalRepository(memory).load();
    expect(reopened!.accounts.firstWhere((a) => a.id == 'hkd').toJson()['note'],
        '工资卡');
    final restored =
        Account.fromJson({...archived.toJson(), 'archived_at': null});
    await store.updateAccount(restored);
    expect(store.activeAccounts, hasLength(2));
    expect(store.state.transactions.single.amount, 10);
    expect(
        store.repository.queue.pending().last.payload['archived_at'], isNull);
  });

  test(
      'UR-018 HKD then USD then HKD queues each account snapshot without reverting other currency',
      () async {
    final memory = Memory();
    final store = makeStore(memory, const FinanceState(accounts: accounts));
    await store.saveManualExchangeRate(
        baseCurrency: 'HKD', rate: .9, rateDate: '2026-10-08', source: '用户凭证');
    await store.saveManualExchangeRate(
        baseCurrency: 'USD', rate: 7, rateDate: '2026-10-08', source: '用户凭证');
    await store.saveManualExchangeRate(
        baseCurrency: 'HKD', rate: .91, rateDate: '2026-10-09', source: '用户凭证');
    final state = (await LocalRepository(memory).load())!;
    final hkd = state.accounts.firstWhere((a) => a.id == 'hkd');
    final usd = state.accounts.firstWhere((a) => a.id == 'usd');
    expect(hkd.openingBalance, 100);
    expect(hkd.openingCnyAmount, 91);
    expect(usd.openingBalance, 50);
    expect(usd.openingCnyAmount, 350);
    final queued = await LocalRepository(memory).loadQueue();
    // The established queue coalesces pending mutations per entity.
    expect(queued, hasLength(2));
    expect(queued.map((op) => op.entityId), ['hkd', 'usd']);
    expect(queued.map((op) => op.payload['opening_cny_amount']), [91, 350]);
    expect(queued.first.payload['server_version'], 4);
  });

  test(
      'concurrent currency saves derive queue payloads from their serialized state',
      () async {
    final store = makeStore(Memory(), const FinanceState(accounts: accounts));
    await Future.wait([
      store.saveManualExchangeRate(
          baseCurrency: 'HKD',
          rate: .9,
          rateDate: '2026-10-09',
          source: '用户凭证'),
      store.saveManualExchangeRate(
          baseCurrency: 'USD', rate: 7, rateDate: '2026-10-09', source: '用户凭证'),
    ]);
    expect(store.accounts.map((a) => a.openingCnyAmount), [90, 350]);
    expect(store.repository.queue.pending(), hasLength(2));
  });

  test('non-finite and non-CNY snapshots never corrupt balances or queue',
      () async {
    final store = makeStore(Memory(), const FinanceState(accounts: accounts));
    await store.saveManualExchangeRate(
        baseCurrency: 'HKD',
        rate: double.infinity,
        rateDate: '2026-10-09',
        source: '用户凭证');
    expect(store.accounts.first.openingCnyAmount, isNull);
    expect(store.repository.queue.pending(), isEmpty);
  });

  testWidgets(
      'UR-007/017 personal page limits account preview and opens searchable archived management',
      (tester) async {
    final state = FinanceState(accounts: [
      for (var i = 1; i <= 10; i++)
        Account(
            id: 'a$i',
            name: '账户$i',
            note: i == 9 ? '工资卡' : '',
            type: AccountType.asset),
      const Account(
          id: 'old',
          name: '旧卡',
          type: AccountType.asset,
          archivedAt: '2026-10-09'),
    ]);
    final store = FinanceStore(
        repository: FinanceRepository(
            local: LocalRepository(Memory()), queue: SyncQueue()),
        initialState: state);
    addTearDown(store.dispose);
    await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: SettingsPage(store: store))));
    expect(find.text('账户9'), findsNothing);
    await tester.scrollUntilVisible(find.text('查看全部账户'), 200);
    await tester.pumpAndSettle();
    await tester.tap(find.text('查看全部账户'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '工资');
    await tester.pumpAndSettle();
    expect(find.text('账户9'), findsOneWidget);
    expect(find.text('账户8'), findsNothing);
    await tester.enterText(find.byType(TextField).first, '');
    await tester.tap(find.text('已归档'));
    await tester.pumpAndSettle();
    expect(find.text('旧卡'), findsOneWidget);
    await tester.tap(find.text('恢复'));
    await tester.pumpAndSettle();
    expect(store.assets.activeAccounts.any((a) => a.id == 'old'), isTrue);
  });
}
