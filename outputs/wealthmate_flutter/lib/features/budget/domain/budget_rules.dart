import '../../../domain/models.dart';
import '../../../domain/transaction_query.dart';

const totalBudgetCategory = '__total__';

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
  final first = DateTime.parse('$month-01');
  final transactions = TransactionQuery(
          start: first,
          end: DateTime(first.year, first.month + 1, 0),
          type: TransactionType.expense)
      .select(state);
  return state.budgets
      .where((budget) =>
          budget.deletedAt == null && budget.active && budget.month == month)
      .map((budget) {
    final spent = transactions
        .where((item) =>
            budget.categoryId == totalBudgetCategory ||
            item.categoryId == budget.categoryId)
        .fold<double>(0, (sum, item) => sum + (cnyAmount(item) ?? 0));
    return progressFor(budget, _round(spent));
  }).toList(growable: false);
}

double _round(double value) => (value * 100).round() / 100;
