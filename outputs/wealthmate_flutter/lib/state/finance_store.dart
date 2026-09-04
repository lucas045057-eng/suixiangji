import 'package:flutter/foundation.dart' show ChangeNotifier;
import 'dart:convert';

import '../data/finance_repository.dart';
import '../data/api_client.dart';
import '../data/sync_queue.dart';
import '../domain/demo_state.dart';
import '../domain/finance_rules.dart';
import '../domain/models.dart';

class FinanceStore extends ChangeNotifier {
  FinanceStore({required this.repository, FinanceState? initialState})
      : _state = initialState ?? DemoData.create();

  final FinanceRepository repository;
  FinanceState _state;
  AgentDraft? _draft;
  String? _draftSourceText;
  UserProfile? _profile;
  String? _message;
  List<BudgetAlert> _budgetAlerts = const [];
  FinanceState? _metricsState;
  String? _metricsMonth;
  FinanceMetrics? _metricsCache;

  FinanceState get state => _state;
  AgentDraft? get draft => _draft;
  UserProfile? get profile => _profile;
  String? get message => _message;
  List<BudgetAlert> get budgetAlerts => List.unmodifiable(_budgetAlerts);
  bool get isDemoMode => repository.api == null;
  List<Category> get activeCategories =>
      _state.categories.where((item) => item.active).toList(growable: false);
  FinanceMetrics get metrics {
    final month = _state.currentMonth.isEmpty
        ? _monthKey(DateTime.now())
        : _state.currentMonth;
    if (identical(_metricsState, _state) &&
        _metricsMonth == month &&
        _metricsCache != null) return _metricsCache!;
    _metricsState = _state;
    _metricsMonth = month;
    _metricsCache = FinanceRules.deriveMetrics(_state, month);
    return _metricsCache!;
  }

  Future<void> load() async {
    final loaded = await repository.load();
    if (loaded != null) _state = loaded;
    notifyListeners();
  }

  Future<void> loadProfile() async {
    if (repository.api == null || repository.api!.token == null) return;
    try {
      final profile = await repository.api!.fetchProfile();
      _profile = profile;
      final memories = <String, QuickMemory>{
        for (final memory in _state.quickMemories) memory.key: memory,
        for (final memory in profile.quickMemories) memory.key: memory,
      };
      _state = _state.copyWith(quickMemories: memories.values.toList());
      await repository.save(_state);
      _message = null;
    } on ApiFailure catch (failure) {
      _message = failure.message;
    }
    notifyListeners();
  }

  Future<bool> updateProfile({String? displayName, String? username}) async {
    if (repository.api == null) {
      _message = '当前未配置同步服务';
      notifyListeners();
      return false;
    }
    try {
      _profile = await repository.api!
          .updateProfile(displayName: displayName, username: username);
      _message = '用户资料已更新';
      notifyListeners();
      return true;
    } on ApiFailure catch (failure) {
      _message = failure.message;
      notifyListeners();
      return false;
    }
  }

  Future<bool> changePassword(
      String currentPassword, String newPassword) async {
    if (repository.api == null) {
      _message = '当前未配置同步服务';
      notifyListeners();
      return false;
    }
    try {
      _profile =
          await repository.api!.changePassword(currentPassword, newPassword);
      _message = '密码已更新，其他设备需要重新登录';
      notifyListeners();
      return true;
    } on ApiFailure catch (failure) {
      _message = failure.message;
      notifyListeners();
      return false;
    }
  }

  Future<void> addTransaction(FinanceTransaction transaction) async {
    _state = await repository.applyLocal(_state, transaction);
    await checkBudgetAlerts();
    _message = '已保存到本地';
    notifyListeners();
  }

  Future<void> addAccount(
      {required String name,
      required AccountType type,
      String currency = 'CNY',
      double openingBalance = 0,
      AccountKind accountKind = AccountKind.other}) async {
    final normalizedName = name.trim().toLowerCase();
    if (normalizedName.isEmpty ||
        _state.accounts.any((item) =>
            item.deletedAt == null &&
            item.name.trim().toLowerCase() == normalizedName)) {
      _message = '账户名称不能重复';
      notifyListeners();
      return;
    }
    final id = 'account-${DateTime.now().microsecondsSinceEpoch}';
    _state = await repository.applyLocalAccount(
        _state,
        Account(
            id: id,
            name: name,
            type: type,
            accountKind: accountKind,
            currency: currency.toUpperCase(),
            openingBalance: openingBalance));
    _message = '账户已保存到本地，联网后会同步';
    notifyListeners();
  }

