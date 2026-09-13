import '../../../core/network/api_response.dart';
import '../../../core/network/api_session.dart';
import '../../../domain/models.dart';

class LedgerRemoteDataSource {
  LedgerRemoteDataSource({required this.api});

  final ApiSession api;

  Future<List<Category>> fetchCategories() async {
    final json = await requestMapWithSession(api, 'GET', '/categories');
    return responseItems(json).map((item) => Category.fromJson(item)).toList();
  }

  Future<Category> createCategory(
      {required String name, required TransactionType type}) async {
    final json = await requestMapWithSession(
      api,
      'POST',
      '/categories',
      body: {'name': name, 'kind': transactionTypeToJson(type)},
    );
    return Category.fromJson(json);
  }

  Future<Category> updateCategory(
    String categoryId, {
    required String name,
    required bool active,
  }) async {
    final json = await requestMapWithSession(
      api,
      'PATCH',
      '/categories/$categoryId',
      body: {'name': name, 'active': active},
    );
    return Category.fromJson(json);
  }

  Future<List<FinanceTransaction>> fetchTransactions() async {
    final json = await requestMapWithSession(api, 'GET', '/transactions');
    return responseItems(json)
        .map((item) => FinanceTransaction.fromJson(item))
        .toList();
  }
}
