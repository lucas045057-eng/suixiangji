import 'package:flutter/foundation.dart' show ChangeNotifier;

import '../../../data/api_client.dart';
import '../../../domain/cny_amount.dart';
import '../../../domain/finance_rules.dart';
import '../../../domain/models.dart';
import '../data/assets_repository.dart';
import '../domain/asset_rules.dart';

class AssetStore extends ChangeNotifier {
  AssetStore({required this.repository, FinanceState? initialState})
      : _state = initialState ?? const FinanceState(),
        _initialStatePending = initialState != null;

  final AssetsRepository repository;
  FinanceState _state;
  bool _initialStatePending;
  String? _message;

  /// Called when an Assets mutation also needs to update a compatibility store.
  void Function(FinanceState state)? onStateChanged;
  void Function(String reason)? onLocalMutation;
  void Function(String? message)? onMessageChanged;

  /// Optional pre-flight sync. The calibration contract expects the account to
  /// be current before a basis token is issued; FinanceStore wires its sync
  /// pipeline here so the feature itself stays independent of it.
  Future<void> Function()? beforeCalibration;

  WealthView? _wealthView;

  /// Latest remote V2 wealth snapshot, when explicitly loaded. Local metrics
  /// remain the default current view.
  WealthView? get wealthView => _wealthView;

  FinanceState get state => _state;
  List<Account> get accounts => List.unmodifiable(_state.accounts);
  List<Account> get activeAccounts =>
      _state.accounts.where((item) => item.isActive).toList(growable: false);
  List<ExchangeRateSnapshot> get exchangeRates =>
      List.unmodifiable(_state.exchangeRates);
  String? get message => _message;
  bool get isDemoMode => repository.api == null;

  FinanceMetrics get metrics {
    final month = _state.currentMonth.isEmpty
        ? _monthKey(DateTime.now())
        : _state.currentMonth;
    return FinanceRules.deriveMetrics(_state, month);
  }

  List<AccountBalance> get accountBalances => metrics.accountBalances;
  double get assetTotal => metrics.assetTotal;
  double get liabilityTotal => metrics.liabilityTotal;
  double get netWorth => metrics.netWorth;
  int get pendingConversionCount => metrics.pendingConversionCount;

  Set<String> get foreignCurrencies => <String>{
        ..._state.accounts.map((item) => item.currency.toUpperCase()),
        ..._state.transactions.map((item) => item.currency.toUpperCase()),
      }..remove('CNY');

  void adoptState(FinanceState state, {bool notify = false}) {
    _state = state;
    _initialStatePending = false;
    if (notify) {
      onStateChanged?.call(state);
      notifyListeners();
    }
  }

  /// Loads the V2 `/wealth` view, optionally as of an explicit business date.
  ///
  /// Totals stay null when any entry is pending conversion; the UI must show
  /// "待换算" instead of treating the missing total as zero.
  Future<void> loadWealth({String? asOfDate}) async {
    if (repository.remote == null) {
      _message = '当前未配置同步服务';
      _notifyMessageChanged();
      return;
    }
    try {
      final view = await repository.fetchWealthSnapshot(asOfDate: asOfDate);
      _wealthView = view;
      _message = view.hasPending ? '账面净值存在待换算账目' : null;
      _notifyChanged();
    } on ApiFailure catch (failure) {
      _message = failure.detail ?? failure.message;
      _notifyMessageChanged();
    }
  }

  Future<bool> _apply(
      Future<FinanceState> Function(FinanceState? baseState) write) async {
    final startedLocal = repository.session.local;
    final baseState = _initialStatePending ? _state : null;
    _initialStatePending = false;
    final next = await write(baseState);
    if (!identical(repository.session.local, startedLocal)) return false;
    _state = next;
    return true;
  }

  void _notifyChanged() {
    onStateChanged?.call(_state);
    notifyListeners();
  }

  void _notifyMessageChanged() {
    onMessageChanged?.call(_message);
    notifyListeners();
  }

