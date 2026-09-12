import 'dart:math';

import 'package:flutter/material.dart';

import '../../../domain/models.dart';
import '../../assets/domain/asset_rules.dart';
import '../../budget/domain/budget_rules.dart' as budget_rules;

class PeriodPoint {
  const PeriodPoint({
    required this.bucket,
    required this.label,
    required this.expense,
    required this.income,
  });

  final DateTime bucket;
  final String label;
  final double expense;
  final double income;
}

/// Deterministic, read-only calculations used by the Insights feature.
class InsightRules {
  static List<PeriodPoint> periodExpenseSeries(
      FinanceState state, DateTimeRange range) {
    final start =
        DateTime(range.start.year, range.start.month, range.start.day);
    final end = DateTime(range.end.year, range.end.month, range.end.day);
    final sameDay = start == end;
    final points = <PeriodPoint>[];
    if (sameDay) {
      for (var hour = 0; hour < 24; hour += 1) {
        final bucket = DateTime(start.year, start.month, start.day, hour);
        points.add(PeriodPoint(
          bucket: bucket,
          label: '${hour.toString().padLeft(2, '0')}:00',
          expense: 0,
          income: 0,
        ));
      }
    } else {
      var cursor = start;
      while (!cursor.isAfter(end)) {
        points.add(PeriodPoint(
          bucket: cursor,
          label:
              '${cursor.month.toString().padLeft(2, '0')}-${cursor.day.toString().padLeft(2, '0')}',
          expense: 0,
          income: 0,
        ));
        cursor = cursor.add(const Duration(days: 1));
      }
    }
    final expenses = List<double>.filled(points.length, 0);
    final incomes = List<double>.filled(points.length, 0);
    for (final transaction in state.transactions.where((item) =>
        item.deletedAt == null && item.type != TransactionType.transfer)) {
      final occurred = _occurredDate(transaction);
      if (occurred == null) continue;
      final date = DateTime(occurred.year, occurred.month, occurred.day);
      if (date.isBefore(start) || date.isAfter(end)) continue;
      final index = sameDay ? occurred.hour : date.difference(start).inDays;
      if (index < 0 || index >= points.length) continue;
      final amount = _cnyAmount(transaction);
      if (amount == null) continue;
      if (transaction.type == TransactionType.expense) {
        expenses[index] += amount;
      }
      if (transaction.type == TransactionType.income) {
        incomes[index] += amount;
      }
    }
    return [
      for (var index = 0; index < points.length; index += 1)
        PeriodPoint(
          bucket: points[index].bucket,
          label: points[index].label,
          expense: _round(expenses[index]),
          income: _round(incomes[index]),
        )
    ];
  }

  static Map<String, double> expenseByCategory(
      FinanceState state, DateTimeRange range) {
    final start =
        DateTime(range.start.year, range.start.month, range.start.day);
    final end = DateTime(range.end.year, range.end.month, range.end.day);
    final totals = <String, double>{};
    for (final transaction in state.transactions.where((item) =>
        item.deletedAt == null && item.type == TransactionType.expense)) {
      final occurred = _occurredDate(transaction);
      final amount = _cnyAmount(transaction);
      if (occurred == null || amount == null) continue;
      final date = DateTime(occurred.year, occurred.month, occurred.day);
      if (date.isBefore(start) || date.isAfter(end)) continue;
      final key = transaction.categoryId ?? 'uncategorized';
      totals[key] = (totals[key] ?? 0) + amount;
    }
    return totals.map((key, value) => MapEntry(key, _round(value)));
  }

  static Map<String, double> expenseByAccount(
      FinanceState state, DateTimeRange range) {
    final start =
        DateTime(range.start.year, range.start.month, range.start.day);
    final end = DateTime(range.end.year, range.end.month, range.end.day);
    final totals = <String, double>{};
    for (final transaction in state.transactions.where((item) =>
        item.deletedAt == null && item.type == TransactionType.expense)) {
      final occurred = _occurredDate(transaction);
      final amount = _cnyAmount(transaction);
      if (occurred == null || amount == null) continue;
      final date = DateTime(occurred.year, occurred.month, occurred.day);
      if (date.isBefore(start) || date.isAfter(end)) continue;
      final key = transaction.accountId ?? 'unknown';
      totals[key] = (totals[key] ?? 0) + amount;
    }
    return totals.map((key, value) => MapEntry(key, _round(value)));
  }

