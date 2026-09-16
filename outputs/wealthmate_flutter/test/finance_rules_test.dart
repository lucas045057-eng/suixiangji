import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:wealthmate_flutter/domain/finance_rules.dart';
import 'package:wealthmate_flutter/domain/models.dart';
import 'package:wealthmate_flutter/features/assets/domain/asset_rules.dart';

FinanceState stateWith({
  List<Account> accounts = const [],
  List<FinanceTransaction> transactions = const [],
  List<Budget> budgets = const [],
  List<Goal> goals = const [],
}) {
  return FinanceState(
    accounts: accounts,
    categories: const [
      Category(id: 'food', name: '餐饮'),
      Category(id: 'transport', name: '交通'),
      Category(id: 'salary', name: '工资'),
    ],
    transactions: transactions,
    budgets: budgets,
    goals: goals,
    currentMonth: '2026-09',
  );
}

FinanceTransaction tx({
  required String id,
  required TransactionType type,
  required double amount,
  String? accountId,
  String? categoryId,
  String? fromAccountId,
  String? toAccountId,
}) {
  return FinanceTransaction(
    id: id,
    date: '2026-09-01',
    type: type,
    amount: amount,
    accountId: accountId,
    categoryId: categoryId,
    fromAccountId: fromAccountId,
    toAccountId: toAccountId,
    note: id,
  );
}

