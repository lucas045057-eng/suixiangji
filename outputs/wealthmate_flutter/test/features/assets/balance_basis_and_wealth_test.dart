import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:wealthmate_flutter/core/database/local_state_session.dart';
import 'package:wealthmate_flutter/data/api_client.dart';
import 'package:wealthmate_flutter/data/local_repository.dart';
import 'package:wealthmate_flutter/data/sync_queue.dart';
import 'package:wealthmate_flutter/domain/cny_amount.dart';
import 'package:wealthmate_flutter/domain/models.dart';
import 'package:wealthmate_flutter/features/assets/data/assets_remote_data_source.dart';
import 'package:wealthmate_flutter/features/assets/data/assets_repository.dart';
import 'package:wealthmate_flutter/features/assets/state/asset_store.dart';
import 'package:wealthmate_flutter/features/ledger/data/ledger_repository.dart';
import 'package:wealthmate_flutter/features/ledger/state/ledger_store.dart';
import 'package:wealthmate_flutter/ui/wealth_page.dart';

class _MemoryStore implements KeyValueStore {
  final values = <String, String>{};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;
}

const _account = Account(
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

const _initialState = FinanceState(
  accounts: [_account],
  transactions: [_expense],
);

http.Response _json(int status, Map<String, Object?> body) => http.Response(
      jsonEncode(body),
      status,
      headers: const {'content-type': 'application/json; charset=utf-8'},
    );

http.Response _basis(
  http.Request request, {
  required String token,
  String balance = '80.000000',
  String? expiresAt = '2030-01-01T00:00:00+00:00',
}) {
  final accountId = request.url.pathSegments[2];
  final date = request.url.queryParameters['effective_on'] ?? '2026-09-15';
  return _json(200, {
    'account_id': accountId,
    'effective_on': date,
    'balance_cny': balance,
    'basis_version': 1,
    'basis_token': token,
    'ttl_seconds': 600,
    'expires_at': expiresAt ??
        DateTime.now()
            .toUtc()
            .add(const Duration(minutes: 10))
            .toIso8601String(),
    'server_version': 9,
  });
}

http.Response _adjustment(http.Request request, String amount) {
  final body = jsonDecode(request.body) as Map<String, Object?>;
  final date = body['effective_on'] as String;
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
    'server_version': 10,
    'updated_at': '2026-09-15T00:00:00',
    'adjustment_meta': {'reason': 'balance_calibration', 'effective_on': date},
    'reverses_transaction_id': null,
  });
}

AssetStore _storeWith(
  MockClient client, {
  FinanceState initialState = _initialState,
}) {
  final api = ApiClient(
    baseUrl: 'https://basis.test',
    token: 'basis-token',
    client: client,
  );
  return AssetStore(
    repository: AssetsRepository(
      session: LocalStateSession(
        local: LocalRepository(_MemoryStore()),
        queue: SyncQueue(),
      ),
      remote: AssetsRemoteDataSource(api: api),
    ),
    initialState: initialState,
  );
}

http.Response _error(String code, int status) =>
    _json(status, {'code': code, 'detail': code});

