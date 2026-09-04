import 'package:flutter/material.dart';

import 'models.dart';

class PeriodPoint {
  const PeriodPoint(
      {required this.bucket,
      required this.label,
      required this.expense,
      required this.income});

  final DateTime bucket;
  final String label;
  final double expense;
  final double income;
}

class FinanceRules {
  static const double confirmationThreshold = .85;

  static List<PeriodPoint> periodExpenseSeries(
      FinanceState state, DateTimeRange range) {
    final start =
        DateTime(range.start.year, range.start.month, range.start.day);
    final end = DateTime(range.end.year, range.end.month, range.end.day);
    final sameDay = start == end;
    final points = <PeriodPoint>[];
    if (sameDay) {
      for (var hour = 0; hour < 24; hour += 1) {
        final bucket = DateTime(start.year, start.month, start.day, hour);
        points.add(PeriodPoint(
            bucket: bucket,
            label: '${hour.toString().padLeft(2, '0')}:00',
            expense: 0,
            income: 0));
      }
    } else {
      var cursor = start;
      while (!cursor.isAfter(end)) {
        points.add(PeriodPoint(
            bucket: cursor,
            label:
                '${cursor.month.toString().padLeft(2, '0')}-${cursor.day.toString().padLeft(2, '0')}',
            expense: 0,
            income: 0));
        cursor = cursor.add(const Duration(days: 1));
      }
    }
    final expenses = List<double>.filled(points.length, 0);
    final incomes = List<double>.filled(points.length, 0);
    for (final transaction in state.transactions.where((item) =>
        item.deletedAt == null && item.type != TransactionType.transfer)) {
      final occurred = _occurredDate(transaction);
      if (occurred == null) continue;
      final date = DateTime(occurred.year, occurred.month, occurred.day);
      if (date.isBefore(start) || date.isAfter(end)) continue;
      final index = sameDay ? occurred.hour : date.difference(start).inDays;
      if (index < 0 || index >= points.length) continue;
      final amount = _cnyAmount(transaction);
      if (amount == null) continue;
      if (transaction.type == TransactionType.expense)
        expenses[index] += amount;
      if (transaction.type == TransactionType.income) incomes[index] += amount;
    }
    return [
      for (var index = 0; index < points.length; index += 1)
        PeriodPoint(
            bucket: points[index].bucket,
            label: points[index].label,
            expense: _round(expenses[index]),
            income: _round(incomes[index]))
    ];
  }

  static Map<String, double> expenseByCategory(
      FinanceState state, DateTimeRange range) {
    final start =
        DateTime(range.start.year, range.start.month, range.start.day);
    final end = DateTime(range.end.year, range.end.month, range.end.day);
    final totals = <String, double>{};
    for (final transaction in state.transactions.where((item) =>
        item.deletedAt == null && item.type == TransactionType.expense)) {
      final occurred = _occurredDate(transaction);
      final amount = _cnyAmount(transaction);
      if (occurred == null || amount == null) continue;
      final date = DateTime(occurred.year, occurred.month, occurred.day);
      if (date.isBefore(start) || date.isAfter(end)) continue;
      final key = transaction.categoryId ?? 'uncategorized';
      totals[key] = (totals[key] ?? 0) + amount;
    }
    return totals.map((key, value) => MapEntry(key, _round(value)));
  }

  static Map<String, double> expenseByAccount(
      FinanceState state, DateTimeRange range) {
    final start =
        DateTime(range.start.year, range.start.month, range.start.day);
    final end = DateTime(range.end.year, range.end.month, range.end.day);
    final totals = <String, double>{};
    for (final transaction in state.transactions.where((item) =>
        item.deletedAt == null && item.type == TransactionType.expense)) {
      final occurred = _occurredDate(transaction);
      final amount = _cnyAmount(transaction);
      if (occurred == null || amount == null) continue;
      final date = DateTime(occurred.year, occurred.month, occurred.day);
      if (date.isBefore(start) || date.isAfter(end)) continue;
      final key = transaction.accountId ?? 'unknown';
      totals[key] = (totals[key] ?? 0) + amount;
    }
    return totals.map((key, value) => MapEntry(key, _round(value)));
  }

