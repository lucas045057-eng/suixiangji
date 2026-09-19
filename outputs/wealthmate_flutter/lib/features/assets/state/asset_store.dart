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
  List<Account> get activeAccounts => _state.accounts
      .where((item) => item.deletedAt == null)
      .toList(growable: false);
  List<ExchangeRateSnapshot> get exchangeRates =>
      List.unmodifiable(_state.exchangeRates);
  List<Goal> get goals => List.unmodifiable(_state.goals);
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

  Future<void> calibrateBalance(Account account, double delta) async {
    final current =
        _state.accounts.where((item) => item.id == account.id).firstOrNull;
    if (current == null) return;

    late final Account calibrated;
    try {
      calibrated = AssetRules.calibrateBalance(current, delta);
    } on ArgumentError catch (error) {
      _message = error.message?.toString() ?? '余额校准金额无效';
      _notifyMessageChanged();
      return;
    }
    if (!await _apply((baseState) =>
        repository.saveAccount(calibrated, baseState: baseState))) {
      return;
    }
    _message = '账户余额已校准';
    _notifyChanged();
    onLocalMutation?.call('assets.account.calibrate');
  }

  Future<void> setDefaultAccount(String accountId) async {
    final eligible = _state.accounts.any((item) =>
        item.id == accountId &&
        item.deletedAt == null &&
        item.type == AccountType.asset);
    if (!eligible) return;
    if (!await _apply((baseState) =>
        repository.setDefaultAccount(accountId, baseState: baseState))) {
      return;
    }
    _message = '默认支付账户已更新';
    _notifyChanged();
  }

  Future<void> saveManualExchangeRate({
    required String baseCurrency,
    required double rate,
    required String rateDate,
    required String source,
  }) async {
    final base = baseCurrency.trim().toUpperCase();
    if (base.length < 3 ||
        base == 'CNY' ||
        rate <= 0 ||
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
    if (repository.remote != null) {
      try {
        await repository.remote!.saveExchangeRate(snapshot.toJson());
        _message = '汇率已保存并同步';
      } on ApiFailure {
        _message = '汇率已保存在本机，联网后可再次同步';
      }
    } else {
      _message = '汇率已保存到本地';
    }
    _notifyChanged();
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
      if (snapshot.rate <= 0) {
        throw const ApiFailure(ApiFailureKind.validation, '公开汇率无效');
      }
      if (!await _apply((baseState) =>
          repository.saveExchangeRate(snapshot, baseState: baseState))) {
        return;
      }
      _message = '已获取并保存 ${snapshot.baseCurrency}/CNY 汇率';
      _notifyChanged();
    } on Object {
      _message = '获取汇率失败，已保留上一次可靠汇率';
      _notifyMessageChanged();
    }
  }

  static String _monthKey(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}';
}
