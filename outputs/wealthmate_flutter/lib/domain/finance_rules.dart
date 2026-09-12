import 'package:flutter/material.dart';

import '../features/insights/domain/insight_rules.dart';
import 'models.dart';

export '../features/insights/domain/insight_rules.dart' show PeriodPoint;

class FinanceRules {
  static const double confirmationThreshold = .85;

  static List<PeriodPoint> periodExpenseSeries(
          FinanceState state, DateTimeRange range) =>
      InsightRules.periodExpenseSeries(state, range);

  static Map<String, double> expenseByCategory(
          FinanceState state, DateTimeRange range) =>
      InsightRules.expenseByCategory(state, range);

  static Map<String, double> expenseByAccount(
          FinanceState state, DateTimeRange range) =>
      InsightRules.expenseByAccount(state, range);

  static FinanceMetrics deriveMetrics(FinanceState state, String monthKey) =>
      InsightRules.deriveMetrics(state, monthKey);

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
    key = key.replaceAll(
        RegExp(
            r'今天|明天|昨天|前天|花了|用了|买了|支出|收入|收到|支付|付款|共|元|块钱?|人民币|cny|usd|美元|微信|支付宝|现金|银行卡|信用卡'),
        '');
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
        active.any((item) => item.id == base.categoryId))
      return base.categoryId;
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

}
