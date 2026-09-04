import 'api_client.dart';
import 'local_repository.dart';
import 'sync_queue.dart';
import '../domain/models.dart';

class FinanceRepository {
  FinanceRepository({required this.local, required this.queue, this.api});

  final LocalRepository local;
  final SyncQueue queue;
  final ApiClient? api;

  Future<FinanceState?> load() async {
    queue.replace(await local.loadQueue());
    return local.load();
  }

  Future<void> save(FinanceState state) => local.save(state);

  Future<void> persistQueue() => local.saveQueue(queue);

  Future<FinanceState> applyLocal(
      FinanceState state, FinanceTransaction transaction) async {
    final next =
        state.copyWith(transactions: [...state.transactions, transaction]);
    queue.enqueue(SyncOperation(
      clientOpId: transaction.clientOpId,
      entity: 'transactions',
      entityId: transaction.id,
      type: SyncOperationType.upsert,
      payload: transaction.toJson(),
      createdAt: DateTime.now().toIso8601String(),
    ));
    await local.save(next);
    await persistQueue();
    return next;
  }

  Future<FinanceState> applyLocalAccount(
      FinanceState state, Account account) async {
    final next = state.copyWith(accounts: [
      ...state.accounts.where((item) => item.id != account.id),
      account
    ]);
    queue.enqueue(SyncOperation(
      clientOpId:
          'account:${account.id}:${DateTime.now().microsecondsSinceEpoch}',
      entity: 'accounts',
      entityId: account.id,
      type: SyncOperationType.upsert,
      payload: account.toJson(),
      createdAt: DateTime.now().toIso8601String(),
    ));
    await local.save(next);
    await persistQueue();
    return next;
  }

  Future<FinanceState> applyLocalCategory(
      FinanceState state, Category category) async {
    final next = state.copyWith(categories: [
      ...state.categories.where((item) => item.id != category.id),
      category
    ]);
    queue.enqueue(SyncOperation(
      clientOpId:
          'category:${category.id}:${DateTime.now().microsecondsSinceEpoch}',
      entity: 'categories',
      entityId: category.id,
      type: SyncOperationType.upsert,
      payload: category.toJson(),
      createdAt: DateTime.now().toIso8601String(),
    ));
    await local.save(next);
    await persistQueue();
    return next;
  }

  Future<FinanceState> softDelete(
      FinanceState state, String transactionId) async {
    final now = DateTime.now().toIso8601String();
    final nextTransactions = state.transactions.map((item) {
      return item.id == transactionId ? item.copyWith(deletedAt: now) : item;
    }).toList();
    final deleted =
        nextTransactions.firstWhere((item) => item.id == transactionId);
    final next = state.copyWith(transactions: nextTransactions);
    queue.enqueue(SyncOperation(
      clientOpId: '${deleted.clientOpId}:delete',
      entity: 'transactions',
      entityId: transactionId,
      type: SyncOperationType.delete,
      payload: deleted.toJson(),
      createdAt: now,
    ));
    await local.save(next);
    await persistQueue();
    return next;
  }

  FinanceState mergePulled(
      FinanceState localState, List<FinanceTransaction> remoteTransactions) {
    final merged = [...localState.transactions];
    final conflicts = [...localState.conflicts];
    for (final remote in remoteTransactions) {
      final index = merged.indexWhere((item) => item.id == remote.id);
      if (index < 0) {
        merged.add(remote);
        continue;
      }
      final localItem = merged[index];
      if (remote.serverVersion != null &&
          localItem.serverVersion != null &&
          remote.serverVersion! < localItem.serverVersion!) {
        if (!conflicts.contains('transactions:${remote.id}'))
          conflicts.add('transactions:${remote.id}');
        continue;
      }
      merged[index] = remote;
    }
    return localState.copyWith(transactions: merged, conflicts: conflicts);
  }

  FinanceState mergePulledAccounts(
      FinanceState localState, List<Account> remoteAccounts) {
    final merged = [...localState.accounts];
    for (final remote in remoteAccounts) {
      final index = merged.indexWhere((item) => item.id == remote.id);
      if (index < 0) {
        merged.add(remote);
      } else if (remote.serverVersion == null ||
          merged[index].serverVersion == null ||
          remote.serverVersion! >= merged[index].serverVersion!) {
        merged[index] = remote;
      }
    }
    return localState.copyWith(accounts: merged);
  }

  FinanceState mergePulledCategories(
      FinanceState localState, List<Category> remoteCategories) {
    final merged = [...localState.categories];
    for (final remote in remoteCategories) {
      final index = merged.indexWhere((item) => item.id == remote.id);
      if (index < 0) {
        merged.add(remote);
      } else {
        merged[index] = remote;
      }
    }
    return localState.copyWith(categories: merged);
  }

  FinanceState mergePulledBudgets(
      FinanceState localState, List<Budget> remoteBudgets) {
    final merged = [...localState.budgets];
    for (final remote in remoteBudgets) {
      final index = merged.indexWhere((item) => item.id == remote.id);
      if (index < 0) {
        merged.add(remote);
      } else {
        merged[index] = remote;
      }
    }
    return localState.copyWith(budgets: merged);
  }

  Future<FinanceState> pushPending(FinanceState state) async {
    if (api == null)
      return state.copyWith(syncState: const SyncState(error: '离线演示/待配置'));
    if (queue.pending().isEmpty)
      return state.copyWith(syncState: const SyncState(error: null));
    try {
      final operations = queue.pending();
      final result = await api!.push(operations);
      final accepted =
          ((result['accepted'] as List<Object?>?) ?? const <Object?>[])
              .map((item) => ((item! as Map)['client_op_id']) as String)
              .toSet();
      for (final operation in operations) {
        if (accepted.contains(operation.clientOpId))
          queue.complete(operation.clientOpId);
      }
      await persistQueue();
      final conflicts =
          ((result['conflicts'] as List<Object?>?) ?? const <Object?>[])
              .map((item) => 'sync:${(item! as Map)['entity_id']}')
              .toList();
      return state.copyWith(
          conflicts: [...state.conflicts, ...conflicts],
          syncState: SyncState(
              serverVersion: (result['server_version'] as num?)?.toInt() ??
                  state.syncState.serverVersion,
              lastSyncedAt: DateTime.now().toIso8601String()));
    } on ApiFailure catch (failure) {
      return state.copyWith(syncState: SyncState(error: failure.message));
    }
  }

  Future<FinanceState> pullChanges(FinanceState state) async {
    if (api == null)
      return state.copyWith(syncState: const SyncState(error: '离线演示/待配置'));
    try {
      final remote = await api!.pullChanges(state.syncState.serverVersion);
      final merged = mergePulledBudgets(
          mergePulledCategories(
              mergePulledAccounts(
                  mergePulled(state, remote.transactions), remote.accounts),
              remote.categories),
          remote.budgets);
      final next = merged.copyWith(
          syncState: SyncState(
        serverVersion: remote.serverVersion,
        lastSyncedAt: DateTime.now().toIso8601String(),
      ));
      await local.save(next);
      return next;
    } on ApiFailure catch (failure) {
      return state.copyWith(syncState: SyncState(error: failure.message));
    }
  }
}