  static FinanceMetrics deriveMetrics(FinanceState state, String monthKey) {
    final visibleTransactions =
        state.transactions.where((item) => item.deletedAt == null).toList();
    final monthTransactions = visibleTransactions
        .where((item) => item.date.startsWith(monthKey))
        .toList();
    final pendingConversionCount = monthTransactions
        .where((item) => _cnyAmount(item) == null && item.currency != 'CNY')
        .length;
    final income = _round(monthTransactions
        .where((item) => item.type == TransactionType.income)
        .fold<double>(0, (sum, item) => sum + (_cnyAmount(item) ?? 0)));
    final expense = _round(monthTransactions
        .where((item) => item.type == TransactionType.expense)
        .fold<double>(0, (sum, item) => sum + (_cnyAmount(item) ?? 0)));
    final savings = _round(income - expense);
    final savingsRate = income == 0 ? 0.0 : _round(savings / income, 3);
    final accountBalances = state.accounts
        .where((item) => item.deletedAt == null)
        .map((account) => AccountBalance(
            account: account,
            balance: _accountBalance(account, visibleTransactions)))
        .toList();
    final assetTotal = _round(accountBalances
        .where((item) => item.account.type == AccountType.asset)
        .fold<double>(0, (sum, item) => sum + item.balance));
    final liabilityTotal = _round(accountBalances
        .where((item) => item.account.type == AccountType.liability)
        .fold<double>(0, (sum, item) => sum + item.balance));
    final netWorth = _round(assetTotal - liabilityTotal);
    final budgetProgress = state.budgets
        .where((item) =>
            item.deletedAt == null && item.active && item.month == monthKey)
        .map((budget) {
      final spent = _round(monthTransactions
          .where((item) =>
              item.type == TransactionType.expense &&
              item.categoryId == budget.categoryId)
          .fold<double>(0, (sum, item) => sum + (_cnyAmount(item) ?? 0)));
      final ratio = budget.limit <= 0 ? 0 : spent / budget.limit;
      final status = ratio >= 1
          ? BudgetStatus.over
          : ratio >= .8
              ? BudgetStatus.warning
              : BudgetStatus.healthy;
      return BudgetProgress(budget: budget, spent: spent, status: status);
    }).toList();
    final goal = state.goals.isEmpty ? null : state.goals.first;
    final liquidAssets = accountBalances.where((item) {
      if (item.account.type != AccountType.asset || !item.account.isLiquid)
        return false;
      return goal == null ||
          goal.liquidAccountIds.isEmpty ||
          goal.liquidAccountIds.contains(item.account.id);
    }).toList();
    final selectedGoalIds = goal?.liquidAccountIds ?? const <String>[];
    final invalidGoalSelection = selectedGoalIds.any((id) => state.accounts.any(
        (account) =>
            account.id == id && account.type == AccountType.liability));
    final emergencyFund =
        _round(liquidAssets.fold<double>(0, (sum, item) => sum + item.balance));
    final goalProgress = goal == null || goal.target <= 0
        ? 0.0
        : (emergencyFund / goal.target).clamp(0, 1).toDouble();
    final remainingMonths =
        goal != null && savings > 0 && emergencyFund < goal.target
            ? ((goal.target - emergencyFund) / savings).ceil()
            : 0;

    return FinanceMetrics(
      monthKey: monthKey,
      income: income,
      expense: expense,
      savings: savings,
      savingsRate: savingsRate,
      accountBalances: accountBalances,
      assetTotal: assetTotal,
      liabilityTotal: liabilityTotal,
      netWorth: netWorth,
      budgetProgress: budgetProgress,
      emergencyFund: emergencyFund,
      goalProgress: goalProgress,
      remainingMonths: remainingMonths,
      emergencyFundError: invalidGoalSelection ? '应急金账户必须是资产账户' : null,
      pendingConversionCount: pendingConversionCount,
    );
  }

