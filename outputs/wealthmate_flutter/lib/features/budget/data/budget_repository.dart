import 'dart:convert';

import '../../../core/database/local_state_session.dart';
import '../../../core/network/api_session.dart';
import '../../../data/local_repository.dart';
import '../../../data/sync_queue.dart';
import '../../../domain/models.dart';
import 'budget_remote_data_source.dart';

class BudgetRepository {
  BudgetRepository({required this.session, this.remote});

  final LocalStateSession session;
  final BudgetRemoteDataSource? remote;

  ApiSession? get api => remote?.api;
  SyncQueue get queue => session.queue;

  Future<FinanceState?> load() => session.load();

  Future<FinanceState> saveBudget(Budget budget, {FinanceState? baseState}) {
    return session.write(
      (current) => current.copyWith(
        budgets: [
          ...current.budgets.where((item) => item.id != budget.id),
          budget,
        ],
      ),
      appendOperations: [
        SyncOperation(
          clientOpId:
              'budget:${budget.id}:${DateTime.now().microsecondsSinceEpoch}',
          entity: 'budgets',
          entityId: budget.id,
          type: SyncOperationType.upsert,
          payload: budget.toJson(),
          createdAt: DateTime.now().toIso8601String(),
        ),
      ],
      initialState: baseState,
    );
  }

  Future<List<Budget>> fetchBudgets({String? month}) => remote == null
      ? Future.value(const <Budget>[])
      : remote!.fetchBudgets(month: month);

  Future<Budget> createBudget(Budget budget) {
    if (remote == null) throw StateError('同步服务未配置');
    return remote!.createBudget(budget);
  }

  Future<Budget> updateBudget(String budgetId, Map<String, Object?> changes) {
    if (remote == null) throw StateError('同步服务未配置');
    return remote!.updateBudget(budgetId, changes);
  }

  Future<void> deleteBudget(String budgetId) {
    if (remote == null) throw StateError('同步服务未配置');
    return remote!.deleteBudget(budgetId);
  }

  Future<Set<String>> readAlertKeys() async {
    final raw =
        await session.local.readMetadata(LocalRepository.budgetAlertsKey);
    if (raw == null || raw.isEmpty) return <String>{};
    final decoded = jsonDecode(raw);
    return decoded is List ? decoded.whereType<String>().toSet() : <String>{};
  }

  Future<void> writeAlertKeys(Set<String> keys) => session.local.writeMetadata(
      LocalRepository.budgetAlertsKey, jsonEncode(keys.toList()));
}
