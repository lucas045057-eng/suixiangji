import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:wealthmate_flutter/core/database/local_state_session.dart';
import 'package:wealthmate_flutter/data/api_client.dart';
import 'package:wealthmate_flutter/data/local_repository.dart';
import 'package:wealthmate_flutter/data/sync_queue.dart';
import 'package:wealthmate_flutter/domain/models.dart';
import 'package:wealthmate_flutter/features/assets/data/assets_remote_data_source.dart';
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

LocalStateSession _session(_MemoryStore memory) =>
    LocalStateSession(local: LocalRepository(memory), queue: SyncQueue());

AssetStore _store(FinanceState initialState, {_MemoryStore? memory}) {
  return AssetStore(
    repository: AssetsRepository(session: _session(memory ?? _MemoryStore())),
    initialState: initialState,
  );
}

AssetStore _onlineStore(
  FinanceState initialState,
  MockClient client,
) {
  final api = ApiClient(
    baseUrl: 'https://calibration.test',
    token: 'calibration-token',
    client: client,
  );
  return AssetStore(
    repository: AssetsRepository(
      session: _session(_MemoryStore()),
      remote: AssetsRemoteDataSource(api: api),
    ),
    initialState: initialState,
  );
}

http.Response _json(int status, Map<String, Object?> body) => http.Response(
      jsonEncode(body),
      status,
      headers: const {'content-type': 'application/json; charset=utf-8'},
    );

/// Echoes an authoritative adjustment shaped like `transaction_json`.
http.Response _adjustmentResponse(
  http.Request request,
  String amount, {
  String? reversesId,
  int serverVersion = 5,
}) {
  final body = jsonDecode(request.body) as Map<String, Object?>;
  final date = (body['effective_on'] ?? '2026-09-15') as String;
  return _json(200, {
    'id': body['adjustment_id'],
    'date': date,
    'occurred_on': date,
    'type': 'adjustment',
    'kind': 'adjustment',
    'amount': amount,
    'currency': 'CNY',
    'original_amount': amount,
    'original_currency': 'CNY',
    'cny_amount': amount,
    'exchange_rate': '1',
    'conversion_status': 'ready',
    'category_id': null,
    'account_id': request.url.pathSegments[2],
    'from_account_id': null,
    'to_account_id': null,
    'occurred_at': '${date}T00:00:00',
    'note': '',
    'client_op_id': body['client_op_id'],
    'deleted_at': null,
    'server_version': serverVersion,
    'updated_at': '2026-09-15T00:00:00',
    'adjustment_meta': {
      'reason': reversesId == null ? 'balance_calibration' : 'reversal',
      'effective_on': date,
    },
    'reverses_transaction_id': reversesId,
  });
}

const _cnyAccount = Account(
  id: 'cny',
  name: '人民币账户',
  type: AccountType.asset,
  openingBalance: 100,
);

const _expense = FinanceTransaction(
  id: 'existing',
  date: '2026-09-15',
  type: TransactionType.expense,
  amount: 20,
  accountId: 'cny',
);