void main() {
  test('CnyAmount keeps six-decimal server strings exact', () {
    final value = CnyAmount.tryParse('1000.123456')!;
    expect(value.toFixed6(), '1000.123456');
    expect(CnyAmount.tryParse('-0.000001')!.toFixed6(), '-0.000001');
    expect(CnyAmount.tryParse('0.1')!.toFixed6(), '0.100000');
    expect(CnyAmount.tryParse('1.1234567'), isNull);
    expect(CnyAmount.tryParse('abc'), isNull);
    final delta = CnyAmount.fromDouble(125.00) - value;
    expect(delta.toFixed6(), '-875.123456');
  });

  test('a calibration draft persists its token and operation identity', () {
    const draft = CalibrationDraft(
      accountId: 'cny',
      targetCny: 125,
      effectiveOn: '2026-09-15',
      createdAt: '2026-11-03T08:00:00.000',
      expectedCurrentCny: 80,
      basisToken: 'b1.persisted',
      basisExpiresAt: '2026-11-03T08:10:00+00:00',
      basisBalanceCny: '80.000000',
      clientOpId: 'cal-original',
      adjustmentId: 'adj-original',
    );
    final restored = FinanceState.fromJson(
            const FinanceState(calibrationDrafts: [draft]).toJson())
        .calibrationDraftFor('cny')!;
    expect(restored.basisToken, 'b1.persisted');
    expect(restored.basisExpiresAt, '2026-11-03T08:10:00+00:00');
    expect(restored.basisBalanceCny, '80.000000');
    expect(restored.clientOpId, 'cal-original');
    expect(restored.adjustmentId, 'adj-original');
  });

  test('a signed basis token is submitted and the numeric fallback is omitted',
      () async {
    final requests = <http.Request>[];
    final store = _storeWith(MockClient((request) async {
      requests.add(request);
      if (request.method == 'GET') return _basis(request, token: 'b1.t1');
      return _adjustment(request, '45.000000');
    }));

    await store.calibrateBalance(store.accounts.single, 125,
        effectiveOn: '2026-09-15');

    expect(requests.map((item) => item.method), ['GET', 'POST']);
    expect(requests.first.url.path, '/assets/accounts/cny/balance-basis');
    expect(requests.first.headers['x-wealthmate-sync-protocol'], '2');
    final body = jsonDecode(requests.last.body) as Map<String, Object?>;
    expect(body['basis_token'], 'b1.t1');
    expect(body.containsKey('expected_current_cny'), isFalse);
    final adjustment = store.state.transactions
        .firstWhere((item) => item.type == TransactionType.adjustment);
    expect(adjustment.amount, 45);
    expect(store.message, '余额校准已提交');
    expect(store.calibrationDraftFor('cny'), isNull);
  });

  test('basis_expired refetches a basis and waits for the user to reconfirm',
      () async {
    var basisCalls = 0;
    final requests = <http.Request>[];
    final store = _storeWith(MockClient((request) async {
      requests.add(request);
      if (request.method == 'GET') {
        basisCalls++;
        return _basis(request, token: 'b1.$basisCalls');
      }
      return _error('basis_expired', 409);
    }));

    await store.calibrateBalance(store.accounts.single, 125,
        effectiveOn: '2026-09-15');

    expect(requests.map((item) => item.method), ['GET', 'POST', 'GET']);
    expect(basisCalls, 2);
    expect(store.state.transactions.single.id, 'existing');
    expect(store.accountBalances.single.balance, 80);
    final draft = store.calibrationDraftFor('cny');
    expect(draft, isNotNull);
    expect(draft!.basisToken, 'b1.2');
    expect(draft.targetCny, 125);
    expect(draft.clientOpId, isNotNull);
    expect(store.message, contains('重新提交'));
    expect(store.repository.queue.pending(), isEmpty);
  });

  test('basis_scope_mismatch never reuses another account or date', () async {
    final store = _storeWith(MockClient((request) async {
      if (request.method == 'GET') return _basis(request, token: 'b1.other');
      return _error('basis_scope_mismatch', 422);
    }));

    await store.calibrateBalance(store.accounts.single, 125,
        effectiveOn: '2026-09-15');

    expect(store.calibrationDraftFor('cny'), isNull);
    expect(store.state.transactions.single.id, 'existing');
    expect(store.message, '校准基准与账户或日期不匹配，请重新校准');
    expect(store.repository.queue.pending(), isEmpty);
  });

  test('balance_changed writes nothing and asks for a refresh, no rebase',
      () async {
    final requests = <http.Request>[];
    final store = _storeWith(MockClient((request) async {
      requests.add(request);
      if (request.method == 'GET') {
        return _basis(request, token: 'b1.stale', balance: '80.000000');
      }
      return _error('balance_changed', 409);
    }));

    await store.calibrateBalance(store.accounts.single, 125,
        effectiveOn: '2026-09-15');

    // No follow-up basis fetch: a changed balance is never auto-rebased.
    expect(requests.map((item) => item.method), ['GET', 'POST']);
    expect(store.state.transactions.single.id, 'existing');
    expect(store.calibrationDraftFor('cny'), isNull);
    expect(store.message, '账目已变化，请刷新账目后重新核对校准');
    expect(store.repository.queue.pending(), isEmpty);
  });

  test('conversion_pending never fabricates a zero basis', () async {
    var posted = 0;
    final store = _storeWith(MockClient((request) async {
      if (request.method == 'GET') {
        return _error('conversion_pending', 409);
      }
      posted++;
      return _adjustment(request, '45.000000');
    }));

    await store.calibrateBalance(store.accounts.single, 125,
        effectiveOn: '2026-09-15');

    expect(posted, 0);
    expect(store.state.transactions.single.id, 'existing');
    expect(store.calibrationDraftFor('cny'), isNull);
    expect(store.message, '账户存在待换算账目，请先补充汇率');
  });

  test('an unresolved submission retries with the same token and operation IDs',
      () async {
    final requests = <http.Request>[];
    const pending = CalibrationDraft(
      accountId: 'cny',
      targetCny: 125,
      effectiveOn: '2026-09-15',
      createdAt: '2026-11-03T08:00:00.000',
      expectedCurrentCny: 80,
      basisToken: 'b1.persisted',
      // Locally in the past on purpose: only the server may expire it.
      basisExpiresAt: '2020-01-01T00:00:00+00:00',
      basisBalanceCny: '80.000000',
      clientOpId: 'cal-original',
      adjustmentId: 'adj-original',
    );
    final store = _storeWith(
      MockClient((request) async {
        requests.add(request);
        return _adjustment(request, '45.000000');
      }),
      initialState: const FinanceState(
        accounts: [_account],
        transactions: [_expense],
        calibrationDrafts: [pending],
      ),
    );

    await store.calibrateBalance(store.accounts.single, 125,
        effectiveOn: '2026-09-15');

    // No local-expiry refetch: exactly one byte-identical retry.
    expect(requests, hasLength(1));
    expect(requests.single.method, 'POST');
    final body = jsonDecode(requests.single.body) as Map<String, Object?>;
    expect(body['basis_token'], 'b1.persisted');
    expect(body['client_op_id'], 'cal-original');
    expect(body['adjustment_id'], 'adj-original');
    expect(body.containsKey('expected_current_cny'), isFalse);
    expect(store.calibrationDraftFor('cny'), isNull);
  });

  test('V2 wealth as_of_date keeps pending balances null and never zero',
      () async {
    final requests = <http.Request>[];
    final store = _storeWith(MockClient((request) async {
      requests.add(request);
      return _json(200, {
        'as_of_date': '2026-09-30',
        'excludes_later_adjustments': true,
        'valuation_mode': 'frozen_cny_book_value',
        'total_assets': null,
        'total_liabilities': null,
        'net_worth': null,
        'known_total_assets': '1000.000000',
        'known_total_liabilities': '0.000000',
        'pending_conversion_count': 1,
        'accounts': [
          {
            'id': 'cny',
            'name': '人民币账户',
            'kind': 'asset',
            'currency': 'CNY',
            'cny_balance': '1000.000000',
            'cny_balance_exact': '1000.000000',
            'conversion_status': 'ready',
            'pending_conversion_count': 0,
          },
          {
            'id': 'usd',
            'name': '美元账户',
            'kind': 'asset',
            'currency': 'USD',
            'cny_balance': null,
            'cny_balance_exact': null,
            'conversion_status': 'pending',
            'pending_conversion_count': 1,
          },
        ],
        'server_version': 42,
      });
    }));

    await store.loadWealth(asOfDate: '2026-09-30');

    expect(requests.single.url.path, '/wealth');
    expect(requests.single.url.queryParameters['as_of_date'], '2026-09-30');
    expect(requests.single.headers['x-wealthmate-sync-protocol'], '2');
    final view = store.wealthView;
    expect(view, isNotNull);
    expect(view!.asOfDate, '2026-09-30');
    expect(view.excludesLaterAdjustments, isTrue);
    expect(view.valuationMode, 'frozen_cny_book_value');
    expect(view.netWorth, isNull);
    expect(view.netWorthDisplay, '待换算');
    expect(view.hasPending, isTrue);
    expect(view.knownTotalAssets, 1000);
    expect(view.accounts[0].displayBalance, '1000.000000');
    expect(view.accounts[1].cnyBalance, isNull);
    expect(view.accounts[1].displayBalance, '待换算');
    expect(store.message, contains('待换算'));
  });

  testWidgets('the wealth page shows pending totals as 待换算, never zero',
      (tester) async {
    final store = _storeWith(MockClient((request) async => _json(200, {
          'as_of_date': '2026-09-30',
          'excludes_later_adjustments': true,
          'valuation_mode': 'frozen_cny_book_value',
          'total_assets': null,
          'total_liabilities': null,
          'net_worth': null,
          'known_total_assets': '1000.000000',
          'known_total_liabilities': '0.000000',
          'pending_conversion_count': 1,
          'accounts': [
            {
              'id': 'usd',
              'name': '美元账户',
              'kind': 'asset',
              'currency': 'USD',
              'cny_balance': null,
              'cny_balance_exact': null,
              'conversion_status': 'pending',
              'pending_conversion_count': 1,
            },
          ],
          'server_version': 42,
        })));
    await store.loadWealth(asOfDate: '2026-09-30');

    final session = LocalStateSession(
      local: LocalRepository(_MemoryStore()),
      queue: SyncQueue(),
    );
    final ledger = LedgerStore(
      repository: LedgerRepository(session: session),
      initialState: _initialState,
    );
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: WealthPage(store: store, ledger: ledger),
      ),
    ));
    await tester.pump();

    expect(find.textContaining('截至 2026-09-30'), findsOneWidget);
    expect(find.text('待换算'), findsWidgets);
    expect(find.text('美元账户 · 待换算'), findsOneWidget);
  });
}
