import 'dart:convert';

import 'package:flutter/material.dart' show DateTimeRange;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:wealthmate_flutter/core/database/local_state_session.dart';
import 'package:wealthmate_flutter/data/api_client.dart';
import 'package:wealthmate_flutter/data/finance_repository.dart';
import 'package:wealthmate_flutter/data/local_repository.dart';
import 'package:wealthmate_flutter/data/sync_queue.dart';
import 'package:wealthmate_flutter/domain/finance_rules.dart';
import 'package:wealthmate_flutter/domain/models.dart';
import 'package:wealthmate_flutter/features/assets/domain/asset_rules.dart';
import 'package:wealthmate_flutter/features/budget/domain/budget_rules.dart';
import 'package:wealthmate_flutter/features/insights/domain/insight_rules.dart';
import 'package:wealthmate_flutter/features/ledger/data/ledger_repository.dart';
import 'package:wealthmate_flutter/features/ledger/state/ledger_store.dart';
import 'package:wealthmate_flutter/features/quick_entry/domain/quick_entry_context.dart';

class _MemoryStore implements KeyValueStore {
  final values = <String, String>{};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;
}

const _cny = Account(
  id: 'cny',
  name: '人民币账户',
  type: AccountType.asset,
  openingBalance: 100,
);

const _expense = FinanceTransaction(
  id: 'food',
  date: '2026-09-10',
  type: TransactionType.expense,
  amount: 20,
  accountId: 'cny',
  categoryId: 'food-category',
);

const _adjustment = FinanceTransaction(
  id: 'adj-1',
  date: '2026-09-20',
  type: TransactionType.adjustment,
  amount: 30,
  accountId: 'cny',
  cnyAmount: 30,
  exchangeRate: 1,
  adjustmentMeta: {
    'reason': 'balance_calibration',
    'target_cny': '110.00',
    'basis_balance_cny': '80.000000',
    'effective_on': '2026-09-20',
  },
);

