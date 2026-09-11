import '../../../domain/models.dart';

/// Pure transaction and category decisions for the Ledger feature.
class LedgerRules {
  static FinanceState upsertTransaction(
      FinanceState state, FinanceTransaction transaction) {
    return state.copyWith(transactions: [
      ...state.transactions.where((item) => item.id != transaction.id),
      transaction,
    ]);
  }

  static FinanceState softDeleteTransaction(
      FinanceState state, String transactionId, String deletedAt) {
    return state.copyWith(
        transactions: state.transactions
            .map((item) => item.id == transactionId
                ? item.copyWith(deletedAt: deletedAt)
                : item)
            .toList());
  }

  static FinanceState upsertCategory(FinanceState state, Category category) {
    return state.copyWith(categories: [
      ...state.categories.where((item) => item.id != category.id),
      category,
    ]);
  }

  static List<Category> activeCategories(FinanceState state) => state.categories
      .where((item) => item.active)
      .toList(growable: false);
}
