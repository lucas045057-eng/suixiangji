import '../../../core/network/api_response.dart';
import '../../../core/network/api_session.dart';
import '../../../domain/models.dart';

class BudgetRemoteDataSource {
  BudgetRemoteDataSource({required this.api});

  final ApiSession api;

  Future<List<Budget>> fetchBudgets({String? month}) async {
    final json = await requestMapWithSession(
      api,
      'GET',
      month == null ? '/budgets' : '/budgets?month=$month',
    );
    return responseItems(json).map((item) => Budget.fromJson(item)).toList();
  }

  Future<Budget> createBudget(Budget budget) async {
    final json = await requestMapWithSession(
      api,
      'POST',
      '/budgets',
      body: budget.toJson(),
    );
    return Budget.fromJson(json);
  }

  Future<Budget> updateBudget(
      String budgetId, Map<String, Object?> changes) async {
    final json = await requestMapWithSession(
      api,
      'PATCH',
      '/budgets/$budgetId',
      body: changes,
    );
    return Budget.fromJson(json);
  }

  Future<void> deleteBudget(String budgetId) async {
    await requestMapWithSession(api, 'DELETE', '/budgets/$budgetId');
  }
}
