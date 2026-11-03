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
      return next.copyWith(defaultAccountId: account.id);
    }
    return next;
  }

  /// Builds a local calibration draft. It deliberately does not touch the
  /// account: 1.0.10 only records the user's target until the adjustment-based
  /// calibration ships.
  static CalibrationDraft buildCalibrationDraft(
    Account account, {
    required double targetCny,
    required String effectiveOn,
    DateTime? createdAt,
  }) {
    if (!targetCny.isFinite) {
      throw ArgumentError.value(targetCny, 'targetCny', '必须是有限数');
    }
    if (targetCny <= 0) {
      throw ArgumentError.value(targetCny, 'targetCny', '人民币账面余额必须大于零');
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
    );
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
    return eligible ? state.copyWith(defaultAccountId: accountId) : state;
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
    if (transaction.currency == 'CNY') {
      return transaction.cnyAmount ?? transaction.amount;
    }
    return transaction.cnyAmount;
  }

  static double _round(double value, [int decimals = 2]) {
    final scale = math.pow(10, decimals).toDouble();
    final epsilon = value.isNegative ? -1e-9 : 1e-9;
    return ((value * scale) + epsilon).roundToDouble() / scale;
  }
}