  Future<void> addAccount({
    required String name,
    required AccountType type,
    String currency = 'CNY',
    double openingBalance = 0,
    AccountKind accountKind = AccountKind.other,
  }) async {
    if (AssetRules.hasDuplicateAccountName(_state, name)) {
      _message = '账户名称不能重复';
      _notifyMessageChanged();
      return;
    }
    final normalizedCurrency = currency.toUpperCase();
    // A new foreign account freezes the newest already-stored, dated rate.
    // Waiting for the user to open 管理汇率 and refresh again was why a fresh
    // account could sit at 0 even though the app already knew a usable rate.
    final stored = AssetRules.latestStoredRate(_state, normalizedCurrency);
    final account = Account(
      id: 'account-${DateTime.now().microsecondsSinceEpoch}',
      name: name,
      type: type,
      accountKind: accountKind,
      currency: normalizedCurrency,
      openingBalance: openingBalance,
      openingCnyAmount: stored == null ? null : openingBalance * stored.rate,
      exchangeRate: stored?.rate,
      exchangeRateDate: stored?.rateDate,
      exchangeRateSource: stored?.source,
    );
    if (!await _apply(
        (baseState) => repository.saveAccount(account, baseState: baseState))) {
      return;
    }
    _message = '账户已保存到本地，联网后会同步';
    _notifyChanged();
    onLocalMutation?.call('assets.account.add');
  }

  Future<void> updateAccount(Account account) async {
    final existing =
        _state.accounts.where((item) => item.id == account.id).firstOrNull;
    if (existing == null) return;
    if (AssetRules.hasDuplicateAccountName(
      _state,
      account.name,
      excludingId: account.id,
    )) {
      _message = '账户名称不能重复';
      _notifyMessageChanged();
      return;
    }
    var next = account;
    final currencyChanged =
        existing.currency.toUpperCase() != account.currency.toUpperCase();
    if (currencyChanged) {
      // Never carry one currency's snapshot into another.
      next = _refreezeOpening(account);
    } else if (existing.openingBalance != account.openingBalance) {
      // An edited opening amount is re-frozen at the account's own dated rate;
      // today's quote must not silently revalue it.
      next = _refreezeOpening(account, preferAccountRate: true);
    }
    if (!await _apply(
        (baseState) => repository.saveAccount(next, baseState: baseState))) {
      return;
    }
    _message = '账户配置已保存';
    _notifyChanged();
    onLocalMutation?.call('assets.account.update');
  }

  /// Rebuilds a foreign opening snapshot from dated stored rates.
  ///
  /// [preferAccountRate] keeps the rate the account was already frozen with
  /// (an edited opening amount); otherwise the newest stored rate for the
  /// current currency is used. No usable rate leaves the opening pending, so
  /// the UI can show 「待换算」 instead of 0.
  Account _refreezeOpening(Account account, {bool preferAccountRate = false}) {
    final previousRate = account.exchangeRate;
    final previousDate = account.exchangeRateDate;
    final previousSource = account.exchangeRateSource;
    final cleared = account.copyWith(clearOpeningConversion: true);
    if (cleared.currency.toUpperCase() == 'CNY') return cleared;
    if (preferAccountRate &&
        previousRate != null &&
        previousRate.isFinite &&
        previousRate > 0 &&
        previousDate != null &&
        DateTime.tryParse(previousDate) != null) {
      return cleared.copyWith(
        openingCnyAmount: cleared.openingBalance * previousRate,
        exchangeRate: previousRate,
        exchangeRateDate: previousDate,
        exchangeRateSource: previousSource,
      );
    }
    final stored = AssetRules.latestStoredRate(_state, cleared.currency);
    if (stored == null) return cleared;
    return cleared.copyWith(
      openingCnyAmount: cleared.openingBalance * stored.rate,
      exchangeRate: stored.rate,
      exchangeRateDate: stored.rateDate,
      exchangeRateSource: stored.source,
    );
  }

  Future<void> archiveAccount(String id) async {
    final account =
        _state.accounts.where((a) => a.id == id && a.isActive).firstOrNull;
    if (account == null) return;
    await updateAccount(account.copyWith(
        archivedAt: DateTime.now().toIso8601String(), isDefaultPayment: false));
  }

  Future<void> restoreAccount(String id) async {
    final account = _state.accounts
        .where((a) => a.id == id && a.deletedAt == null && a.archivedAt != null)
        .firstOrNull;
    if (account == null) return;
    await updateAccount(account.copyWith(clearArchivedAt: true));
  }