void main() {
  test('calibration draft allows zero and negative targets and rejects bad input',
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
    final now = DateTime(2026, 11, 3);

    CalibrationDraft build(double target, {String date = '2026-11-02'}) =>
        AssetRules.buildCalibrationDraft(
          account,
          targetCny: target,
          effectiveOn: date,
          createdAt: now,
        );

    expect(build(745.68).targetCny, 745.68);
    expect(build(0).targetCny, 0);
    expect(build(-12.5).targetCny, -12.5);
    // Drafting never rewrites the frozen opening snapshot.
    expect(account.openingBalance, 100);
    expect(account.openingCnyAmount, 700);

    expect(() => build(double.nan), throwsArgumentError);
    expect(() => build(double.infinity), throwsArgumentError);
    expect(() => build(0.004), throwsArgumentError);
    expect(() => build(1e14), throwsArgumentError);
    expect(() => build(100, date: '2026-11-04'), throwsArgumentError);
    expect(() => build(100, date: '2026-02-30'), throwsArgumentError);
  });

  test('calibration drafts survive state JSON round trips', () {
    const draft = CalibrationDraft(
      accountId: 'cny',
      targetCny: 125.5,
      effectiveOn: '2026-11-02',
      createdAt: '2026-11-03T09:30:00.000',
      expectedCurrentCny: 80.0,
    );
    const state = FinanceState(calibrationDrafts: [draft]);

    final restored = FinanceState.fromJson(state.toJson());
    final restoredDraft = restored.calibrationDraftFor('cny');

    expect(restoredDraft, isNotNull);
    expect(restoredDraft!.targetCny, 125.5);
    expect(restoredDraft.expectedCurrentCny, 80.0);
    expect(restoredDraft.effectiveOn, '2026-11-02');
    expect(restoredDraft.createdAt, '2026-11-03T09:30:00.000');
    expect(state.copyWith(calibrationDrafts: const []).calibrationDrafts,
        isEmpty);
  });

  test('offline calibration keeps an unsubmitted draft and never changes balance',
      () async {
    final store = _store(const FinanceState(
      currentMonth: '2026-09',
      accounts: [_cnyAccount],
      transactions: [_expense],
    ));

    await store.calibrateBalance(store.accounts.single, 125,
        effectiveOn: '2026-09-15');

    expect(store.accountBalances.single.balance, 80);
    expect(store.state.transactions.single.type, TransactionType.expense);
    expect(store.repository.queue.pending(), isEmpty);
    final draft = store.calibrationDraftFor('cny');
    expect(draft, isNotNull);
    expect(draft!.targetCny, 125);
    expect(draft.effectiveOn, '2026-09-15');
    expect(draft.expectedCurrentCny, 80);
    expect(store.message, contains('未提交'));
  });

  test('a target equal to the replay balance creates nothing', () async {
    final store = _store(const FinanceState(
      accounts: [_cnyAccount],
      transactions: [_expense],
    ));

    await store.calibrateBalance(store.accounts.single, 80,
        effectiveOn: '2026-09-15');

    expect(store.message, '余额已一致，无需校准');
    expect(store.calibrationDraftFor('cny'), isNull);
    expect(store.state.transactions.single.type, TransactionType.expense);
    expect(store.repository.queue.pending(), isEmpty);
  });

  test('calibration posts the v2 command and adopts the authoritative adjustment',
      () async {
    final requests = <http.Request>[];
    final store = _onlineStore(
      const FinanceState(
        currentMonth: '2026-09',
        accounts: [_cnyAccount],
        transactions: [_expense],
      ),
      MockClient((request) async {
        requests.add(request);
        return _adjustmentResponse(request, '45.000000');
      }),
    );

    await store.calibrateBalance(store.accounts.single, 125,
        effectiveOn: '2026-09-15');

    final request = requests.single;
    expect(request.method, 'POST');
    expect(request.url.path, '/assets/accounts/cny/calibration');
    // The protocol header is added once, in the shared transport.
    expect(request.headers['x-wealthmate-sync-protocol'], '2');
    final body = jsonDecode(request.body) as Map<String, Object?>;
    expect(body['target_cny'], '125.00');
    expect(body['effective_on'], '2026-09-15');
    expect(body['expected_current_cny'], '80.000000');
    expect(body['client_op_id'], isNotEmpty);
    expect(body['adjustment_id'], isNotEmpty);

    final adjustment = store.state.transactions.firstWhere(
        (item) => item.type == TransactionType.adjustment);
    expect(adjustment.amount, 45);
    expect(adjustment.serverVersion, 5);
    expect(adjustment.adjustmentMeta?['reason'], 'balance_calibration');
    expect(store.accountBalances.single.balance, 125);
    expect(store.calibrationDraftFor('cny'), isNull);
    // Adjustments never enter the normal transaction push queue.
    expect(store.repository.queue.pending(), isEmpty);
    expect(store.message, '余额校准已提交');
  });

  test('409 balance_changed rolls the optimistic row back and asks for a recheck',
      () async {
    final requests = <http.Request>[];
    final store = _onlineStore(
      const FinanceState(
        accounts: [_cnyAccount],
        transactions: [_expense],
      ),
      MockClient((request) async {
        requests.add(request);
        return _json(409, {
          'code': 'balance_changed',
          'detail': 'Account balance changed; reload before calibrating',
        });
      }),
    );

    await store.calibrateBalance(store.accounts.single, 125,
        effectiveOn: '2026-09-15');

    expect(requests, hasLength(1));
    expect(store.state.transactions.single.id, 'existing');
    expect(store.accountBalances.single.balance, 80);
    expect(store.calibrationDraftFor('cny'), isNull);
    expect(store.message, '账目已变化，请重新核对校准');
    expect(store.repository.queue.pending(), isEmpty);
  });

  test('reversal posts a dedicated command and cannot be reversed again',
      () async {
    const original = FinanceTransaction(
      id: 'adj-1',
      date: '2026-09-10',
      type: TransactionType.adjustment,
      amount: 45,
      accountId: 'cny',
      cnyAmount: 45,
      exchangeRate: 1,
      adjustmentMeta: {
        'reason': 'balance_calibration',
        'target_cny': '125.00',
        'basis_balance_cny': '80.000000',
        'effective_on': '2026-09-10',
      },
      serverVersion: 4,
    );
    final requests = <http.Request>[];
    final store = _onlineStore(
      const FinanceState(
        accounts: [_cnyAccount],
        transactions: [_expense, original],
      ),
      MockClient((request) async {
        requests.add(request);
        return _adjustmentResponse(request, '-45.000000',
            reversesId: original.id, serverVersion: 6);
      }),
    );

    await store.reverseAdjustment(original);

    final request = requests.single;
    expect(request.url.path, '/assets/accounts/cny/calibrations/adj-1/reverse');
    expect(request.headers['x-wealthmate-sync-protocol'], '2');
    final body = jsonDecode(request.body) as Map<String, Object?>;
    expect(body['client_op_id'], isNotEmpty);
    expect(body['adjustment_id'], isNotEmpty);
    final reversal = store.state.transactions
        .firstWhere((item) => item.reversesTransactionId == 'adj-1');
    expect(reversal.amount, -45);
    expect(reversal.isReversal, isTrue);
    expect(store.accountBalances.single.balance, 80);
    expect(store.message, '校准已撤销');
    expect(store.repository.queue.pending(), isEmpty);

    await store.reverseAdjustment(reversal);
    expect(requests, hasLength(1));
  });

  test('a rate refresh after calibration does not move the adjusted balance',
      () async {
    const usdAccount = Account(
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
    const coffee = FinanceTransaction(
      id: 'coffee',
      date: '2026-09-15',
      type: TransactionType.expense,
      amount: 70,
      accountId: 'usd',
    );
    final store = _onlineStore(
      const FinanceState(accounts: [usdAccount], transactions: [coffee]),
      MockClient((request) async {
        final body = jsonDecode(request.body) as Map<String, Object?>;
        expect(body['expected_current_cny'], '630.000000');
        return _adjustmentResponse(request, '20.000000');
      }),
    );

    await store.calibrateBalance(store.accounts.single, 650,
        effectiveOn: '2026-09-15');
    expect(store.accountBalances.single.balance, 650);

    await store.saveManualExchangeRate(
        baseCurrency: 'USD', rate: 8, rateDate: '2026-11-03', source: 'public');

    final account = store.accounts.single;
    expect(account.openingCnyAmount, 700);
    expect(account.exchangeRate, 7);
    expect(store.accountBalances.single.balance, 650);
  });

  testWidgets('calibration dialog previews before/after and keeps the draft',
      (tester) async {
    final store = _store(const FinanceState(
      accounts: [_cnyAccount],
      transactions: [_expense],
    ));

    await tester.pumpWidget(MaterialApp(
      home: AccountDetailPage(store: store, account: store.accounts.single),
    ));
    await tester.drag(find.byType(ListView), const Offset(0, -500));
    await tester.pumpAndSettle();
    await tester.tap(find.text('余额校准'));
    await tester.pumpAndSettle();

    expect(find.text('校准前账面额 ¥80'), findsOneWidget);

    await tester.enterText(find.byType(TextField).last, '125');
    await tester.pumpAndSettle();

    expect(find.text('差额 +¥45.00'), findsOneWidget);
    expect(find.text('校准后 ¥125'), findsOneWidget);

    await tester.tap(find.text('提交校准'));
    await tester.pumpAndSettle();

    expect(store.calibrationDraftFor('cny')?.targetCny, 125);
    expect(store.accountBalances.single.balance, 80);
    expect(find.textContaining('未提交'), findsWidgets);

    await tester.tap(find.text('保存账户配置'));
    await tester.pumpAndSettle();

    expect(store.accountBalances.single.balance, 80);
    expect(store.calibrationDraftFor('cny')?.targetCny, 125);
  });

  test('pending foreign conversion blocks calibration instead of guessing',
      () async {
    const usd = Account(
      id: 'usd',
      name: '美元账户',
      type: AccountType.asset,
      currency: 'USD',
      openingBalance: 100,
    );
    const foreignExpense = FinanceTransaction(
      id: 'foreign',
      date: '2026-09-15',
      type: TransactionType.expense,
      amount: 5,
      accountId: 'usd',
      currency: 'USD',
      conversionStatus: 'pending',
    );
    final store = _store(const FinanceState(
      accounts: [usd],
      transactions: [foreignExpense],
    ));

    await store.calibrateBalance(store.accounts.single, 100,
        effectiveOn: '2026-09-15');

    expect(store.message, '账户存在待换算账目，请先补充汇率');
    expect(store.state.transactions.single.type, TransactionType.expense);
    expect(store.calibrationDraftFor('usd'), isNull);
  });
}
