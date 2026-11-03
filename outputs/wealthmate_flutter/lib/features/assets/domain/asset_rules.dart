import 'dart:math' as math;

import '../../../domain/models.dart';

/// Pure account, exchange-rate, and net-worth decisions for Assets.
class AssetRules {
  static bool hasDuplicateAccountName(
    FinanceState state,
    String name, {
    String? excludingId,
  }) {
    final normalized = name.trim().toLowerCase();
    return normalized.isEmpty ||
        state.accounts.any((item) =>
            item.id != excludingId &&
            item.deletedAt == null &&
            item.name.trim().toLowerCase() == normalized);
  }

  static FinanceState upsertAccount(FinanceState state, Account account) {
    final next = state.copyWith(accounts: [
      ...state.accounts.where((item) => item.id != account.id),
      account,
    ]);
    if (account.isDefaultPayment && account.type == AccountType.asset) {
      return setDefaultAccount(next, account.id);
    }
    if (!account.isDefaultPayment && state.defaultAccountId == account.id) {
      return _clearDefaultProjection(next);
    }
    return next;
  }

  /// Builds a local calibration draft. It never touches the account or its
  /// opening balance; a draft is only written when submission was not possible.
  ///
  /// Zero and negative targets are valid: an asset may be overdrawn and a
  /// liability may carry a positive (or corrected) balance.
  static CalibrationDraft buildCalibrationDraft(
    Account account, {
    required double targetCny,
    required String effectiveOn,
    DateTime? createdAt,
    double? expectedCurrentCny,
  }) {
    if (!targetCny.isFinite) {
      throw ArgumentError.value(targetCny, 'targetCny', '必须是有限数');
    }
    if (targetCny.abs() >= 1e14) {
      throw ArgumentError.value(targetCny, 'targetCny', '金额超出可记录范围');
    }
    final cents = targetCny * 100;
    if ((cents - cents.roundToDouble()).abs() > 1e-6) {
      throw ArgumentError.value(targetCny, 'targetCny', '最多保留两位小数');
    }
    final date = _parseDate(effectiveOn);
    if (date == null) {
      throw ArgumentError.value(
          effectiveOn, 'effectiveOn', '日期格式必须为 YYYY-MM-DD');
    }
    final now = createdAt ?? DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    if (date.isAfter(today)) {
      throw ArgumentError.value(effectiveOn, 'effectiveOn', '不能使用未来日期');
    }
    return CalibrationDraft(
      accountId: account.id,
      targetCny: _round(targetCny),
      effectiveOn: effectiveOn,
      createdAt: now.toIso8601String(),
      expectedCurrentCny: expectedCurrentCny,
    );
  }

  /// Inserts or replaces one transaction without queueing a sync operation.
  ///
  /// Adjustments are written only through the dedicated calibration
  /// endpoints, so they must never appear in the normal transaction push.
  static FinanceState upsertTransaction(
      FinanceState state, FinanceTransaction transaction) {
    return state.copyWith(transactions: [
      ...state.transactions.where((item) => item.id != transaction.id),
      transaction,
    ]);
  }

  static FinanceState removeTransaction(FinanceState state, String id) {
    return state.copyWith(
        transactions:
            state.transactions.where((item) => item.id != id).toList());
  }

  static FinanceState upsertCalibrationDraft(
      FinanceState state, CalibrationDraft draft) {
    return state.copyWith(calibrationDrafts: [
      ...state.calibrationDrafts
          .where((item) => item.accountId != draft.accountId),
      draft,
    ]);
  }