  static AgentDraft parseNaturalLanguage(String text,
      {required DateTime now, String? defaultAccountId}) {
    final amountMatch = RegExp(r'(?:¥|￥)?\s*(\d+(?:\.\d+)?)\s*(?:元|块|块钱)?')
        .firstMatch(text.replaceAll(',', ''));
    final amount = double.tryParse(amountMatch?.group(1) ?? '') ?? 0;
    final type = RegExp(r'工资|薪资|奖金|报销|到账|收入|收到').hasMatch(text)
        ? TransactionType.income
        : TransactionType.expense;
    final categoryId = _categoryFromText(text);
    final accountId = _accountFromText(text) ?? defaultAccountId;
    final date = now.subtract(text.contains('前天')
        ? const Duration(days: 2)
        : text.contains('昨天')
            ? const Duration(days: 1)
            : Duration.zero);
    final missingFacts = <String>[];
    if (accountId == null) missingFacts.add('请选择支付账户');
    final confidence = amount <= 0
        ? .35
        : categoryId == null || accountId == null
            ? .72
            : .98;
    return AgentDraft(
      amount: amount,
      type: type,
      categoryId: categoryId,
      accountId: accountId,
      date: _dateKey(date),
      note: text,
      confidence: confidence,
      missingFacts: missingFacts,
    );
  }

  static AgentDraft completeNaturalLanguageDraft(String text,
      {required DateTime now, required FinanceState state}) {
    final base = parseNaturalLanguage(text, now: now);
    final categoryId = _resolveCategory(text, base, state);
    final accountId = _resolveAccount(text, categoryId, state);
    final missingFacts = <String>[];
    if (base.amount <= 0) missingFacts.add('请输入金额');
    if (categoryId == null) missingFacts.add('请选择分类');
    if (accountId == null) missingFacts.add('请选择支付账户');
    final complete = base.amount > 0 && categoryId != null && accountId != null;
    return base.copyWith(
      categoryId: categoryId,
      accountId: accountId,
      confidence: complete ? .98 : .55,
      missingFacts: missingFacts,
    );
  }

  static bool canPostDraft(AgentDraft draft) {
    return draft.amount > 0 &&
        draft.categoryId != null &&
        draft.accountId != null &&
        draft.missingFacts.isEmpty &&
        draft.confidence >= confirmationThreshold;
  }

  static String quickMemoryKey(String text) {
    var key = text.toLowerCase();
    key = key.replaceAll(RegExp(r'\d+(?:\.\d+)?'), '');
    key = key.replaceAll(RegExp(
        r'今天|明天|昨天|前天|花了|用了|买了|支出|收入|收到|支付|付款|共|元|块钱?|人民币|cny|usd|美元|微信|支付宝|现金|银行卡|信用卡'), '');
    key = key.replaceAll(RegExp(r'[\s,，。！？!?、:：¥￥]'), '');
    return key.length >= 2 ? key : text.trim();
  }

  static String? _resolveCategory(
      String text, AgentDraft base, FinanceState state) {
    final active = state.categories.where((item) => item.active).toList();
    for (final category in active) {
      if (category.type == base.type && text.contains(category.name))
        return category.id;
    }
    if (base.categoryId != null &&
        active.any((item) => item.id == base.categoryId)) return base.categoryId;
    for (final memory in state.quickMemories.reversed) {
      if (memory.categoryId == null || !text.contains(memory.key)) continue;
      final category = active.where((item) => item.id == memory.categoryId);
      if (category.isNotEmpty && category.first.type == base.type)
        return memory.categoryId;
    }
    return null;
  }

