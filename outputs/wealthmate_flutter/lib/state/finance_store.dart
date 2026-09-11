import 'package:flutter/foundation.dart' show ChangeNotifier;
import 'dart:convert';

import '../data/finance_repository.dart';
import '../data/api_client.dart';
import '../data/local_repository.dart';
import '../domain/demo_state.dart';
import '../domain/finance_rules.dart';
import '../domain/models.dart';
import '../features/auth/data/auth_remote_data_source.dart';
import '../features/auth/data/auth_repository.dart';
import '../features/auth/state/auth_store.dart';
import '../features/ledger/data/ledger_remote_data_source.dart';
import '../features/ledger/data/ledger_repository.dart';
import '../features/ledger/state/ledger_store.dart';

class FinanceStore extends ChangeNotifier {
  FinanceStore({
    required this.repository,
    FinanceState? initialState,
    AuthStore? authStore,
  })  : _state = initialState ??
            (repository.api == null ? DemoData.create() : const FinanceState()),
        _authStore = authStore ??
            (repository.api == null
                ? null
                : AuthStore(
                    repository: AuthRepository(
                      remote: AuthRemoteDataSource(api: repository.api!),
                    ),
                  )),
        ledger = LedgerStore(
          repository: LedgerRepository(
            session: repository.session,
            remote: repository.api == null
                ? null
                : LedgerRemoteDataSource(api: repository.api!),
          ),
          initialState: initialState ??
              (repository.api == null ? DemoData.create() : const FinanceState()),
        ) {
    ledger.onStateChanged = (next) {
      _state = next;
      _metricsState = null;
      _metricsMonth = null;
      _metricsCache = null;
      notifyListeners();
    };
  }

  final FinanceRepository repository;
  final LedgerStore ledger;
  FinanceState _state;
  AgentDraft? _draft;
  String? _draftSourceText;
  final AuthStore? _authStore;
  String? _message;
  List<BudgetAlert> _budgetAlerts = const [];
  final Set<String> _pendingDeletionCleanupUserIds = <String>{};
  bool _pendingDeletionCleanupStateUnknown = false;
  int _sessionGeneration = 0;
  FinanceState? _metricsState;
  String? _metricsMonth;
  FinanceMetrics? _metricsCache;

