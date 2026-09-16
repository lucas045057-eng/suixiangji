import '../../../domain/models.dart';

/// Pure transaction and category decisions for the Ledger feature.
class LedgerRules {
  static FinanceState upsertTransaction(
      FinanceState state, FinanceTransaction transaction) {
    validateTransactionCategory(state, transaction);
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

  static List<Category> activeCategories(FinanceState state) =>
      state.categories.where((item) => item.active).toList(growable: false);

  static List<Category> categoryCandidates(
    FinanceState state,
    TransactionType type, {
    String? selectedCategoryId,
  }) {
    final candidates = state.categories
        .where((item) => item.active && item.type == type)
        .toList(growable: true);
    if (selectedCategoryId != null && selectedCategoryId.isNotEmpty) {
      final selected = state.categories
          .where((item) => item.id == selectedCategoryId && item.type == type)
          .firstOrNull;
      if (selected != null &&
          !candidates.any((item) => item.id == selected.id)) {
        candidates.insert(0, selected);
      }
    }
    return candidates.toList(growable: false);
  }

  static String defaultCategoryIdForType(
      FinanceState state, TransactionType type) {
    return state.categories
            .where((item) => item.active && item.type == type)
            .map((item) => item.id)
            .firstOrNull ??
        '';
  }

  static String validCategoryIdForType(
    FinanceState state,
    TransactionType type,
    String? categoryId,
  ) {
    if (categoryId != null && categoryId.isNotEmpty) {
      final matches = state.categories
          .any((item) => item.id == categoryId && item.type == type);
      if (matches) return categoryId;
    }
    return defaultCategoryIdForType(state, type);
  }

  static void validateTransactionCategory(
      FinanceState state, FinanceTransaction transaction) {
    final categoryId = transaction.categoryId;
    if (transaction.type == TransactionType.transfer ||
        categoryId == null ||
        categoryId.isEmpty) {
      return;
    }
    final category =
        state.categories.where((item) => item.id == categoryId).firstOrNull;
    if (category != null && category.type != transaction.type) {
      throw ArgumentError.value(categoryId, 'categoryId',
          'category type must match transaction type');
    }
  }
}
