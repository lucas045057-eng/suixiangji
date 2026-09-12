import '../../../domain/models.dart';

BudgetAlertLevel? levelForRatio(double ratio) {
  if (ratio > 1) return BudgetAlertLevel.over;
  if (ratio >= 1) return BudgetAlertLevel.exhausted;
  if (ratio >= .8) return BudgetAlertLevel.warning;
  return null;
}

BudgetProgress progressFor(Budget budget, double spent) {
  final ratio = budget.limit <= 0 ? 0.0 : spent / budget.limit;
  final status = ratio >= 1
      ? BudgetStatus.over
      : ratio >= .8
          ? BudgetStatus.warning
          : BudgetStatus.healthy;
  return BudgetProgress(budget: budget, spent: spent, status: status);
}

List<BudgetProgress> progressForMonth(FinanceState state, String month) {
  final transactions = state.transactions.where((item) =>
      item.deletedAt == null &&
      item.type == TransactionType.expense &&
      item.date.startsWith(month));
  return state.budgets
      .where((budget) =>
          budget.deletedAt == null && budget.active && budget.month == month)
      .map((budget) {
    final spent = transactions
        .where((item) => item.categoryId == budget.categoryId)
        .fold<double>(0, (sum, item) => sum + _cnyAmount(item));
    return progressFor(budget, _round(spent));
  }).toList(growable: false);
}

double _cnyAmount(FinanceTransaction transaction) {
  if (transaction.currency == 'CNY') {
    return transaction.cnyAmount ?? transaction.amount;
  }
  return transaction.cnyAmount ?? 0;
}

double _round(double value) => (value * 100).round() / 100;