  CalibrationDraft? calibrationDraftFor(String accountId) =>
      _state.calibrationDraftFor(accountId);

  /// Raw six-decimal replay for the calibration preview, or null when the
  /// account still has entries without a CNY snapshot.
  double? expectedBalanceFor(Account account, {String? effectiveOn}) {
    final current =
        _state.accounts.where((item) => item.id == account.id).firstOrNull;
    if (current == null) return null;
    final replay = AssetRules.replayBalance(
      _state,
      current,
      asOfDate: effectiveOn ?? _dayKey(DateTime.now()),
    );
    return replay.pending > 0 ? null : replay.rawCny;
  }

  /// Calibrates the account to [targetCny] with an immutable adjustment.
  ///
  /// Online submissions first fetch a server-signed basis token and send it
  /// with the original target/date; the client never uses its own double
  /// replay as the authoritative basis. A retry of an unresolved submission
  /// reuses the persisted token and `client_op_id` verbatim, even when the
  /// token looks locally expired — only the server may declare it expired.
  Future<void> calibrateBalance(Account account, double targetCny,
      {String? effectiveOn}) async {
    final current =
        _state.accounts.where((item) => item.id == account.id).firstOrNull;
    if (current == null) return;
    final effective = effectiveOn ?? _dayKey(DateTime.now());

    late final CalibrationDraft draft;
    try {
      draft = AssetRules.buildCalibrationDraft(
        current,
        targetCny: targetCny,
        effectiveOn: effective,
      );
    } on ArgumentError catch (error) {
      _message = error.message?.toString() ?? '人民币账面余额无效';
      _notifyMessageChanged();
      return;
    }

    final existing = _state.calibrationDraftFor(current.id);
    final retryExisting = existing != null &&
        existing.basisToken != null &&
        existing.clientOpId != null &&
        existing.adjustmentId != null &&
        existing.effectiveOn == effective &&
        (existing.targetCny - draft.targetCny).abs() < 0.005;

    var replay = AssetRules.replayBalance(_state, current, asOfDate: effective);

    if (repository.remote == null) {
      if (!retryExisting) {
        if (replay.pending > 0) {
          _message = '账户存在待换算账目，请先补充汇率';
          _notifyMessageChanged();
          return;
        }
        if (AssetRules.round6(draft.targetCny - replay.rawCny) == 0) {
          _message = '余额已一致，无需校准';
          _notifyMessageChanged();
          return;
        }
      }
      // Keep the token and operation identity untouched while offline.
      await _saveUnsubmittedDraft(retryExisting
          ? existing
          : draft.copyWith(expectedCurrentCny: replay.rawCny));
      return;
    }

    if (retryExisting) {
      await _submitCalibration(current, existing);
      return;
    }

    // Pull the account/ledger up to date before the server signs a basis.
    try {
      await beforeCalibration?.call();
    } catch (_) {
      // A failed pre-flight sync is not fatal: the basis request below will
      // either succeed or surface the same outage.
    }
    // The pre-flight sync may have replaced the account row and ledger.
    final syncedAccount =
        _state.accounts.where((item) => item.id == current.id).firstOrNull ??
            current;
    replay =
        AssetRules.replayBalance(_state, syncedAccount, asOfDate: effective);

    BalanceBasis? basis;
    try {
      basis = await repository.fetchBalanceBasis(
          accountId: current.id, effectiveOn: effective);
    } on ApiFailure catch (failure) {
      if (await _handleBasisFetchFailure(failure, draft, replay)) return;
      // A server that predates the basis endpoint (404) keeps the legacy
      // numeric path; anything else unrecognised is also treated as legacy
      // so a transient contract mismatch cannot block calibration entirely.
      basis = null;
    }

    if (basis == null && replay.pending > 0) {
      _message = '账户存在待换算账目，请先补充汇率';
      _notifyMessageChanged();
      return;
    }

    final expectedText = basis?.balanceCny ?? replay.rawCny.toStringAsFixed(6);
    final expectedExact = CnyAmount.tryParse(expectedText);
    if (expectedExact == null) {
      _message = '校准基准数据无效，请稍后重试';
      _notifyMessageChanged();
      return;
    }
    final targetExact = CnyAmount.fromDouble(draft.targetCny);
    if ((targetExact - expectedExact).isZero) {
      _message = '余额已一致，无需校准';
      _notifyMessageChanged();
      return;
    }

    final stamp = DateTime.now().microsecondsSinceEpoch;
    final submission = CalibrationDraft(
      accountId: current.id,
      targetCny: draft.targetCny,
      effectiveOn: effective,
      createdAt: draft.createdAt,
      expectedCurrentCny: expectedExact.asDouble,
      basisToken: basis?.basisToken,
      basisExpiresAt: basis?.expiresAt,
      basisBalanceCny: expectedText,
      clientOpId: 'cal-$stamp',
      adjustmentId: 'adj-$stamp',
    );
    await _submitCalibration(syncedAccount, submission);
  }