void main() {
  test('adjustment JSON keeps its kind, signed amount and metadata', () {
    final json = <String, Object?>{
      'id': 'adj-1',
      'date': '2026-09-20',
      'occurred_on': '2026-09-20',
      'type': 'adjustment',
      'kind': 'adjustment',
      'amount': '-25.500000',
      'currency': 'CNY',
      'original_amount': '-25.500000',
      'original_currency': 'CNY',
      'cny_amount': '-25.500000',
      'exchange_rate': '1',
      'conversion_status': 'ready',
      'category_id': null,
      'account_id': 'cny',
      'from_account_id': null,
      'to_account_id': null,
      'occurred_at': '2026-09-20T00:00:00',
      'note': '',
      'client_op_id': 'cal-1',
      'deleted_at': null,
      'server_version': 7,
      'updated_at': '2026-09-20T00:00:00',
      'adjustment_meta': {
        'reason': 'balance_calibration',
        'target_cny': '125.00',
        'basis_balance_cny': '150.500000',
        'effective_on': '2026-09-20',
      },
      'reverses_transaction_id': null,
    };

    final parsed = FinanceTransaction.fromJson(json);

    expect(transactionTypeFromJson('adjustment'), TransactionType.adjustment);
    expect(transactionTypeFromJson('mystery'), TransactionType.expense);
    expect(parsed.type, TransactionType.adjustment);
    expect(parsed.isAdjustment, isTrue);
    expect(parsed.isReversal, isFalse);
    expect(parsed.amount, -25.5);
    expect(parsed.cnyAmount, -25.5);
    expect(parsed.exchangeRate, 1);
    expect(parsed.adjustmentMeta?['reason'], 'balance_calibration');
    expect(parsed.reversesTransactionId, isNull);

    final restored = FinanceTransaction.fromJson(parsed.toJson());
    expect(restored.type, TransactionType.adjustment);
    expect(restored.amount, -25.5);
    expect(restored.adjustmentMeta?['target_cny'], '125.00');
  });

  test('asset and liability balances both add the signed adjustment directly',
      () {
    const liability = Account(
      id: 'card',
      name: '信用卡',
      type: AccountType.liability,
      openingBalance: 0,
    );
    const state = FinanceState(accounts: [_cny, liability], transactions: [
      _expense,
      _adjustment,
      FinanceTransaction(
        id: 'debt-up',
        date: '2026-09-21',
        type: TransactionType.adjustment,
        amount: 50,
        accountId: 'card',
        cnyAmount: 50,
      ),
      FinanceTransaction(
        id: 'debt-down',
        date: '2026-09-22',
        type: TransactionType.adjustment,
        amount: -30,
        accountId: 'card',
        cnyAmount: -30,
      ),
    ]);

    final balances = {
      for (final item in AssetRules.accountBalances(state, state.transactions))
        item.account.id: item.balance,
    };

    // 100 - 20 + 30; liability starts at 0 and moves by +50 -30.
    expect(balances['cny'], 110);
    expect(balances['card'], 20);

    final assetReplay =
        AssetRules.replayBalance(state, _cny, asOfDate: '2026-09-30');
    expect(assetReplay.rawCny, 110);
    expect(assetReplay.pending, 0);
  });

  test('date replay excludes adjustments and entries after the effective date',
      () {
    const state = FinanceState(accounts: [_cny], transactions: [
      _expense,
      _adjustment,
    ]);

    expect(AssetRules.replayBalance(state, _cny, asOfDate: '2026-09-19').rawCny,
        80);
    expect(AssetRules.replayBalance(state, _cny, asOfDate: '2026-09-20').rawCny,
        110);
    // Before the expense date only the opening balance applies.
    expect(AssetRules.replayBalance(state, _cny, asOfDate: '2026-09-09').rawCny,
        100);
  });

  test('income, expense, savings, budgets and quick-entry ignore adjustments',
      () {
    const state = FinanceState(
      currentMonth: '2026-09',
      accounts: [_cny],
      categories: [
        Category(id: 'food-category', name: '餐饮', type: TransactionType.expense),
        Category(id: 'salary', name: '工资', type: TransactionType.income),
      ],
      transactions: [
        FinanceTransaction(
          id: 'salary',
          date: '2026-09-05',
          type: TransactionType.income,
          amount: 100,
          accountId: 'cny',
          categoryId: 'salary',
        ),
        _expense,
        FinanceTransaction(
          id: 'same-day-adjustment',
          date: '2026-09-10',
          type: TransactionType.adjustment,
          amount: 500,
          accountId: 'cny',
          cnyAmount: 500,
        ),
      ],
      budgets: [
        Budget(
          id: 'budget-food',
          month: '2026-09',
          categoryId: 'food-category',
          limit: 100,
        ),
      ],
    );

    final metrics = FinanceRules.deriveMetrics(state, '2026-09');
    expect(metrics.income, 100);
    expect(metrics.expense, 20);
    expect(metrics.savings, 80);
    expect(metrics.savingsRate, 0.8);

    final budget = progressForMonth(state, '2026-09').single;
    expect(budget.spent, 20);

    final byCategory = InsightRules.expenseByCategory(
        state, DateTimeRange(start: DateTime(2026, 9, 1), end: DateTime(2026, 9, 30)));
    expect(byCategory['food-category'], 20);

    final context = QuickEntryContextBuilder.build(
        state: state, now: DateTime(2026, 9, 10));
    final cny = context.currency('CNY');
    expect(cny, isNotNull);
    // The same-day adjustment must not inflate the expense aggregate.
    expect(cny!.targetDay.count, 1);
    expect(cny.targetDay.cents, 2000);
    expect(cny.targetDay.categoryTotals, isEmpty);
    expect(cny.referenceDay.count, 0);
    expect(cny.referenceDay.cents, 0);
  });

  test('upgraded clients pull the full history once before resuming the cursor',
      () async {
    final cursors = <int>[];
    final protocols = <String?>[];
    final client = MockClient((request) async {
      expect(request.url.path, '/sync/pull');
      cursors.add(int.parse(request.url.queryParameters['since_version']!));
      protocols.add(request.headers['x-wealthmate-sync-protocol']);
      return http.Response(
        jsonEncode({
          'items': const <Object?>[],
          'accounts': const <Object?>[],
          'categories': const <Object?>[],
          'budgets': const <Object?>[],
          'server_version': 6,
        }),
        200,
        headers: const {'content-type': 'application/json; charset=utf-8'},
      );
    });
    final repository = FinanceRepository(
      local: LocalRepository(_MemoryStore()),
      queue: SyncQueue(),
      api: ApiClient(
        baseUrl: 'https://sync.test',
        token: 'sync-token',
        client: client,
      ),
    );
    await repository.ensureLocalOwner('adjustment-user');

    final first = await repository.pullChanges(const FinanceState(
      financialSchemaVersion: 1,
      syncState: SyncState(serverVersion: 5),
    ));

    expect(cursors, [0]);
    expect(first.financialSchemaVersion, 3);
    expect(first.syncState.serverVersion, 6);

    await repository.pullChanges(first);
    expect(cursors, [0, 6]);
    expect(protocols, ['2', '2']);
  });

  test('ledger mutations refuse to edit or delete an adjustment', () async {
    final session = LocalStateSession(
        local: LocalRepository(_MemoryStore()), queue: SyncQueue());
    final store = LedgerStore(
      repository: LedgerRepository(session: session),
      initialState: const FinanceState(
        accounts: [_cny],
        transactions: [_adjustment],
      ),
    );

    await store.updateTransaction(_adjustment.copyWith(note: 'changed'));
    expect(store.message, '余额校准流水不可编辑，请撤销后重新校准');
    expect(store.transactions.single.note, '');

    await store.deleteTransaction(_adjustment.id);
    expect(store.message, '余额校准流水不可删除，请使用撤销校准');
    expect(store.transactions.single.deletedAt, isNull);
    expect(store.repository.queue.pending(), isEmpty);
  });
}