  Future<void> updateAccount(Account account) async {
    if (!_state.accounts.any((item) => item.id == account.id)) return;
    final normalizedName = account.name.trim().toLowerCase();
    if (normalizedName.isEmpty ||
        _state.accounts.any((item) =>
            item.id != account.id &&
            item.deletedAt == null &&
            item.name.trim().toLowerCase() == normalizedName)) {
      _message = '账户名称不能重复';
      notifyListeners();
      return;
    }
    _state = await repository.applyLocalAccount(_state, account);
    if (account.isDefaultPayment && account.type == AccountType.asset) {
      _state = _state.copyWith(defaultAccountId: account.id);
      await repository.save(_state);
    }
    _message = '账户配置已保存';
    notifyListeners();
  }

  Future<void> addCategory(
      {required String name, required TransactionType type}) async {
    final id = 'category-${DateTime.now().microsecondsSinceEpoch}';
    _state = await repository.applyLocalCategory(
        _state, Category(id: id, name: name, type: type));
    _message = '分类已保存';
    notifyListeners();
  }

  Future<void> updateCategory(String categoryId,
      {required String name, required bool active}) async {
    final matches = _state.categories
        .where((item) => item.id == categoryId)
        .toList(growable: false);
    final existing = matches.isEmpty ? null : matches.first;
    if (existing == null) return;
    _state = await repository.applyLocalCategory(
        _state,
        Category(
            id: existing.id, name: name, active: active, type: existing.type));
    _message = active ? '分类已更新' : '分类已归档';
    notifyListeners();
  }

  Future<void> archiveCategory(String categoryId) async {
    final matches = _state.categories
        .where((item) => item.id == categoryId)
        .toList(growable: false);
    final existing = matches.isEmpty ? null : matches.first;
    if (existing == null) return;
    await updateCategory(categoryId, name: existing.name, active: false);
  }

  Future<void> updateTransaction(FinanceTransaction transaction) async {
    if (!_state.transactions.any((item) => item.id == transaction.id)) return;
    _state = _state.copyWith(
        transactions: _state.transactions
            .map((item) => item.id == transaction.id ? transaction : item)
            .toList());
    repository.queue.enqueue(SyncOperation(
      clientOpId: transaction.clientOpId,
      entity: 'transactions',
      entityId: transaction.id,
      type: SyncOperationType.upsert,
      payload: transaction.toJson(),
      createdAt: DateTime.now().toIso8601String(),
    ));
    await repository.save(_state);
    await repository.persistQueue();
    _message = '账目已更新';
    notifyListeners();
  }

  Future<void> createDraft(String text, {DateTime? now}) async {
    final localDraft = FinanceRules.completeNaturalLanguageDraft(text,
        now: now ?? DateTime.now(), state: _state);
    _draft = localDraft;
    _draftSourceText = text;
    _message = null;
    notifyListeners();
    if (repository.api != null) {
      try {
        final remoteDraft = await repository.api!.postAgentDraft(text);
        _draft = localDraft.copyWith(
          amount: remoteDraft.amount > 0 ? remoteDraft.amount : localDraft.amount,
          type: remoteDraft.type,
          date: remoteDraft.date.isEmpty ? localDraft.date : remoteDraft.date,
          note: remoteDraft.note.isEmpty ? localDraft.note : remoteDraft.note,
          currency: remoteDraft.currency,
        );
        _message = '已从同步服务生成待确认草稿';
        notifyListeners();
      } on ApiFailure {
        _message = '同步服务暂不可用，已使用本地规则草稿';
        notifyListeners();
      }
    }
  }

  void updateDraft(AgentDraft draft) {
    final missingFacts = <String>[];
    if (draft.amount <= 0) missingFacts.add('请输入金额');
    if (draft.categoryId == null) missingFacts.add('请选择分类');
    if (draft.accountId == null) missingFacts.add('请选择支付账户');
    _draft = draft.copyWith(
      confidence: missingFacts.isEmpty ? .98 : .55,
      missingFacts: missingFacts,
    );
    _message = null;
    notifyListeners();
  }

  Future<void> rememberDraftChoice(
      String sourceText, AgentDraft draft) async {
    final key = FinanceRules.quickMemoryKey(sourceText);
    if (key.isEmpty || draft.categoryId == null || draft.accountId == null)
      return;
    final memory = QuickMemory(
        key: key,
        categoryId: draft.categoryId,
        accountId: draft.accountId,
        updatedAt: DateTime.now().toIso8601String());
    _state = _state.copyWith(
        quickMemories: [
          ..._state.quickMemories.where((item) => item.key != key),
          memory
        ]);
    await repository.save(_state);
    if (repository.api != null) {
      try {
        _profile = await repository.api!
            .updateProfile(quickMemories: _state.quickMemories);
      } on ApiFailure {
        // The confirmed transaction remains safe locally and will sync later.
      }
    }
  }

