import 'package:flutter/foundation.dart' show ChangeNotifier;

import '../../../data/api_client.dart';
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
    final account = Account(
      id: 'account-${DateTime.now().microsecondsSinceEpoch}',
      name: name,
      type: type,
      accountKind: accountKind,
      currency: currency.toUpperCase(),
      openingBalance: openingBalance,
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
    if (!_state.accounts.any((item) => item.id == account.id)) return;
    if (AssetRules.hasDuplicateAccountName(
      _state,
      account.name,
      excludingId: account.id,
    )) {
      _message = '账户名称不能重复';
      _notifyMessageChanged();
      return;
    }
    if (!await _apply(
        (baseState) => repository.saveAccount(account, baseState: baseState))) {
      return;
    }
    _message = '账户配置已保存';
    _notifyChanged();
    onLocalMutation?.call('assets.account.update');
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
  /// The client replays the balance as of the effective date, posts the
  /// dedicated calibration command, and adopts the authoritative row. A
  /// rejected command never leaves the optimistic row behind; when the device
  /// is offline the target is kept as an explicitly unsubmitted draft.
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
    final replay =
        AssetRules.replayBalance(_state, current, asOfDate: effective);
    if (replay.pending > 0) {
      _message = '账户存在待换算账目，请先补充汇率';
      _notifyMessageChanged();
      return;
    }
    final expected = replay.rawCny;
    final delta = AssetRules.round6(draft.targetCny - expected);
    if (delta == 0) {
      _message = '余额已一致，无需校准';
      _notifyMessageChanged();
      return;
    }
    final pendingDraft = draft.copyWith(expectedCurrentCny: expected);
    if (repository.remote == null) {
      await _saveUnsubmittedDraft(pendingDraft);
      return;
    }

    final stamp = DateTime.now().microsecondsSinceEpoch;
    final clientOpId = 'cal-$stamp';
    final adjustmentId = 'adj-$stamp';
    final target = draft.targetCny.toStringAsFixed(2);
    final optimistic = FinanceTransaction(
      id: adjustmentId,
      date: effective,
      occurredAt: '${effective}T00:00:00',
      type: TransactionType.adjustment,
      amount: delta,
      accountId: current.id,
      currency: 'CNY',
      cnyAmount: delta,
      exchangeRate: 1,
      conversionStatus: 'ready',
      adjustmentMeta: {
        'reason': 'balance_calibration',
        'target_cny': target,
        'basis_balance_cny': expected.toStringAsFixed(6),
        'effective_on': effective,
      },
      clientOpId: clientOpId,
    );
    if (!await _apply((baseState) => repository.saveLocalAdjustment(optimistic,
        baseState: baseState))) {
      return;
    }
    try {
      final authoritative = await repository.remote!.calibrate(
        accountId: current.id,
        clientOpId: clientOpId,
        adjustmentId: adjustmentId,
        targetCny: target,
        effectiveOn: effective,
        expectedCurrentCny: expected.toStringAsFixed(6),
      );
      if (!await _apply((baseState) => repository.adoptAdjustment(
            authoritative,
            accountId: current.id,
            optimisticAdjustmentId: adjustmentId,
            optimisticClientOpId: clientOpId,
            baseState: baseState,
          ))) {
        return;
      }
      _message = '余额校准已提交';
      _notifyChanged();
      onLocalMutation?.call('assets.account.calibrate');
    } on ApiFailure catch (failure) {
      if (failure.code == 'balance_changed') {
        await _discard(adjustmentId);
        _message = '账目已变化，请重新核对校准';
        _notifyChanged();
        onLocalMutation?.call('assets.account.calibrate.conflict');
      } else if (failure.code == 'balance_unchanged') {
        await _discard(adjustmentId);
        _message = '余额已一致，无需校准';
        _notifyChanged();
      } else if (failure.code == 'conversion_pending') {
        await _discard(adjustmentId);
        _message = '账户存在待换算账目，请先补充汇率';
        _notifyChanged();
      } else if (failure.kind == ApiFailureKind.network ||
          failure.kind == ApiFailureKind.configuration) {
        await _saveUnsubmittedDraft(pendingDraft, removeAdjustmentId: adjustmentId);
      } else {
        await _discard(adjustmentId);
        _message = _calibrationFailureMessage(failure);
        _notifyMessageChanged();
      }
    }
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
    final effective = original.date.compareTo(today) > 0 ? original.date : today;
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
    await _apply((baseState) => repository.discardAdjustment(adjustmentId,
        baseState: baseState));
  }

  String _calibrationFailureMessage(ApiFailure failure) {
    return switch (failure.code) {
      'account_inactive' => '账户已归档或删除，无法校准',
      'operation_mismatch' || 'adjustment_id_used' => '校准操作重复，请重试',
      _ => failure.detail ?? failure.message,
    };
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