  static String? _resolveAccount(
      String text, String? categoryId, FinanceState state) {
    final active = state.accounts
        .where((item) => item.deletedAt == null)
        .toList(growable: false);
    for (final account in active) {
      if (account.name.trim().isNotEmpty && text.contains(account.name))
        return account.id;
    }
    final aliasKinds = <String, AccountKind>{
      '微信': AccountKind.wechat,
      '支付宝': AccountKind.alipay,
      '现金': AccountKind.cash,
      '银行卡': AccountKind.bankCard,
      '银行': AccountKind.bankCard,
      '信用卡': AccountKind.creditCard,
    };
    for (final entry in aliasKinds.entries) {
      if (!text.contains(entry.key)) continue;
      final match = active.where((item) => item.accountKind == entry.value);
      if (match.isNotEmpty) return match.first.id;
    }
    for (final memory in state.quickMemories.reversed) {
      if (!text.contains(memory.key) || memory.accountId == null) continue;
      if (active.any((item) => item.id == memory.accountId))
        return memory.accountId;
    }
    if (categoryId != null) {
      final history = state.transactions
          .where((item) =>
              item.deletedAt == null &&
              item.categoryId == categoryId &&
              item.accountId != null &&
              active.any((account) => account.id == item.accountId))
          .toList();
      if (history.isNotEmpty) return history.last.accountId;
    }
    final defaultId = state.defaultAccountId;
    if (defaultId != null && active.any((item) => item.id == defaultId))
      return defaultId;
    return null;
  }

  static double _accountBalance(
      Account account, List<FinanceTransaction> transactions) {
    var balance = account.currency == 'CNY'
        ? account.openingBalance
        : (account.openingCnyAmount ?? 0);
    for (final transaction in transactions) {
      final amount = _cnyAmount(transaction);
      if (amount == null) continue;
      if (transaction.type == TransactionType.transfer) {
        if (transaction.fromAccountId == account.id) balance -= amount;
        if (transaction.toAccountId == account.id) balance += amount;
      } else if (transaction.accountId == account.id) {
        if (account.type == AccountType.liability) {
          balance +=
              transaction.type == TransactionType.expense ? amount : -amount;
        } else {
          balance +=
              transaction.type == TransactionType.income ? amount : -amount;
        }
      }
    }
    return _round(balance);
  }

  static double? _cnyAmount(FinanceTransaction transaction) {
    if (transaction.currency == 'CNY')
      return transaction.cnyAmount ?? transaction.amount;
    return transaction.cnyAmount;
  }

  static DateTime? _occurredDate(FinanceTransaction transaction) {
    final raw = transaction.occurredAt ?? transaction.date;
    if (raw.length >= 19 && raw[10] == 'T')
      return DateTime.tryParse(raw.substring(0, 19));
    return DateTime.tryParse(raw);
  }

  static String? _categoryFromText(String text) {
    const rules = <String, List<String>>{
      'food': ['外卖', '吃', '餐', '饭', '咖啡', '星巴克', '奶茶', '火锅', '日料', '美团'],
      'transport': ['打车', '滴滴', '地铁', '公交', '交通', '加油', '出行'],
      'shopping': ['购物', '淘宝', '京东', '超市', '盒马', '买', '日用品'],
      'home': ['房租', '房贷', '水电', '物业', '燃气'],
      'entertainment': ['电影', '游戏', '娱乐', '演唱会'],
      'health': ['医院', '看病', '药', '健身'],
      'salary': ['工资', '薪资', '奖金', '报销', '到账', '收入'],
    };
    for (final entry in rules.entries) {
      if (entry.value.any((word) => text.contains(word))) return entry.key;
    }
    return null;
  }

  static String? _accountFromText(String text) {
    if (text.contains('支付宝')) return 'alipay';
    if (text.contains('微信')) return 'wechat';
    if (text.contains('银行卡') || text.contains('银行')) return 'bank';
    if (text.contains('现金')) return 'cash';
    if (text.contains('信用卡')) return 'credit';
    return null;
  }

  static String _dateKey(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  static double _round(double value, [int digits = 2]) {
    final factor = 10.0.pow(digits);
    return (value * factor).round() / factor;
  }
}

extension on double {
  double pow(int exponent) {
    var result = 1.0;
    for (var index = 0; index < exponent; index += 1) {
      result *= this;
    }
    return result;
  }
}
