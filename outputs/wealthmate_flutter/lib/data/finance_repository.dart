import 'api_client.dart';
import 'local_repository.dart';
import 'sync_queue.dart';
import '../domain/models.dart';

class FinanceRepository {
  FinanceRepository({required this.local, required this.queue, this.api});

  final LocalRepository local;
  final SyncQueue queue;
  final ApiClient? api;
  String? _localOwnerUserId;

  String? get localOwnerUserId => _localOwnerUserId;

  bool get isLocalOwnerBound => _localOwnerUserId != null;

  Future<FinanceState?> loadForUser(String userId) async {
    await ensureLocalOwner(userId);
    return load();
  }

  Future<void> ensureLocalOwner(String userId) async {
    final normalizedUserId = userId.trim();
    if (normalizedUserId.isEmpty) {
      throw ArgumentError.value(userId, 'userId', '用户身份不能为空');
    }
    final storedOwner = await local.loadOwnerUserId();
    if (storedOwner != normalizedUserId) {
      await local.clearFinanceStateAndQueue();
      queue.replace(const []);
    }
    await local.saveOwnerUserId(normalizedUserId);
    _localOwnerUserId = normalizedUserId;
  }

  void unbindLocalOwner() {
    _localOwnerUserId = null;
  }

  Future<bool> restoreLocalOwnerForVerifiedSession() async {
    if (api == null || api!.token == null || api!.token!.trim().isEmpty) {
      return false;
    }
    final verifiedUserId = api!.lastVerifiedUserId?.trim();
    if (verifiedUserId == null || verifiedUserId.isEmpty) return false;
    final storedOwner = await local.loadOwnerUserId();
    if (storedOwner == null || storedOwner != verifiedUserId) return false;
    _localOwnerUserId = storedOwner;
    return true;
  }

  Future<FinanceState?> load() async {
    if (api != null && !isLocalOwnerBound) {
      final restored = await restoreLocalOwnerForVerifiedSession();
      if (!restored) {
        queue.replace(const []);
        return null;
      }
    }
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
    if (!isLocalOwnerBound) {
      return state.copyWith(
          syncState: const SyncState(error: '当前用户身份尚未确认，暂不上传本地数据'));
    }
    if (queue.pending().isEmpty) {
      return state.copyWith(
        syncState: state.syncState.copyWith(
          isSyncing: false,
          error: null,
        ),
      );
    }
    try {
      final operations = queue.pending();
      final result = await api!.push(operations);
      final accepted =
          ((result['accepted'] as List<Object?>?) ?? const <Object?>[])
              .map((item) => (item! as Map).cast<String, Object?>())
              .toList();
      final acceptedByOperation = <String, Map<String, Object?>>{
        for (final item in accepted) item['client_op_id']! as String: item,
      };
      final nextTransactions = [...state.transactions];
      final nextAccounts = [...state.accounts];
      final nextBudgets = [...state.budgets];
      for (final operation in operations) {
        final receipt = acceptedByOperation[operation.clientOpId];
        if (receipt != null) {
          queue.complete(operation.clientOpId);
          final serverVersion = (receipt['server_version'] as num?)?.toInt();
          if (serverVersion == null) continue;
          if (operation.entity == 'transactions') {
            final index = nextTransactions
                .indexWhere((item) => item.id == operation.entityId);
            if (index >= 0 &&
                (nextTransactions[index].serverVersion == null ||
                    serverVersion >= nextTransactions[index].serverVersion!)) {
              nextTransactions[index] = nextTransactions[index]
                  .copyWith(serverVersion: serverVersion);
            }
          } else if (operation.entity == 'accounts') {
            final index = nextAccounts
                .indexWhere((item) => item.id == operation.entityId);
            if (index >= 0 &&
                (nextAccounts[index].serverVersion == null ||
                    serverVersion >= nextAccounts[index].serverVersion!)) {
              nextAccounts[index] =
                  nextAccounts[index].copyWith(serverVersion: serverVersion);
            }
          } else if (operation.entity == 'budgets') {
            final index =
                nextBudgets.indexWhere((item) => item.id == operation.entityId);
            if (index >= 0 &&
                (nextBudgets[index].serverVersion == null ||
                    serverVersion >= nextBudgets[index].serverVersion!)) {
              final current = nextBudgets[index];
              nextBudgets[index] = Budget(
                id: current.id,
                month: current.month,
                categoryId: current.categoryId,
                limit: current.limit,
                active: current.active,
                serverVersion: serverVersion,
                updatedAt: current.updatedAt,
                deletedAt: current.deletedAt,
              );
            }
          }
        }
      }
      await persistQueue();
      final conflicts =
          ((result['conflicts'] as List<Object?>?) ?? const <Object?>[])
              .map((item) => 'sync:${(item! as Map)['entity_id']}')
              .toList();
      final nextState = state.copyWith(
          transactions: nextTransactions,
          accounts: nextAccounts,
          budgets: nextBudgets,
          conflicts: [...state.conflicts, ...conflicts],
          syncState: SyncState(
              serverVersion: (result['server_version'] as num?)?.toInt() ??
                  state.syncState.serverVersion,
              lastSyncedAt: DateTime.now().toIso8601String()));
      await local.save(nextState);
      return nextState;
    } on ApiFailure catch (failure) {
      return state.copyWith(
        syncState: state.syncState.copyWith(
          isSyncing: false,
          error: failure.message,
        ),
      );
    }
  }

  Future<FinanceState> pullChanges(FinanceState state) async {
    if (api == null)
      return state.copyWith(syncState: const SyncState(error: '离线演示/待配置'));
    if (!isLocalOwnerBound) {
      return state.copyWith(
          syncState: const SyncState(error: '当前用户身份尚未确认，暂不下载本地数据'));
    }
    try {
      final remote = await api!.pullChanges(state.syncState.serverVersion);
      final freshBootstrap = _isFreshBootstrap(state);
      var nextState = freshBootstrap
          ? state.copyWith(
              transactions: remote.transactions,
              accounts: remote.accounts,
              categories: remote.categories,
              budgets: remote.budgets,
            )
          : mergePulledBudgets(
              mergePulledCategories(
                  mergePulledAccounts(
                      mergePulled(state, remote.transactions), remote.accounts),
                  remote.categories),
              remote.budgets);
      if (freshBootstrap) {
        final activeAccounts = nextState.accounts
            .where((item) => item.deletedAt == null)
            .toList(growable: false);
        final preferredAccounts = activeAccounts
            .where((item) => item.isDefaultPayment)
            .toList(growable: false);
        final defaultAccount = preferredAccounts.length == 1
            ? preferredAccounts.single
            : activeAccounts.length == 1
                ? activeAccounts.single
                : null;
        if (defaultAccount != null)
          nextState = nextState.copyWith(defaultAccountId: defaultAccount.id);
      }
      final next = nextState.copyWith(
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

  bool _isFreshBootstrap(FinanceState state) {
    return state.syncState.serverVersion == 0 &&
        state.defaultAccountId == null &&
        state.accounts.isEmpty &&
        state.categories.isEmpty &&
        state.transactions.isEmpty &&
        state.budgets.isEmpty &&
        state.exchangeRates.isEmpty &&
        state.goals.isEmpty &&
        state.reports.isEmpty &&
        state.conflicts.isEmpty &&
        state.quickMemories.isEmpty &&
        queue.pending().isEmpty;
  }
}