  Future<bool> confirmDraft(AgentDraft draft) async {
    if (!FinanceRules.canPostDraft(draft)) {
      _message = draft.missingFacts.isEmpty
          ? '这笔记录仍需确认关键字段'
          : draft.missingFacts.join('、');
      notifyListeners();
      return false;
    }
    final id = 'tx-${DateTime.now().microsecondsSinceEpoch}';
    final sourceText = _draftSourceText;
    await addTransaction(FinanceTransaction(
      id: id,
      date: draft.date,
      type: draft.type,
      amount: draft.amount,
      currency: draft.currency,
      categoryId: draft.categoryId,
      accountId: draft.accountId,
      fromAccountId: draft.fromAccountId,
      toAccountId: draft.toAccountId,
      note: draft.note,
      clientOpId: id,
    ));
    if (sourceText != null) await rememberDraftChoice(sourceText, draft);
    _draft = null;
    _draftSourceText = null;
    if (repository.api != null) await sync();
    notifyListeners();
    return true;
  }

  Future<void> deleteTransaction(String transactionId) async {
    if (!_state.transactions.any((item) => item.id == transactionId)) return;
    _state = await repository.softDelete(_state, transactionId);
    _message = '账目已移入待同步删除队列';
    notifyListeners();
  }

  Future<void> upsertBudget(
      {String? id,
      required String month,
      required String categoryId,
      required double limit}) async {
    final budgetId = id ?? 'budget-${DateTime.now().microsecondsSinceEpoch}';
    final budget = Budget(
        id: budgetId, month: month, categoryId: categoryId, limit: limit);
    final budgets = [
      ..._state.budgets.where((item) => item.id != budgetId),
      budget
    ];
    _state = _state.copyWith(budgets: budgets);
    repository.queue.enqueue(SyncOperation(
      clientOpId: 'budget:$budgetId:${DateTime.now().microsecondsSinceEpoch}',
      entity: 'budgets',
      entityId: budgetId,
      type: SyncOperationType.upsert,
      payload: budget.toJson(),
      createdAt: DateTime.now().toIso8601String(),
    ));
    await repository.save(_state);
    await repository.persistQueue();
    _message = '预算已保存';
    notifyListeners();
  }

  Future<List<BudgetAlert>> checkBudgetAlerts() async {
    final raw =
        await repository.local.store.read('wealthmate-budget-alerts-v1');
    final decoded = raw == null || raw.isEmpty ? null : jsonDecode(raw);
    final seen =
        decoded is List ? decoded.whereType<String>().toSet() : <String>{};
    final alerts = <BudgetAlert>[];
    for (final progress in metrics.budgetProgress) {
      final ratio = progress.ratio;
      final level = ratio > 1
          ? BudgetAlertLevel.over
          : ratio >= 1
              ? BudgetAlertLevel.exhausted
              : ratio >= .8
                  ? BudgetAlertLevel.warning
                  : null;
      if (level == null) continue;
      final alert = BudgetAlert(
          budget: progress.budget, spent: progress.spent, level: level);
      if (seen.add(alert.key)) alerts.add(alert);
    }
    if (alerts.isNotEmpty)
      await repository.local.store
          .write('wealthmate-budget-alerts-v1', jsonEncode(seen.toList()));
    _budgetAlerts = alerts;
    return alerts;
  }

  Future<void> setDefaultAccount(String accountId) async {
    if (!_state.accounts
        .any((item) => item.id == accountId && item.type == AccountType.asset))
      return;
    _state = _state.copyWith(defaultAccountId: accountId);
    await repository.save(_state);
    _message = '默认支付账户已更新';
    notifyListeners();
  }

  Future<void> sync() async {
    _state = await repository.pushPending(_state);
    _state = await repository.pullChanges(_state);
    _message = _state.syncState.error ??
        (_state.syncState.lastSyncedAt == null ? '离线演示/待配置' : '已完成同步');
    notifyListeners();
  }