  FinanceState get state => _state;
  AgentDraft? get draft => _draft;
  AuthStore? get authStore => _authStore;
  UserProfile? get profile => _authStore?.profile;
  String? get message => _message;
  String? get pendingDeletionCleanupUserId =>
      _pendingDeletionCleanupUserIds.isEmpty
          ? null
          : _pendingDeletionCleanupUserIds.first;
  String? get pendingDeletionCleanupMessage =>
      _pendingDeletionCleanupStateUnknown
          ? '本机清理状态暂时无法读取，请稍后重试'
          : _pendingDeletionCleanupUserIds.isEmpty
              ? null
              : '账号已删除，但本机数据清理仍未完成，请重试本机清理';
  (int, int) get _session =>
      (_sessionGeneration, repository.sessionIdentity.$2);
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
    final started = _session;
    if (repository.api != null && repository.api!.token == null) {
      await repository.api!.restoreToken();
      if (_session != started) return;
    }
    late final List<String> pending;
    try {
      pending = await repository.local.loadPendingAccountCleanupUserIds();
    } on Object {
      if (_session != started) return;
      _pendingDeletionCleanupStateUnknown = true;
      await _failClosedForUnknownCleanupState();
      notifyListeners();
      return;
    }
    if (_session != started) return;
    _pendingDeletionCleanupStateUnknown = false;
    _pendingDeletionCleanupUserIds
      ..clear()
      ..addAll(pending);
    if (_pendingDeletionCleanupUserIds.isNotEmpty) {
      final verifiedUserId = repository.api?.lastVerifiedUserId?.trim();
      final currentIsDifferentVerifiedUser = repository.api?.token != null &&
          verifiedUserId != null &&
          verifiedUserId.isNotEmpty &&
          !_pendingDeletionCleanupUserIds.contains(verifiedUserId);
      if (!currentIsDifferentVerifiedUser) {
        await repository.api?.logout();
        repository.queue.replace(const []);
        repository.unbindLocalOwner();
        _state = const FinanceState();
        _draft = null;
        _draftSourceText = null;
        _budgetAlerts = const [];
        _metricsState = null;
        _metricsMonth = null;
        _metricsCache = null;
        ledger.adoptState(_state);
        _authStore?.clearSession();
        await _attemptPendingDeletionCleanup(notify: false);
        notifyListeners();
        return;
      }
      await _attemptPendingDeletionCleanup(notify: false);
      if (_session != started && repository.api?.token == null) return;
    }
    if (repository.api != null && !repository.isLocalOwnerBound) {
      await repository.restoreLocalOwnerForVerifiedSession();
      if (_session != started) return;
    }
    final loaded = await repository.load();
    if (_session != started) return;
    if (loaded != null) {
      _state = loaded;
      ledger.adoptState(_state);
    }
    notifyListeners();
  }

  Future<void> _failClosedForUnknownCleanupState() async {
    await repository.api?.logout();
    repository.queue.replace(const []);
    repository.unbindLocalOwner();
    _state = const FinanceState();
    ledger.adoptState(_state);
    _draft = null;
    _draftSourceText = null;
    _budgetAlerts = const [];
    _metricsState = null;
    _metricsMonth = null;
    _metricsCache = null;
    _authStore?.clearSession();
    _message = pendingDeletionCleanupMessage;
  }

  Future<bool> _attemptPendingDeletionCleanup({required bool notify}) async {
    if (_pendingDeletionCleanupUserIds.isEmpty) return true;
    final cleanupMessage = pendingDeletionCleanupMessage;
    var cleanedAll = true;
    for (final userId in List<String>.from(_pendingDeletionCleanupUserIds)) {
      final scopedLocal = repository.local.forUser(userId);
      try {
        await repository.session.purgePartition(scopedLocal);
        await scopedLocal.clearPendingAccountCleanup(userId);
        _pendingDeletionCleanupUserIds.remove(userId);
      } on Object {
        cleanedAll = false;
      }
    }
    if (cleanedAll && _message == cleanupMessage) _message = null;
    if (!cleanedAll) _message = pendingDeletionCleanupMessage;
    if (notify) notifyListeners();
    return cleanedAll;
  }

  Future<bool> retryPendingDeletionCleanup() async {
    if (_pendingDeletionCleanupStateUnknown) {
      late final List<String> pending;
      try {
        pending = await repository.local.loadPendingAccountCleanupUserIds();
      } on Object {
        _message = pendingDeletionCleanupMessage;
        notifyListeners();
        return false;
      }
      _pendingDeletionCleanupStateUnknown = false;
      _pendingDeletionCleanupUserIds
        ..clear()
        ..addAll(pending);
      if (pending.isEmpty) {
        _message = null;
        notifyListeners();
        return true;
      }
    }
    return _attemptPendingDeletionCleanup(notify: true);
  }

  Future<bool> loadProfile() async {
    final started = _session;
    final auth = _authStore;
    if (auth == null || !await auth.loadProfile()) {
      if (_session != started) return false;
      _message = auth?.message;
      notifyListeners();
      return false;
    }
    if (_session != started) return false;
    final profile = auth.profile;
    if (profile == null) return false;
    await loadAuthenticatedProfile(profile);
    return _session == started;
  }

  Future<void> loadAuthenticatedProfile(UserProfile profile) async {
    final started = _session;
    final loaded = await repository.loadForUser(profile.id);
    if (_session != started) return;
    _state = loaded ?? const FinanceState();
    final memories = <String, QuickMemory>{
      for (final memory in _state.quickMemories) memory.key: memory,
      for (final memory in profile.quickMemories) memory.key: memory,
    };
    _state = _state.copyWith(quickMemories: memories.values.toList());
    ledger.adoptState(_state);
    if (_session != started) return;
    await repository.save(_state);
    if (_session != started) return;
    _message = null;
    notifyListeners();
  }

  Future<bool> updateProfile({String? displayName, String? username}) async {
    final auth = _authStore;
    if (auth == null) {
      _message = '当前未配置同步服务';
      notifyListeners();
      return false;
    }
    final started = _session;
    final success =
        await auth.updateProfile(displayName: displayName, username: username);
    if (_session != started) return false;
    _message = success ? '用户资料已更新' : auth.message;
    notifyListeners();
    return success;
  }

  Future<bool> changePassword(
      String currentPassword, String newPassword) async {
    final auth = _authStore;
    if (auth == null) {
      _message = '当前未配置同步服务';
      notifyListeners();
      return false;
    }
    final started = _session;
    final success = await auth.changePassword(currentPassword, newPassword);
    if (_session != started) return false;
    _message = success ? '密码已更新，其他设备需要重新登录' : auth.message;
    notifyListeners();
    return success;
  }

  Future<bool> deleteAccount(String currentPassword) async {
    final started = _session;
    final api = repository.api;
    final auth = _authStore;
    final profile = auth?.profile;
    final local = repository.local;
    if (api == null ||
        auth == null ||
        profile == null ||
        local.userId != profile.id ||
        currentPassword.isEmpty) {
      _message = '请确认登录身份并输入当前密码';
      notifyListeners();
      return false;
    }
    final userId = profile.id.trim();
    final scopedLocal = local.forUser(userId);
    try {
      final deleted = await auth.deleteAccount(currentPassword);
      if (!deleted) return false;

      _pendingDeletionCleanupUserIds.add(userId);
      _message = pendingDeletionCleanupMessage;
      final current = _session == started;
      Future<void>? logout;
      int? logoutGeneration;
      if (current) {
        logout = api.logout();
        logoutGeneration = api.sessionGeneration;
        _state = const FinanceState();
        ledger.adoptState(_state);
        repository.queue.replace(const []);
        repository.unbindLocalOwner();
        _sessionGeneration++;
        auth.clearSession();
        notifyListeners();
      }

      try {
        await scopedLocal.markPendingAccountCleanup(userId);
      } catch (_) {}
      try {
        await repository.session.purgePartition(scopedLocal);
        await scopedLocal.clearPendingAccountCleanup(userId);
        _pendingDeletionCleanupUserIds.remove(userId);
        if (_pendingDeletionCleanupUserIds.isEmpty) _message = null;
      } catch (_) {
        _message = pendingDeletionCleanupMessage;
        notifyListeners();
      }

      if (logoutGeneration != null &&
          api.sessionGeneration == logoutGeneration) {
        try {
          await api.onAuthExpired?.call();
        } catch (_) {}
      }
      try {
        await logout;
      } catch (_) {}
      return true;
    } on ApiFailure catch (failure) {
      if (_session != started) return false;
      _message = failure.message;
      notifyListeners();
      return false;
    }
  }

  Future<void> addTransaction(FinanceTransaction transaction) async {
    final started = _session;
    await ledger.addTransaction(transaction);
    if (_session != started) return;
    await checkBudgetAlerts();
    if (_session != started) return;
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
    ledger.adoptState(_state);
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
    ledger.adoptState(_state);
    _message = '账户配置已保存';
    notifyListeners();
  }

  Future<void> addCategory(
      {required String name, required TransactionType type}) async {
    await ledger.addCategory(name: name, type: type);
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
    await ledger.updateCategory(categoryId, name: name, active: active);
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
    await ledger.updateTransaction(transaction);
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
          amount:
              remoteDraft.amount > 0 ? remoteDraft.amount : localDraft.amount,
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

  Future<void> rememberDraftChoice(String sourceText, AgentDraft draft) async {
    final key = FinanceRules.quickMemoryKey(sourceText);
    if (key.isEmpty || draft.categoryId == null || draft.accountId == null)
      return;
    final memory = QuickMemory(
        key: key,
        categoryId: draft.categoryId,
        accountId: draft.accountId,
        updatedAt: DateTime.now().toIso8601String());
    _state = _state.copyWith(quickMemories: [
      ..._state.quickMemories.where((item) => item.key != key),
      memory
    ]);
    await repository.save(_state);
    if (repository.api != null) {
      try {
        await _authStore?.updateProfile(quickMemories: _state.quickMemories);
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
    await ledger.deleteTransaction(transactionId);
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
    _state = await repository.applyLocalBudget(_state, budget);
    ledger.adoptState(_state);
    _message = '预算已保存';
    notifyListeners();
  }

  Future<List<BudgetAlert>> checkBudgetAlerts() async {
    final raw = await repository.local
        .readMetadata(LocalRepository.budgetAlertsKey);
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
    if (alerts.isNotEmpty) {
      await repository.local
          .writeMetadata(LocalRepository.budgetAlertsKey, jsonEncode(seen.toList()));
    }
    _budgetAlerts = alerts;
    return alerts;
  }

  Future<void> setDefaultAccount(String accountId) async {
    if (!_state.accounts
        .any((item) => item.id == accountId && item.type == AccountType.asset))
      return;
    _state = _state.copyWith(defaultAccountId: accountId);
    await repository.save(_state);
    ledger.adoptState(_state);
    _message = '默认支付账户已更新';
    notifyListeners();
  }

  Future<void> sync() async {
    final started = _session;
    final pushed = await repository.pushPending(_state);
    if (_session != started) return;
    _state = pushed;
    ledger.adoptState(_state);
    final pulled = await repository.pullChanges(_state);
    if (_session != started) return;
    _state = pulled;
    ledger.adoptState(_state);
    if (_session != started) return;
    _message = _state.syncState.error ??
        (_state.syncState.lastSyncedAt == null ? '离线演示/待配置' : '已完成同步');
    notifyListeners();
  }

  void clearAuthenticatedSession() {
    _sessionGeneration++;
    _authStore?.clearSession();
    _draft = null;
    _draftSourceText = null;
    _message = null;
    _budgetAlerts = const [];
    _metricsState = null;
    _metricsMonth = null;
    _metricsCache = null;
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
    ledger.adoptState(_state);
  }

  Future<void> restoreDemoData() async {
    _state = DemoData.create();
    ledger.adoptState(_state);
    _draft = null;
    _draftSourceText = null;
    _message = '演示数据已恢复';
    await repository.clearPendingOperations();
    await repository.save(_state);
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
        ledger.adoptState(_state);
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
    ledger.adoptState(_state);
    await repository.save(_state);
    _message = '月度报告已更新';
    notifyListeners();
  }

  static String _monthKey(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}';
}
