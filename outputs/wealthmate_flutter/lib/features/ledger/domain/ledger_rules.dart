import '../../../domain/models.dart';

/// Pure transaction and category decisions for the Ledger feature.
class LedgerRules {
  static FinanceTransaction prepareConversion(
      FinanceState state, FinanceTransaction transaction) {
    if (transaction.currency == 'CNY') {
      return transaction.copyWith(
          cnyAmount: transaction.cnyAmount ?? transaction.amount,
          exchangeRate: 1,
          conversionStatus: 'ready');
    }
    // A posted conversion is a historical snapshot, never a live quotation.
    if (transaction.cnyAmount != null) return transaction;
    final businessDate = DateTime.tryParse(transaction.date);
    final rates = state.exchangeRates.where((rate) {
      final rateDate = DateTime.tryParse(rate.rateDate);
      return rate.baseCurrency == transaction.currency &&
          rate.quoteCurrency == 'CNY' &&
          rate.rate.isFinite &&
          rate.rate > 0 &&
          businessDate != null &&
          rateDate != null &&
          !rateDate.isAfter(businessDate);
    }).toList()
      ..sort((a, b) => b.rateDate.compareTo(a.rateDate));
    if (rates.isEmpty) {
      return transaction.copyWith(conversionStatus: 'pending');
    }
    final snapshot = rates.first;
    return transaction.copyWith(
        cnyAmount:
            (transaction.amount * snapshot.rate * 100).roundToDouble() / 100,
        exchangeRate: snapshot.rate,
        exchangeRateDate: snapshot.rateDate,
        exchangeRateSource: snapshot.source,
        conversionStatus: 'ready');
  }

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