  static DateTime? _parseDate(String value) {
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) return null;
    final parsed = DateTime.tryParse(value);
    if (parsed == null) return null;
    final normalized = '${parsed.year.toString().padLeft(4, '0')}-'
        '${parsed.month.toString().padLeft(2, '0')}-'
        '${parsed.day.toString().padLeft(2, '0')}';
    return normalized == value ? parsed : null;
  }

  static FinanceState setDefaultAccount(FinanceState state, String accountId) {
    final eligible = state.accounts.any((item) =>
        item.id == accountId &&
        item.isActive &&
        item.type == AccountType.asset);
    if (!eligible) return state;
    final preference = state.preference ?? const UserPreference();
    return state.copyWith(
      defaultAccountId: accountId,
      preference: preference.copyWith(defaultAccountId: accountId),
      accounts: [
        for (final account in state.accounts)
          account.isDefaultPayment == (account.id == accountId)
              ? account
              : account.copyWith(isDefaultPayment: account.id == accountId),
      ],
    );
  }

  /// Keeps `isDefaultPayment` as a pure projection of the singleton preference.
  static FinanceState projectDefaultAccount(
      FinanceState state, String? accountId) {
    final next = accountId == null
        ? state.copyWith(clearDefaultAccountId: true)
        : state.copyWith(defaultAccountId: accountId);
    return next.copyWith(accounts: [
      for (final account in next.accounts)
        account.isDefaultPayment == (account.id == accountId)
            ? account
            : account.copyWith(isDefaultPayment: account.id == accountId),
    ]);
  }

  static FinanceState _clearDefaultProjection(FinanceState state) {
    final preference = state.preference ?? const UserPreference();
    return projectDefaultAccount(
        state.copyWith(
            preference: preference.copyWith(clearDefaultAccount: true)),
        null);
  }

  static FinanceState applyExchangeRate(
      FinanceState state, ExchangeRateSnapshot snapshot) {
    if (!snapshot.rate.isFinite ||
        snapshot.rate <= 0 ||
        snapshot.quoteCurrency != 'CNY' ||
        DateTime.tryParse(snapshot.rateDate) == null) {
      throw ArgumentError('需要有效的人民币汇率快照');
    }
    final base = snapshot.baseCurrency.toUpperCase();
    final rates = [
      ...state.exchangeRates.where((item) =>
          item.baseCurrency != snapshot.baseCurrency ||
          item.quoteCurrency != snapshot.quoteCurrency),
      snapshot,
    ];
    final accounts = state.accounts.map((account) {
      // Landed CNY snapshots are frozen. A rate refresh only fills accounts
      // that have never had one; it must not revalue history.
      if (!account.isActive ||
          account.currency.toUpperCase() != base ||
          account.openingCnyAmount != null) {
        return account;
      }
      return account.copyWith(
        openingCnyAmount: account.openingBalance * snapshot.rate,
        exchangeRate: snapshot.rate,
        exchangeRateDate: snapshot.rateDate,
        exchangeRateSource: snapshot.source,
      );
    }).toList();
    return state.copyWith(exchangeRates: rates, accounts: accounts);
  }

  static List<AccountBalance> accountBalances(
    FinanceState state,
    List<FinanceTransaction> visibleTransactions,
  ) {
    return state.accounts
        .where((item) => item.isActive)
        .map((account) => AccountBalance(
              account: account,
              balance: _accountBalance(account, visibleTransactions),
            ))
        .toList(growable: false);
  }

  static double _accountBalance(
      Account account, List<FinanceTransaction> transactions) {
    var balance = account.currency.toUpperCase() == 'CNY'
        ? account.openingBalance
        : (account.openingCnyAmount ?? 0);
    for (final transaction in transactions) {
      final amount = _cnyAmount(transaction);
      if (amount == null) continue;
      balance = _applyTransaction(account, balance, transaction, amount);
    }
    return _round(balance);
  }

  /// Raw six-decimal replay used as the calibration basis.
  ///
  /// Mirrors the backend replay: adjustments add their signed delta directly
  /// for both assets and liabilities, transfers move value between accounts,
  /// and income/expense keep their per-kind sign. Transactions after
  /// [asOfDate] are excluded, so calibrating a past date cannot absorb later
  /// entries.
  static ({double rawCny, int pending}) replayBalance(
    FinanceState state,
    Account account, {
    String? asOfDate,
  }) {
    final opening = account.currency.toUpperCase() == 'CNY'
        ? account.openingBalance
        : account.openingCnyAmount;
    var balance = opening ?? 0;
    var pending = opening == null ? 1 : 0;
    for (final transaction in state.transactions) {
      if (transaction.deletedAt != null) continue;
      if (asOfDate != null && transaction.date.compareTo(asOfDate) > 0) {
        continue;
      }
      final related = transaction.accountId == account.id ||
          transaction.fromAccountId == account.id ||
          transaction.toAccountId == account.id;
      if (!related) continue;
      final amount = _cnyAmount(transaction);
      if (amount == null) {
        pending += 1;
        continue;
      }
      balance = _applyTransaction(account, balance, transaction, amount);
    }
    return (rawCny: _round(balance, 6), pending: pending);
  }

  static double _applyTransaction(Account account, double balance,
      FinanceTransaction transaction, double amount) {
    if (transaction.isAdjustment) {
      if (transaction.accountId == account.id) balance += amount;
      return balance;
    }
    if (transaction.type == TransactionType.transfer) {
      if (transaction.fromAccountId == account.id) balance -= amount;
      if (transaction.toAccountId == account.id) balance += amount;
      return balance;
    }
    if (transaction.accountId != account.id) return balance;
    if (account.type == AccountType.liability) {
      return balance +
          (transaction.type == TransactionType.expense ? amount : -amount);
    }
    return balance +
        (transaction.type == TransactionType.income ? amount : -amount);
  }

  static double? _cnyAmount(FinanceTransaction transaction) {
    if (transaction.currency == 'CNY') {
      return transaction.cnyAmount ?? transaction.amount;
    }
    return transaction.cnyAmount;
  }

  /// Raw money scale used by the backend replay and adjustment amounts.
  static double round6(double value) => _round(value, 6);

  static double _round(double value, [int decimals = 2]) {
    final scale = math.pow(10, decimals).toDouble();
    final epsilon = value.isNegative ? -1e-9 : 1e-9;
    return ((value * scale) + epsilon).roundToDouble() / scale;
  }
}