  Future<void> saveManualExchangeRate(
      {required String baseCurrency,
      required double rate,
      required String rateDate,
      required String source}) async {
    final base = baseCurrency.trim().toUpperCase();
    if (base.length < 3 ||
        base == 'CNY' ||
        rate <= 0 ||
        source.trim().isEmpty) {
      _message = '汇率需要填写有效币种、正数汇率和来源';
      notifyListeners();
      return;
    }
    final snapshot = ExchangeRateSnapshot(
        baseCurrency: base,
        rate: rate,
        rateDate: rateDate,
        source: source.trim(),
        updatedAt: DateTime.now().toIso8601String());
    _applyExchangeRate(snapshot);
    await repository.save(_state);
    if (repository.api != null) {
      try {
        await repository.api!.saveExchangeRate(snapshot.toJson());
        _message = '汇率已保存并同步';
      } on ApiFailure {
        _message = '汇率已保存在本机，联网后可再次同步';
      }
    } else {
      _message = '汇率已保存到本地';
    }
    notifyListeners();
  }

  Future<void> refreshExchangeRate(String baseCurrency) async {
    if (repository.api == null) {
      _message = '当前未配置同步服务，无法获取公开汇率';
      notifyListeners();
      return;
    }
    try {
      final json =
          await repository.api!.fetchExchangeRate(baseCurrency.toUpperCase());
      final snapshot = ExchangeRateSnapshot.fromJson(json);
      if (snapshot.rate <= 0)
        throw const ApiFailure(ApiFailureKind.validation, '公开汇率无效');
      _applyExchangeRate(snapshot);
      await repository.save(_state);
      _message = '已获取并保存 ${snapshot.baseCurrency}/CNY 汇率';
    } on ApiFailure {
      _message = '获取汇率失败，已保留上一次可靠汇率';
    } on Object {
      _message = '获取汇率失败，已保留上一次可靠汇率';
    }
    notifyListeners();
  }

  void _applyExchangeRate(ExchangeRateSnapshot snapshot) {
    final rates = [
      ..._state.exchangeRates.where((item) =>
          item.baseCurrency != snapshot.baseCurrency ||
          item.quoteCurrency != snapshot.quoteCurrency),
      snapshot
    ];
    final accounts = _state.accounts.map((account) {
      if (account.currency.toUpperCase() != snapshot.baseCurrency)
        return account;
      return account.copyWith(
          openingCnyAmount: account.openingBalance * snapshot.rate,
          exchangeRate: snapshot.rate,
          exchangeRateDate: snapshot.rateDate,
          exchangeRateSource: snapshot.source);
    }).toList();
    _state = _state.copyWith(exchangeRates: rates, accounts: accounts);
  }

  Future<void> restoreDemoData() async {
    _state = DemoData.create();
    _draft = null;
    _draftSourceText = null;
    _message = '演示数据已恢复';
    repository.queue.replace(const []);
    await repository.save(_state);
    await repository.persistQueue();
    notifyListeners();
  }

  void clearMessage() {
    _message = null;
    notifyListeners();
  }

  void clearDraft() {
    _draft = null;
    _draftSourceText = null;
    _message = null;
    notifyListeners();
  }

  String exportJson() => jsonEncode(_state.toJson());

  Future<void> generateMonthlyReport() async {
    if (repository.api != null) {
      try {
        final result = await repository.api!
            .fetchMonthlyReport(metrics.monthKey, force: true);
        final remoteReport = Report(
          id: '${result['id'] ?? 'report-${metrics.monthKey}'}',
          month: result['month'] as String? ?? metrics.monthKey,
          title: ((result['ai_status'] as String?) == 'success')
              ? 'AI 月度财务分析'
              : '本月程序统计（AI 未配置）',
          summary: result['summary'] as String? ?? '当前数据不足，无法判断。',
          generatedAt: result['generated_at'] as String? ??
              DateTime.now().toIso8601String(),
        );
        _state = _state.copyWith(reports: [
          ..._state.reports.where((item) => item.month != metrics.monthKey),
          remoteReport
        ]);
        await repository.save(_state);
        _message = '月度报告已从服务端更新';
        notifyListeners();
        return;
      } on ApiFailure {
        _message = '报告服务暂不可用，保留本地程序统计';
      }
    }
    final current = metrics;
    final report = Report(
      id: 'report-${current.monthKey}',
      month: current.monthKey,
      title: current.savings >= 0 ? '本月结余正在形成安全垫' : '本月支出超过收入，需要留意节奏',
      summary:
          '本月收入 ${current.income.toStringAsFixed(0)} 元，支出 ${current.expense.toStringAsFixed(0)} 元，储蓄率 ${(current.savingsRate * 100).round()}%。',
      generatedAt: DateTime.now().toIso8601String(),
    );
    _state = _state.copyWith(reports: [
      ..._state.reports.where((item) => item.month != current.monthKey),
      report
    ]);
    await repository.save(_state);
    _message = '月度报告已更新';
    notifyListeners();
  }

  static String _monthKey(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}';
}
