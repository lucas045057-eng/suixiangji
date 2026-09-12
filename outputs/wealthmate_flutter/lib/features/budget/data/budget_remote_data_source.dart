import '../../../data/api_client.dart';
import '../../../domain/models.dart';

class BudgetRemoteDataSource {
  BudgetRemoteDataSource({required this.api});

  final ApiClient api;

  Future<List<Budget>> fetchBudgets({String? month}) =>
      api.fetchBudgets(month: month);

  Future<Budget> createBudget(Budget budget) => api.createBudget(budget);

  Future<Budget> updateBudget(String budgetId, Map<String, Object?> changes) =>
      api.updateBudget(budgetId, changes);

  Future<void> deleteBudget(String budgetId) => api.deleteBudget(budgetId);
}