  /// Posts a persisted calibration draft (fresh or retry) and adopts the
  /// authoritative adjustment. The optimistic row always uses the exact
  /// six-decimal basis, never a locally replayed double.
  Future<void> _submitCalibration(
      Account account, CalibrationDraft submission) async {
    final basisExact = CnyAmount.tryParse(submission.basisBalanceCny ?? '') ??
        (submission.expectedCurrentCny == null
            ? null
            : CnyAmount.fromDouble(submission.expectedCurrentCny!));
    if (basisExact == null) {
      _message = '校准基准数据无效，请稍后重试';
      _notifyMessageChanged();
      return;
    }
    final targetExact = CnyAmount.fromDouble(submission.targetCny);
    final delta = (targetExact - basisExact).asDouble;
    final basisText = basisExact.toFixed6();
    final effective = submission.effectiveOn;
    final adjustmentId = submission.adjustmentId ??
        'adj-${DateTime.now().microsecondsSinceEpoch}';
    final clientOpId =
        submission.clientOpId ?? 'cal-${DateTime.now().microsecondsSinceEpoch}';
    final target = submission.targetCny.toStringAsFixed(2);

    final optimistic = FinanceTransaction(
      id: adjustmentId,
      date: effective,
      occurredAt: '${effective}T00:00:00',
      type: TransactionType.adjustment,
      amount: delta,
      accountId: account.id,
      currency: 'CNY',
      cnyAmount: delta,
      exchangeRate: 1,
      conversionStatus: 'ready',
      adjustmentMeta: {
        'reason': 'balance_calibration',
        'target_cny': target,
        'basis_balance_cny': basisText,
        'effective_on': effective,
      },
      clientOpId: clientOpId,
    );
    if (!await _apply((baseState) =>
        repository.saveLocalAdjustment(optimistic, baseState: baseState))) {
      return;
    }
    try {
      final authoritative = await repository.remote!.calibrate(
        accountId: account.id,
        clientOpId: clientOpId,
        adjustmentId: adjustmentId,
        targetCny: target,
        effectiveOn: effective,
        basisToken: submission.basisToken,
        expectedCurrentCny: submission.basisToken == null ? basisText : null,
      );
      if (!await _apply((baseState) => repository.adoptAdjustment(
            authoritative,
            accountId: account.id,
            optimisticAdjustmentId: adjustmentId,
            optimisticClientOpId: clientOpId,
            baseState: baseState,
          ))) {
        return;
      }
      _wealthView = null;
      _message = '余额校准已提交';
      _notifyChanged();
      onLocalMutation?.call('assets.account.calibrate');
    } on ApiFailure catch (failure) {
      await _handleSubmitFailure(failure, submission, adjustmentId);
    }
  }