void main() {
  test('asset rules keep missing foreign openings out of net worth', () {
    const state = FinanceState(accounts: [
      Account(
          id: 'cny', name: '人民币', type: AccountType.asset, openingBalance: 100),
      Account(
          id: 'usd',
          name: '美元',
          type: AccountType.asset,
          currency: 'USD',
          openingBalance: 100),
    ]);

    final balances = AssetRules.accountBalances(state, const []);

    expect(balances.map((item) => item.balance), [100, 0]);
  });

  test('asset income increases the asset balance', () {
    final state = stateWith(
      accounts: const [
        Account(
            id: 'bank',
            name: '银行卡',
            type: AccountType.asset,
            openingBalance: 100),
      ],
      transactions: [
        tx(
            id: 'income',
            type: TransactionType.income,
            amount: 500,
            accountId: 'bank',
            categoryId: 'salary'),
      ],
    );

    final metrics = FinanceRules.deriveMetrics(state, '2026-09');

    expect(metrics.income, 500);
    expect(metrics.accountBalances.single.balance, 600);
  });

  test('liability expense increases the liability balance', () {
    final state = stateWith(
      accounts: const [
        Account(
            id: 'credit',
            name: '信用卡',
            type: AccountType.liability,
            openingBalance: 200),
      ],
      transactions: [
        tx(
            id: 'expense',
            type: TransactionType.expense,
            amount: 80,
            accountId: 'credit',
            categoryId: 'food'),
      ],
    );

    final metrics = FinanceRules.deriveMetrics(state, '2026-09');

    expect(metrics.expense, 80);
    expect(metrics.accountBalances.single.balance, 280);
    expect(metrics.liabilities, 280);
  });

  test('transfer changes accounts but does not enter cash-flow totals', () {
    final state = stateWith(
      accounts: const [
        Account(
            id: 'cash',
            name: '现金',
            type: AccountType.asset,
            openingBalance: 100),
        Account(
            id: 'bank',
            name: '银行卡',
            type: AccountType.asset,
            openingBalance: 0),
      ],
      transactions: [
        tx(
            id: 'transfer',
            type: TransactionType.transfer,
            amount: 40,
            fromAccountId: 'cash',
            toAccountId: 'bank'),
      ],
    );

    final metrics = FinanceRules.deriveMetrics(state, '2026-09');

    expect(metrics.income, 0);
    expect(metrics.expense, 0);
    expect(metrics.accountBalances.first.balance, 60);
    expect(metrics.accountBalances.last.balance, 40);
  });

  test('budget status changes at 80 percent and 100 percent', () {
    final state = stateWith(
      accounts: const [
        Account(id: 'bank', name: '银行卡', type: AccountType.asset),
      ],
      transactions: [
        tx(
            id: 'food',
            type: TransactionType.expense,
            amount: 80,
            accountId: 'bank',
            categoryId: 'food'),
        tx(
            id: 'transport',
            type: TransactionType.expense,
            amount: 100,
            accountId: 'bank',
            categoryId: 'transport'),
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
      ],
    );

    final budgets = FinanceRules.deriveMetrics(state, '2026-09').budgetProgress;

    expect(budgets.first.status, BudgetStatus.warning);
    expect(budgets.last.status, BudgetStatus.over);
  });

  test('natural language expense becomes a high-confidence reviewable draft',
      () {
    final draft = FinanceRules.parseNaturalLanguage(
      '今天中午外卖 32 元，支付宝',
      now: DateTime(2026, 9, 1, 10),
    );

    expect(draft.amount, 32);
    expect(draft.type, TransactionType.expense);
    expect(draft.categoryId, 'food');
    expect(draft.accountId, 'alipay');
    expect(draft.confidence, greaterThanOrEqualTo(.85));
    expect(FinanceRules.canPostDraft(draft), isTrue);
  });

  test('natural language parses Chinese amount units equivalently', () {
    final examples = <String, double>{
      '今天中午外卖 16块86，支付宝': 16.86,
      '今天中午外卖 16元8角6分，支付宝': 16.86,
      '今天中午外卖 16元8毛6，支付宝': 16.86,
      '今天中午外卖 两元，支付宝': 2.00,
      '今天中午外卖 两块，支付宝': 2.00,
      '今天中午外卖 两块五，支付宝': 2.50,
      '今天中午外卖 2块5，支付宝': 2.50,
      '今天中午外卖 16.86元，支付宝': 16.86,
      '今天中午外卖 32元，支付宝': 32.00,
    };

    for (final entry in examples.entries) {
      final draft = FinanceRules.parseNaturalLanguage(
        entry.key,
        now: DateTime(2026, 9, 1, 10),
      );

      expect(draft.amount, closeTo(entry.value, 0.001), reason: entry.key);
      expect(draft.confidence, greaterThanOrEqualTo(.85), reason: entry.key);
      expect(FinanceRules.canPostDraft(draft), isTrue, reason: entry.key);
    }
  });

  test('natural language does not invent unparseable amounts', () {
    final examples = [
      '今天中午外卖好多钱，支付宝',
      '今天中午外卖 十百元，支付宝',
      '今天中午外卖 16.860元，支付宝',
      '今天中午外卖 16元5厘，支付宝',
      '今天中午外卖 16元8角6厘，支付宝',
      '今天中午外卖 0元，支付宝',
    ];

    for (final text in examples) {
      final draft = FinanceRules.parseNaturalLanguage(
        text,
        now: DateTime(2026, 9, 1, 10),
      );

      expect(draft.amount, 0, reason: text);
      expect(draft.missingFacts, contains('请输入金额'), reason: text);
      expect(FinanceRules.canPostDraft(draft), isFalse, reason: text);
    }
  });

  test('natural language parses Chinese ten-thousand shorthand', () {
    const examples = <String, double>{
      '今天中午外卖 一万二元，支付宝': 12000,
      '今天中午外卖 二万三元，支付宝': 23000,
    };

    for (final entry in examples.entries) {
      final draft = FinanceRules.parseNaturalLanguage(
        entry.key,
        now: DateTime(2026, 9, 1, 10),
      );
      expect(draft.amount, closeTo(entry.value, 0.001), reason: entry.key);
    }
  });

  test('missing account and low confidence drafts cannot post', () {
    final noAccount = FinanceRules.parseNaturalLanguage(
      '今天中午外卖 32 元',
      now: DateTime(2026, 9, 1, 10),
    );
    final lowConfidence = noAccount
        .copyWith(accountId: 'alipay', confidence: .72, missingFacts: const []);

    expect(noAccount.missingFacts, contains('请选择支付账户'));
    expect(FinanceRules.canPostDraft(noAccount), isFalse);
    expect(FinanceRules.canPostDraft(lowConfidence), isFalse);
  });

  test('natural language draft uses custom labels and recent account habit',
      () {
    final state = FinanceState(
      defaultAccountId: 'wechat',
      accounts: const [
        Account(
            id: 'wechat',
            name: '我的微信',
            type: AccountType.asset,
            accountKind: AccountKind.wechat),
        Account(
            id: 'bank',
            name: '招商银行卡',
            type: AccountType.asset,
            accountKind: AccountKind.bankCard),
      ],
      categories: const [
        Category(id: 'food', name: '日常饮食'),
      ],
      transactions: const [
        FinanceTransaction(
            id: 'recent-food',
            date: '2026-09-03',
            type: TransactionType.expense,
            amount: 28,
            categoryId: 'food',
            accountId: 'wechat'),
      ],
    );

    final draft = FinanceRules.completeNaturalLanguageDraft(
      '今天吃饭吃了30元',
      now: DateTime(2026, 9, 4, 10),
      state: state,
    );

    expect(draft.amount, 30);
    expect(draft.categoryId, 'food');
    expect(draft.accountId, 'wechat');
    expect(draft.date, '2026-09-04');
    expect(draft.confidence, greaterThanOrEqualTo(.85));
  });

  test('quick memory survives finance state serialization', () {
    final state = FinanceState(
      quickMemories: const [
        QuickMemory(key: '吃饭', categoryId: 'food', accountId: 'alipay')
      ],
    );

    final restored = FinanceState.fromJson(state.toJson());

    expect(restored.quickMemories.single.key, '吃饭');
    expect(restored.quickMemories.single.categoryId, 'food');
    expect(restored.quickMemories.single.accountId, 'alipay');
  });

  test('user profile preserves editable identity fields', () {
    final profile = UserProfile.fromJson(const {
      'id': 'user-1',
      'username': 'linmo',
      'display_name': '林默',
      'quick_memories': [
        {'key': '吃饭', 'category_id': 'food', 'account_id': 'alipay'}
      ],
    });

    final restored = UserProfile.fromJson(profile.toJson());

    expect(restored.username, 'linmo');
    expect(restored.displayName, '林默');
    expect(restored.quickMemories.single.accountId, 'alipay');
  });

  test('account and transaction JSON preserve V1.1 contract fields', () {
    const account = Account(
      id: 'fund',
      name: '基金账户',
      type: AccountType.asset,
      accountKind: AccountKind.fundInvestment,
    );
    final restoredAccount = Account.fromJson(account.toJson());
    expect(restoredAccount.accountKind, AccountKind.fundInvestment);

    const transaction = FinanceTransaction(
      id: 'timed',
      date: '2026-09-03',
      occurredAt: '2026-09-03T18:42:00+08:00',
      type: TransactionType.expense,
      amount: 12.5,
    );
    final restoredTransaction =
        FinanceTransaction.fromJson(transaction.toJson());
    expect(restoredTransaction.occurredAt, '2026-09-03T18:42:00+08:00');
  });

  test(
      'period expense series uses hourly buckets for today and excludes transfers and pending FX',
      () {
    final state = stateWith(
      transactions: [
        FinanceTransaction(
            id: 'morning',
            date: '2026-09-03',
            occurredAt: '2026-09-03T09:20:00+08:00',
            type: TransactionType.expense,
            amount: 12,
            categoryId: 'food'),
        FinanceTransaction(
            id: 'noon',
            date: '2026-09-03',
            occurredAt: '2026-09-03T12:40:00+08:00',
            type: TransactionType.expense,
            amount: 20,
            categoryId: 'transport'),
        const FinanceTransaction(
            id: 'pending',
            date: '2026-09-03',
            type: TransactionType.expense,
            amount: 99,
            currency: 'USD',
            categoryId: 'food'),
        const FinanceTransaction(
            id: 'transfer',
            date: '2026-09-03',
            type: TransactionType.transfer,
            amount: 200,
            fromAccountId: 'cash',
            toAccountId: 'bank'),
      ],
    );

    final points = FinanceRules.periodExpenseSeries(state,
        DateTimeRange(start: DateTime(2026, 9, 3), end: DateTime(2026, 9, 3)));

    expect(points, hasLength(24));
    expect(points[9].expense, 12);
    expect(points[12].expense, 20);
    expect(points.fold<double>(0, (sum, item) => sum + item.expense), 32);
  });

  test(
      'period category totals are programmatic and pie percentages can cover all converted expense',
      () {
    final state = stateWith(
      transactions: [
        const FinanceTransaction(
            id: 'food-1',
            date: '2026-09-01',
            type: TransactionType.expense,
            amount: 30,
            categoryId: 'food'),
        const FinanceTransaction(
            id: 'food-2',
            date: '2026-09-02',
            type: TransactionType.expense,
            amount: 20,
            categoryId: 'food'),
        const FinanceTransaction(
            id: 'transport',
            date: '2026-09-03',
            type: TransactionType.expense,
            amount: 50,
            categoryId: 'transport'),
      ],
    );
    final categories = FinanceRules.expenseByCategory(state,
        DateTimeRange(start: DateTime(2026, 9, 1), end: DateTime(2026, 9, 7)));

    expect(categories['food'], 50);
    expect(categories['transport'], 50);
    expect(
        categories.values
            .map((value) =>
                value /
                categories.values.fold<double>(0, (sum, item) => sum + item))
            .fold<double>(0, (sum, item) => sum + item),
        closeTo(1, 0.0001));
  });
}
