import '../network/api_response.dart';
import '../network/api_session.dart';
import '../../data/sync_queue.dart';
import '../../domain/models.dart';

class SyncRemoteDataSource {
  SyncRemoteDataSource({required this.api});

  final ApiSession api;

  Future<Map<String, Object?>> push(List<SyncOperation> operations) {
    return requestMapWithSession(
      api,
      'POST',
      '/sync/push',
      body: {
        'operations': operations.map((item) => item.toJson()).toList(),
      },
    );
  }

  Future<PullResult> pullChanges(int sinceVersion) async {
    final json = await requestMapWithSession(
      api,
      'GET',
      '/sync/pull?since_version=$sinceVersion',
    );
    final transactionItems = responseItems(json);
    final accountItems = _mapItems(json['accounts']);
    final categoryItems = _mapItems(json['categories']);
    final budgetItems = _mapItems(json['budgets']);
    return PullResult(
      transactions: transactionItems
          .map((item) => FinanceTransaction.fromJson(item))
          .toList(),
      accounts: accountItems.map((item) => Account.fromJson(item)).toList(),
      categories: categoryItems.map((item) => Category.fromJson(item)).toList(),
      budgets: budgetItems.map((item) => Budget.fromJson(item)).toList(),
      serverVersion: (json['server_version'] as num?)?.toInt() ?? sinceVersion,
    );
  }

  List<Map<String, Object?>> _mapItems(Object? value) {
    return ((value as List<Object?>?) ?? const <Object?>[])
        .map((item) => (item! as Map).cast<String, Object?>())
        .toList();
  }
}

class PullResult {
  const PullResult({
    required this.transactions,
    required this.accounts,
    this.categories = const [],
    this.budgets = const [],
    required this.serverVersion,
  });

  final List<FinanceTransaction> transactions;
  final List<Account> accounts;
  final List<Category> categories;
  final List<Budget> budgets;
  final int serverVersion;
}