  Future<void> _handleSubmitFailure(ApiFailure failure,
      CalibrationDraft submission, String adjustmentId) async {
    final code = failure.code;
    if (code == 'basis_expired' || code == 'invalid_basis_token') {
      await _discard(adjustmentId);
      await _renewBasisAfterExpiry(submission);
      return;
    }
    if (failure.kind == ApiFailureKind.network ||
        failure.kind == ApiFailureKind.configuration) {
      // Preserve the exact token + operation IDs for a byte-identical retry.
      await _saveUnsubmittedDraft(submission, removeAdjustmentId: adjustmentId);
      return;
    }
    await _discard(adjustmentId);
    await _apply((baseState) => repository
        .clearCalibrationDraft(submission.accountId, baseState: baseState));
    _message = switch (code) {
      'balance_changed' => '账目已变化，请刷新账目后重新核对校准',
      'conversion_pending' => '账户存在待换算账目，请先补充汇率',
      'basis_scope_mismatch' => '校准基准与账户或日期不匹配，请重新校准',
      'basis_out_of_range' => '校准金额超出可记录范围',
      'invalid_effective_on' => '校准日期无效，请选择今天或更早的日期',
      'operation_mismatch' || 'adjustment_id_used' => '该校准操作已提交过，请重新发起校准',
      'balance_unchanged' => '余额已一致，无需校准',
      'account_inactive' => '账户已归档或删除，无法校准',
      _ => failure.detail ?? failure.message,
    };
    _notifyChanged();
  }

  /// Refetches the basis after the server rejected an expired token. The user
  /// must confirm the target again; nothing is resubmitted automatically.
  Future<void> _renewBasisAfterExpiry(CalibrationDraft previous) async {
    var next = previous.copyWith(clearBasis: true, clearOperation: true);
    try {
      final basis = await repository.remote!.fetchBalanceBasis(
          accountId: previous.accountId, effectiveOn: previous.effectiveOn);
      final stamp = DateTime.now().microsecondsSinceEpoch;
      next = next.copyWith(
        basisToken: basis.basisToken,
        basisExpiresAt: basis.expiresAt,
        basisBalanceCny: basis.balanceCny,
        expectedCurrentCny: CnyAmount.tryParse(basis.balanceCny)?.asDouble,
        clientOpId: 'cal-$stamp',
        adjustmentId: 'adj-$stamp',
      );
      _message = '校准基准已更新，请核对金额后重新提交';
    } catch (_) {
      _message = '校准基准已失效，请重新校准';
    }
    await _apply((baseState) =>
        repository.discardAdjustment('', draft: next, baseState: baseState));
    _notifyChanged();
  }

  Future<bool> _handleBasisFetchFailure(ApiFailure failure,
      CalibrationDraft draft, ({double rawCny, int pending}) replay) async {
    if (failure.code == 'conversion_pending') {
      _message = '账户存在待换算账目，请先补充汇率';
      _notifyMessageChanged();
      return true;
    }
    if (failure.code == 'invalid_effective_on') {
      _message = '校准日期无效，请选择今天或更早的日期';
      _notifyMessageChanged();
      return true;
    }
    if (failure.code == 'account_inactive') {
      _message = '账户已归档或删除，无法校准';
      _notifyMessageChanged();
      return true;
    }
    if (failure.code == 'basis_out_of_range') {
      _message = '校准金额超出可记录范围';
      _notifyMessageChanged();
      return true;
    }
    if (failure.kind == ApiFailureKind.network ||
        failure.kind == ApiFailureKind.configuration) {
      if (replay.pending > 0) {
        _message = '账户存在待换算账目，请先补充汇率';
        _notifyMessageChanged();
        return true;
      }
      final expected = replay.rawCny;
      if (AssetRules.round6(draft.targetCny - expected) == 0) {
        _message = '余额已一致，无需校准';
        _notifyMessageChanged();
        return true;
      }
      await _saveUnsubmittedDraft(draft.copyWith(expectedCurrentCny: expected));
      return true;
    }
    return false;
  }

  /// Reverses an original calibration with a new opposite adjustment.
  ///
  /// Reversals are not queued offline: the backend only accepts them through
  /// this dedicated command, so a failed request leaves no local residue.
  Future<void> reverseAdjustment(FinanceTransaction original) async {
    if (!original.isAdjustment || original.isReversal) return;
    final accountId = original.accountId;
    if (accountId == null) return;
    if (repository.remote == null) {
      _message = '需要联网才能撤销校准';
      _notifyMessageChanged();
      return;
    }
    final stamp = DateTime.now().microsecondsSinceEpoch;
    final today = _dayKey(DateTime.now());
    final effective =
        original.date.compareTo(today) > 0 ? original.date : today;
    try {
      final reversal = await repository.remote!.reverseCalibration(
        accountId: accountId,
        transactionId: original.id,
        clientOpId: 'rev-$stamp',
        adjustmentId: 'adj-rev-$stamp',
        effectiveOn: effective,
      );
      if (!await _apply((baseState) => repository.adoptAdjustment(
            reversal,
            accountId: accountId,
            baseState: baseState,
          ))) {
        return;
      }
      _message = '校准已撤销';
      _notifyChanged();
      onLocalMutation?.call('assets.account.calibrate.reverse');
    } on ApiFailure catch (failure) {
      _message = switch (failure.code) {
        'already_reversed' => '该校准已撤销',
        'not_reversible' => '该流水不可撤销',
        'operation_mismatch' || 'adjustment_id_used' => '撤销操作重复，请稍后重试',
        'account_inactive' => '账户已归档或删除，无法撤销',
        _ => failure.kind == ApiFailureKind.network
            ? '撤销失败，请检查网络后重试'
            : (failure.detail ?? failure.message),
      };
      _notifyMessageChanged();
    }
  }

