import 'package:flutter/material.dart';

import '../features/insights/domain/insight_rules.dart';
import 'models.dart';

export '../features/insights/domain/insight_rules.dart' show PeriodPoint;

class FinanceRules {
  static const double confirmationThreshold = .85;
  static const Map<String, int> _chineseDigits = {
    '零': 0,
    '〇': 0,
    '一': 1,
    '二': 2,
    '两': 2,
    '三': 3,
    '四': 4,
    '五': 5,
    '六': 6,
    '七': 7,
    '八': 8,
    '九': 9,
  };
  static const Map<String, int> _chineseSmallUnits = {
    '十': 10,
    '百': 100,
    '千': 1000,
  };
  static const String _numberToken =
      r'(?:\d+(?:\.\d{1,2})?|[零〇一二两三四五六七八九十百千万]+)';

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
    final amount = _amountFromText(text) ?? 0;
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
    if (amount <= 0) missingFacts.add('请输入金额');
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

  static double? _amountFromText(String text) {
    final normalized = _normalizeAmountText(text);
    for (final symbolMatch
        in RegExp(r'[¥￥](\d+(?:\.\d{1,2})?)').allMatches(normalized)) {
      if (!_hasAmountBoundary(
          normalized, symbolMatch.start + 1, symbolMatch.end)) continue;
      final amount = double.tryParse(symbolMatch.group(1)!);
      return amount != null && amount > 0 ? amount : null;
    }
    RegExpMatch? match;
    for (final candidate in RegExp('($_numberToken)(块钱|元|块|人民币|CNY|USD|美元|刀)',
            caseSensitive: false)
        .allMatches(normalized)) {
      if (_hasAmountBoundary(normalized, candidate.start, candidate.end)) {
        match = candidate;
        break;
      }
    }
    if (match == null) return null;
    final rawYuan = match.group(1)!;
    final yuan = _parseWholeYuan(rawYuan);
    if (yuan == null || yuan < 0) return null;
    if (rawYuan.contains('.')) {
      final amount = _roundCurrencyAmount(yuan);
      return amount > 0 ? amount : null;
    }
    final suffix = normalized.substring(match.end);
    if (_hasInvalidFractionSuffix(suffix)) return null;
    final fraction = _fractionFromSuffix(suffix);
    final amount = _roundCurrencyAmount(yuan + (fraction ?? 0));
    return amount > 0 ? amount : null;
  }

  static bool _hasAmountBoundary(String text, int start, int end) {
    if (start > 0 && RegExp(r'[\d.]').hasMatch(text[start - 1])) return false;
    if (end < text.length && RegExp(r'[.]').hasMatch(text[end])) return false;
    return true;
  }

  static String _normalizeAmountText(String text) {
    const fullWidth = '０１２３４５６７８９．，';
    const halfWidth = '0123456789.,';
    var normalized = text;
    for (var i = 0; i < fullWidth.length; i += 1) {
      normalized = normalized.replaceAll(fullWidth[i], halfWidth[i]);
    }
    return normalized.replaceAll(RegExp(r'\s+|,'), '');
  }

  static double? _parseWholeYuan(String value) {
    if (RegExp(r'^\d+(?:\.\d{1,2})?$').hasMatch(value)) {
      return double.tryParse(value);
    }
    final parsed = _parseChineseNumber(value);
    return parsed?.toDouble();
  }

  static int? _parseChineseNumber(String value) {
    if (value.isEmpty) return null;
    var total = 0;
    var section = 0;
    var number = 0;
    int? lastSmallUnit;
    var previousDigit = false;
    int? previousDigitValue;
    var afterWan = false;
    var wanTailHasExplicitZero = false;
    for (final char in value.characters) {
      final digit = _chineseDigits[char];
      if (digit != null) {
        if (previousDigit && previousDigitValue != 0) return null;
        number = digit;
        if (afterWan && digit == 0) wanTailHasExplicitZero = true;
        previousDigit = true;
        previousDigitValue = digit;
        continue;
      }
      final smallUnit = _chineseSmallUnits[char];
      if (smallUnit != null) {
        if (lastSmallUnit != null && smallUnit >= lastSmallUnit) return null;
        section += (number == 0 ? 1 : number) * smallUnit;
        number = 0;
        lastSmallUnit = smallUnit;
        previousDigit = false;
        previousDigitValue = null;
        continue;
      }
      if (char == '万') {
        if (total != 0 || section + number <= 0) return null;
        total += (section + number) * 10000;
        section = 0;
        number = 0;
        lastSmallUnit = null;
        previousDigit = false;
        previousDigitValue = null;
        afterWan = true;
        wanTailHasExplicitZero = false;
        continue;
      }
      return null;
    }
    var tail = section + number;
    if (afterWan &&
        tail > 0 &&
        section == 0 &&
        lastSmallUnit == null &&
        !wanTailHasExplicitZero) {
      tail *= 1000;
    }
    return total + tail;
  }

  static double? _fractionFromSuffix(String suffix) {
    if (suffix.isEmpty) return 0;
    final jiaoMatch = RegExp('^($_numberToken)(?:角|毛)(.*)').firstMatch(suffix);
    if (jiaoMatch != null) {
      final jiao = _singleDigit(jiaoMatch.group(1)!);
      if (jiao == null) return null;
      final rest = jiaoMatch.group(2)!;
      int fen;
      if (rest.isEmpty) {
        fen = 0;
      } else {
        final fenMatch = RegExp('^($_numberToken)分?').firstMatch(rest);
        if (fenMatch == null) return null;
        final parsedFen = _singleDigit(fenMatch.group(1)!);
        if (parsedFen == null) return null;
        fen = parsedFen;
      }
      return jiao / 10 + fen / 100;
    }
    final fenMatch = RegExp('^($_numberToken)分').firstMatch(suffix);
    if (fenMatch != null) {
      final fen = _singleDigit(fenMatch.group(1)!);
      return fen == null ? null : fen / 100;
    }
    final digitTail = RegExp(r'^\d{1,2}').firstMatch(suffix);
    if (digitTail != null) {
      final raw = digitTail.group(0)!;
      return int.parse(raw) / (raw.length == 1 ? 10 : 100);
    }
    final chineseTail = RegExp(r'^[零〇一二两三四五六七八九]{1,2}').firstMatch(suffix);
    if (chineseTail != null) {
      final raw = chineseTail.group(0)!;
      final cents = raw.characters.map((char) => _chineseDigits[char]!).join();
      return int.parse(cents) / (cents.length == 1 ? 10 : 100);
    }
    return null;
  }

  static bool _hasInvalidFractionSuffix(String suffix) {
    if (RegExp('^($_numberToken)(?:厘|毫)').hasMatch(suffix)) return true;
    final jiaoMatch = RegExp('^($_numberToken)(?:角|毛)(.*)').firstMatch(suffix);
    if (jiaoMatch == null) return false;
    final secondUnit =
        RegExp('^($_numberToken)(分|厘|毫|角|毛)').firstMatch(jiaoMatch.group(2)!);
    return secondUnit != null && secondUnit.group(2) != '分';
  }

  static int? _singleDigit(String value) {
    if (RegExp(r'^\d$').hasMatch(value)) return int.parse(value);
    if (value.characters.length == 1) return _chineseDigits[value];
    return null;
  }

  static double _roundCurrencyAmount(double value) =>
      (value * 100).roundToDouble() / 100;
}
