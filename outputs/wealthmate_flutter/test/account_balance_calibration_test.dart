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
  test('calibration draft keeps the target and date without touching the account',
      () {
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

    final draft = AssetRules.buildCalibrationDraft(
      account,
      targetCny: 745.68,
      effectiveOn: '2026-11-02',
      createdAt: DateTime(2026, 11, 3, 9, 30),
    );

    expect(draft.accountId, 'usd');
    expect(draft.targetCny, 745.68);
    expect(draft.effectiveOn, '2026-11-02');
    expect(draft.createdAt, DateTime(2026, 11, 3, 9, 30).toIso8601String());
    // Drafting never rewrites the frozen opening snapshot.
    expect(account.openingBalance, 100);
    expect(account.openingCnyAmount, 700);
    expect(account.exchangeRate, 7);
  });

  test('calibration draft rejects zero, negative, non-finite and sub-cent targets',
      () {
    const account = Account(
      id: 'cny',
      name: '人民币账户',
      type: AccountType.asset,
      openingBalance: 100,
    );
    final now = DateTime(2026, 11, 3);

    CalibrationDraft build(double target) => AssetRules.buildCalibrationDraft(
          account,
          targetCny: target,
          effectiveOn: '2026-11-02',
          createdAt: now,
        );

    expect(() => build(0), throwsArgumentError);
    expect(() => build(-12.5), throwsArgumentError);
    expect(() => build(double.nan), throwsArgumentError);
    expect(() => build(double.infinity), throwsArgumentError);
    expect(() => build(0.004), throwsArgumentError);
    expect(
        () => AssetRules.buildCalibrationDraft(
              account,
              targetCny: 100,
              effectiveOn: '2026-11-04',
              createdAt: now,
            ),
        throwsArgumentError);
    expect(
        () => AssetRules.buildCalibrationDraft(
              account,
              targetCny: 100,
              effectiveOn: '2026-02-30',
              createdAt: now,
            ),
        throwsArgumentError);
  });

  test('calibration drafts survive state JSON round trips', () {
    const draft = CalibrationDraft(
      accountId: 'cny',
      targetCny: 125.5,
      effectiveOn: '2026-11-02',
      createdAt: '2026-11-03T09:30:00.000',
    );
    const state = FinanceState(calibrationDrafts: [draft]);

    final restored = FinanceState.fromJson(state.toJson());
    final restoredDraft = restored.calibrationDraftFor('cny');

    expect(restoredDraft, isNotNull);
    expect(restoredDraft!.accountId, 'cny');
    expect(restoredDraft.targetCny, 125.5);
    expect(restoredDraft.effectiveOn, '2026-11-02');
    expect(restoredDraft.createdAt, '2026-11-03T09:30:00.000');
    expect(
        state.copyWith(currentMonth: '2026-11').calibrationDraftFor('cny'),
        isNotNull);
    expect(state.copyWith(calibrationDrafts: const []).calibrationDrafts,
        isEmpty);
  });

  test('store calibration saves a local draft only', () async {
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

    await store.calibrateBalance(store.accounts.single, 125.01,
        effectiveOn: '2026-09-15');

    expect(store.accounts.single.openingBalance, 100);
    expect(store.accounts.single.openingCnyAmount, isNull);
    expect(store.state.transactions, same(transactionsBefore));
    expect(store.accountBalances.single.balance, 80);
    expect(store.repository.queue.pending(), isEmpty);
    final draft = store.calibrationDraftFor('cny');
    expect(draft, isNotNull);
    expect(draft!.targetCny, 125.01);
    expect(draft.effectiveOn, '2026-09-15');
    expect(DateTime.tryParse(draft.createdAt), isNotNull);
    expect(store.message, '校准草稿已保存');
  });

  test('store rejects a target equal to the current balance', () async {
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

    await store.calibrateBalance(store.accounts.single, 100,
        effectiveOn: '2026-11-02');

    expect(store.message, '余额已一致，无需校准');
    expect(store.calibrationDraftFor('cny'), isNull);
    expect(store.repository.queue.pending(), isEmpty);
    expect(store.accounts.single.openingBalance, 100);
  });

  testWidgets('saving account configuration keeps a prior calibration draft',
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

    expect(find.text('人民币账面余额'), findsOneWidget);
    expect(find.textContaining('当前保存为本地草稿'), findsOneWidget);

    await tester.enterText(find.byType(TextField).last, '125');
    await tester.tap(find.text('保存校准'));
    await tester.pumpAndSettle();

    expect(store.accounts.single.openingBalance, 100);
    expect(store.calibrationDraftFor('cny')?.targetCny, 125);
    expect(find.text('校准草稿已保存'), findsOneWidget);

    await tester.tap(find.text('保存账户配置'));
    await tester.pumpAndSettle();

    expect(store.accounts.single.openingBalance, 100);
    expect(store.calibrationDraftFor('cny')?.targetCny, 125);
  });

  test('refreshing a rate keeps landed foreign snapshots and queues nothing',
      () async {
    final store = _store(const FinanceState(
      currentMonth: '2026-09',
      accounts: [
        Account(
          id: 'usd',
          name: '美元账户',
          type: AccountType.asset,
          currency: 'USD',
          openingBalance: 100,
          openingCnyAmount: 700,
          exchangeRate: 7,
          exchangeRateDate: '2026-09-10',
          exchangeRateSource: 'manual',
        ),
      ],
      transactions: [
        FinanceTransaction(
          id: 'coffee',
          date: '2026-09-15',
          type: TransactionType.expense,
          amount: 70,
          accountId: 'usd',
        ),
      ],
    ));

    await store.saveManualExchangeRate(
        baseCurrency: 'USD', rate: 8, rateDate: '2026-11-03', source: 'public');

    final account = store.accounts.single;
    expect(account.openingBalance, 100);
    expect(account.openingCnyAmount, 700);
    expect(account.exchangeRate, 7);
    expect(account.exchangeRateDate, '2026-09-10');
    expect(account.exchangeRateSource, 'manual');
    expect(store.accountBalances.single.balance, 630);
    expect(store.repository.queue.pending(), isEmpty);
    // The candidate cache still moves to the newest rate.
    expect(store.exchangeRates.single.rate, 8);
    expect(store.exchangeRates.single.rateDate, '2026-11-03');
  });

  test('refreshing fills a missing snapshot once and queues a single update',
      () async {
    final store = _store(const FinanceState(
      accounts: [
        Account(
          id: 'usd',
          name: '美元账户',
          type: AccountType.asset,
          currency: 'USD',
          openingBalance: 100,
        ),
      ],
    ));

    await store.saveManualExchangeRate(
        baseCurrency: 'USD', rate: 7, rateDate: '2026-11-01', source: 'public');

    expect(store.accounts.single.openingCnyAmount, 700);
    expect(store.accounts.single.exchangeRate, 7);
    expect(store.repository.queue.pending(), hasLength(1));
    final operation = store.repository.queue.pending().single;
    expect(operation.entity, 'accounts');
    expect(operation.entityId, 'usd');
    expect(operation.type, SyncOperationType.upsert);
    expect(operation.payload['opening_cny_amount'], 700);

    await store.saveManualExchangeRate(
        baseCurrency: 'USD', rate: 8, rateDate: '2026-11-03', source: 'public');

    expect(store.accounts.single.openingCnyAmount, 700);
    expect(store.accounts.single.exchangeRate, 7);
    expect(store.repository.queue.pending(), hasLength(1));
    expect(store.exchangeRates.single.rate, 8);
  });
}
