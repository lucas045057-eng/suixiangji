import '../../../data/api_client.dart';
import '../../../domain/models.dart';

class LedgerRemoteDataSource {
  LedgerRemoteDataSource({required this.api});

  final ApiClient api;

  Future<List<Category>> fetchCategories() => api.fetchCategories();

  Future<Category> createCategory(
          {required String name, required TransactionType type}) =>
      api.createCategory(name: name, type: type);

  Future<Category> updateCategory(String categoryId,
          {required String name, required bool active}) =>
      api.updateCategory(categoryId, name: name, active: active);

  Future<List<FinanceTransaction>> fetchTransactions() =>
      api.fetchTransactions();
}