  Future<void> _saveUnsubmittedDraft(CalibrationDraft draft,
      {String? removeAdjustmentId}) async {
    if (!await _apply((baseState) => repository.discardAdjustment(
          removeAdjustmentId ?? '',
          draft: draft,
          baseState: baseState,
        ))) {
      return;
    }
    _message = '当前未联网，校准已保存为未提交草稿';
    _notifyChanged();
  }

  Future<void> _discard(String adjustmentId) async {
    await _apply((baseState) =>
        repository.discardAdjustment(adjustmentId, baseState: baseState));
  }

  Future<void> setDefaultAccount(String accountId) async {
    final eligible = _state.accounts.any((item) =>
        item.id == accountId &&
        item.isActive &&
        item.type == AccountType.asset);
    if (!eligible) return;
    if (!await _apply((baseState) =>
        repository.setDefaultAccount(accountId, baseState: baseState))) {
      return;
    }
    _message = '默认支付账户已更新';
    _notifyChanged();
    onLocalMutation?.call('assets.account.default');
  }

  Future<void> saveManualExchangeRate({
    required String baseCurrency,
    required double rate,
    required String rateDate,
    required String source,
  }) async {
    final base = baseCurrency.trim().toUpperCase();
    if (!RegExp(r'^[A-Z]{3}$').hasMatch(base) ||
        base == 'CNY' ||
        !rate.isFinite ||
        rate <= 0 ||
        DateTime.tryParse(rateDate) == null ||
        source.trim().isEmpty) {
      _message = '汇率需要填写有效币种、正数汇率和来源';
      _notifyMessageChanged();
      return;
    }
    final snapshot = ExchangeRateSnapshot(
      baseCurrency: base,
      rate: rate,
      rateDate: rateDate,
      source: source.trim(),
      updatedAt: DateTime.now().toIso8601String(),
    );
    if (!await _apply((baseState) =>
        repository.saveExchangeRate(snapshot, baseState: baseState))) {
      return;
    }
    _message = '汇率已保存到本地，账户快照将随账目同步';
    _notifyChanged();
    onLocalMutation?.call('assets.rate.manual');
  }

  Future<void> refreshExchangeRate(String baseCurrency) async {
    if (repository.remote == null) {
      _message = '当前未配置同步服务，无法获取公开汇率';
      _notifyMessageChanged();
      return;
    }
    try {
      final json = await repository.remote!
          .fetchExchangeRate(baseCurrency.toUpperCase());
      final snapshot = ExchangeRateSnapshot.fromJson(json);
      if (!snapshot.rate.isFinite || snapshot.rate <= 0) {
        throw const ApiFailure(ApiFailureKind.validation, '公开汇率无效');
      }
      if (!await _apply((baseState) =>
          repository.saveExchangeRate(snapshot, baseState: baseState))) {
        return;
      }
      _message = json['stale'] == true
          ? '汇率服务暂不可用，使用 ${snapshot.rateDate} 的缓存汇率'
          : '已获取并保存 ${snapshot.baseCurrency}/CNY 汇率';
      _notifyChanged();
      onLocalMutation?.call('assets.rate.refresh');
    } on Object {
      _message = '获取汇率失败，已保留上一次可靠汇率';
      _notifyMessageChanged();
    }
  }

  static String _dayKey(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';

  static String _monthKey(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}';
}