  static FinanceMetrics deriveMetrics(FinanceState state, String monthKey) {
    final visibleTransactions =
        state.transactions.where((item) => item.deletedAt == null).toList();
    final monthTransactions = visibleTransactions
        .where((item) => item.date.startsWith(monthKey))
        .toList();
    final pendingConversionCount = monthTransactions
        .where((item) => _cnyAmount(item) == null && item.currency != 'CNY')
        .length;
    final income = _round(monthTransactions
        .where((item) => item.type == TransactionType.income)
        .fold<double>(0, (sum, item) => sum + (_cnyAmount(item) ?? 0)));
    final expense = _round(monthTransactions
        .where((item) => item.type == TransactionType.expense)
        .fold<double>(0, (sum, item) => sum + (_cnyAmount(item) ?? 0)));
    final savings = _round(income - expense);
    final savingsRate = income == 0 ? 0.0 : _round(savings / income, 3);
    final accountBalances =
        AssetRules.accountBalances(state, visibleTransactions);
    final assetTotal = _round(accountBalances
        .where((item) => item.account.type == AccountType.asset)
        .fold<double>(0, (sum, item) => sum + item.balance));
    final liabilityTotal = _round(accountBalances
        .where((item) => item.account.type == AccountType.liability)
        .fold<double>(0, (sum, item) => sum + item.balance));
    final netWorth = _round(assetTotal - liabilityTotal);
    final budgetProgress = budget_rules.progressForMonth(state, monthKey);
    final goal = state.goals.isEmpty ? null : state.goals.first;
    final liquidAssets = accountBalances.where((item) {
      if (item.account.type != AccountType.asset || !item.account.isLiquid) {
        return false;
      }
      return goal == null ||
          goal.liquidAccountIds.isEmpty ||
          goal.liquidAccountIds.contains(item.account.id);
    }).toList();
    final selectedGoalIds = goal?.liquidAccountIds ?? const <String>[];
    final invalidGoalSelection = selectedGoalIds.any((id) => state.accounts.any(
        (account) =>
            account.id == id && account.type == AccountType.liability));
    final emergencyFund =
        _round(liquidAssets.fold<double>(0, (sum, item) => sum + item.balance));
    final goalProgress = goal == null || goal.target <= 0
        ? 0.0
        : (emergencyFund / goal.target).clamp(0, 1).toDouble();
    final remainingMonths =
        goal != null && savings > 0 && emergencyFund < goal.target
            ? ((goal.target - emergencyFund) / savings).ceil()
            : 0;

    return FinanceMetrics(
      monthKey: monthKey,
      income: income,
      expense: expense,
      savings: savings,
      savingsRate: savingsRate,
      accountBalances: accountBalances,
      assetTotal: assetTotal,
      liabilityTotal: liabilityTotal,
      netWorth: netWorth,
      budgetProgress: budgetProgress,
      emergencyFund: emergencyFund,
      goalProgress: goalProgress,
      remainingMonths: remainingMonths,
      emergencyFundError: invalidGoalSelection ? '应急金账户必须是资产账户' : null,
      pendingConversionCount: pendingConversionCount,
    );
  }

  static double? _cnyAmount(FinanceTransaction transaction) {
    if (transaction.currency == 'CNY') {
      return transaction.cnyAmount ?? transaction.amount;
    }
    return transaction.cnyAmount;
  }

  static DateTime? _occurredDate(FinanceTransaction transaction) {
    final raw = transaction.occurredAt ?? transaction.date;
    if (raw.length >= 19 && raw[10] == 'T') {
      return DateTime.tryParse(raw.substring(0, 19));
    }
    return DateTime.tryParse(raw);
  }

  static double _round(double value, [int digits = 2]) {
    final factor = pow(10, digits).toDouble();
    return (value * factor).round() / factor;
  }
}
