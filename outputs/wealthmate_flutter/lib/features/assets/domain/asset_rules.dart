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

  static Account calibrateBalance(Account account, double delta) {
    if (!delta.isFinite) {
      throw ArgumentError.value(delta, 'delta', '必须是有限数');
    }
    final change = _round(delta);
    if (change == 0) {
      throw ArgumentError.value(delta, 'delta', '不能为零变化');
    }

    final isCny = account.currency.toUpperCase() == 'CNY';
    final current =
        isCny ? account.openingBalance : account.openingCnyAmount ?? 0;
    if (!current.isFinite) {
      throw ArgumentError.value(account, 'account', '当前余额必须是有限数');
    }
    final nextOpening = _round(current + change);
    if (!nextOpening.isFinite) {
      throw ArgumentError.value(delta, 'delta', '校准后余额必须是有限数');
    }
    return isCny
        ? account.copyWith(openingBalance: nextOpening)
        : account.copyWith(openingCnyAmount: nextOpening);
  }

  static FinanceState setDefaultAccount(FinanceState state, String accountId) {
    final eligible = state.accounts.any((item) =>
        item.id == accountId &&
        item.deletedAt == null &&
        item.type == AccountType.asset);
    return eligible ? state.copyWith(defaultAccountId: accountId) : state;
  }

  static FinanceState applyExchangeRate(
      FinanceState state, ExchangeRateSnapshot snapshot) {
    final rates = [
      ...state.exchangeRates.where((item) =>
          item.baseCurrency != snapshot.baseCurrency ||
          item.quoteCurrency != snapshot.quoteCurrency),
      snapshot,
    ];
    final accounts = state.accounts.map((account) {
      if (account.currency.toUpperCase() != snapshot.baseCurrency) {
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
        .where((item) => item.deletedAt == null)
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
