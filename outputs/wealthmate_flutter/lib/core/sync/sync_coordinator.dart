import '../../data/api_client.dart';
import '../../data/sync_queue.dart';
import '../../domain/models.dart';
import '../database/local_state_session.dart';

/// Owns the existing push/pull orchestration while leaving the sync protocol
/// and conflict semantics unchanged.
class SyncCoordinator {
  SyncCoordinator({
    required this.session,
    required this.api,
    required this.isLocalOwnerBound,
  });

  final LocalStateSession session;
  final ApiClient? api;
  final bool Function() isLocalOwnerBound;
  final Set<String> _pendingConflictClientOpIds = <String>{};

  SyncQueue get queue => session.queue;

  void clearConflictState() => _pendingConflictClientOpIds.clear();

  Future<FinanceState> sync(FinanceState state,
      {bool Function()? isCurrent}) async {
    final pushed = await pushPending(state);
    if (isCurrent != null && !isCurrent()) return pushed;
    return pullChanges(pushed);
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
        if (!conflicts.contains('transactions:${remote.id}')) {
          conflicts.add('transactions:${remote.id}');
        }
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
    if (api == null) {
      return state.copyWith(syncState: const SyncState(error: '离线演示/待配置'));
    }
    if (!isLocalOwnerBound()) {
      return state.copyWith(
          syncState: const SyncState(error: '当前用户身份尚未确认，暂不上传本地数据'));
    }
    if ((await session.pendingOperations()).isEmpty) {
      return state.copyWith(
        syncState: state.syncState.copyWith(
          isSyncing: false,
          error: null,
        ),
      );
    }
    try {
      final operations = await session.pendingOperations();
      final result = await api!.push(operations);
      final accepted =
          ((result['accepted'] as List<Object?>?) ?? const <Object?>[])
              .map((item) => (item! as Map).cast<String, Object?>())
              .toList();
      final acceptedByOperation = <String, Map<String, Object?>>{
        for (final item in accepted) item['client_op_id']! as String: item,
      };
      final acceptedClientOpIds = <String>{};
      for (final operation in operations) {
        final receipt = acceptedByOperation[operation.clientOpId];
        if (receipt != null) {
          acceptedClientOpIds.add(operation.clientOpId);
        }
      }
      await session.mutateQueue((pending) {
        for (final clientOpId in acceptedClientOpIds) {
          pending.complete(clientOpId);
        }
      });
      final conflictItems =
          ((result['conflicts'] as List<Object?>?) ?? const <Object?>[])
              .map((item) => (item! as Map).cast<String, Object?>())
              .toList();
      _pendingConflictClientOpIds
        ..clear()
        ..addAll(conflictItems
            .map((item) => item['client_op_id'])
            .whereType<String>());
      final nextState = await session.write((current) {
        final base = _mergeCurrentWithRequested(current, state);
        final nextTransactions = [...base.transactions];
        final nextAccounts = [...base.accounts];
        final nextBudgets = [...base.budgets];
        for (final operation in operations) {
          final receipt = acceptedByOperation[operation.clientOpId];
          final serverVersion = (receipt?['server_version'] as num?)?.toInt();
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
              final currentBudget = nextBudgets[index];
              nextBudgets[index] = Budget(
                id: currentBudget.id,
                month: currentBudget.month,
                categoryId: currentBudget.categoryId,
                limit: currentBudget.limit,
                active: currentBudget.active,
                serverVersion: serverVersion,
                updatedAt: currentBudget.updatedAt,
                deletedAt: currentBudget.deletedAt,
              );
            }
          }
        }
        final conflicts =
            conflictItems.map((item) => 'sync:${item['entity_id']}').toList();
        return current.copyWith(
            transactions: nextTransactions,
            accounts: nextAccounts,
            budgets: nextBudgets,
            conflicts: [
              ...base.conflicts,
              for (final conflict in conflicts)
                if (!base.conflicts.contains(conflict)) conflict,
            ],
            syncState: SyncState(
                serverVersion: (result['server_version'] as num?)?.toInt() ??
                    base.syncState.serverVersion,
                lastSyncedAt: DateTime.now().toIso8601String()));
      }, initialState: state);
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
    if (api == null) {
      return state.copyWith(syncState: const SyncState(error: '离线演示/待配置'));
    }
    if (!isLocalOwnerBound()) {
      return state.copyWith(
          syncState: const SyncState(error: '当前用户身份尚未确认，暂不下载本地数据'));
    }
    try {
      final conflictOperations = _pendingConflictOperations(state);
      final pullSince = conflictOperations.isEmpty
          ? state.syncState.serverVersion
          : _minimumConflictBaseVersion(
              conflictOperations, state.syncState.serverVersion);
      final remote = await api!.pullChanges(pullSince);
      if (conflictOperations.isNotEmpty) {
        return await _completeConflictRecovery(
            state, remote, conflictOperations);
      }
      final next = await session.write((current) {
        final base = _mergeCurrentWithRequested(current, state);
        final freshBootstrap = _isFreshBootstrap(base);
        var nextState = freshBootstrap
            ? base.copyWith(
                transactions: remote.transactions,
                accounts: remote.accounts,
                categories: remote.categories,
                budgets: remote.budgets,
              )
            : mergePulledBudgets(
                mergePulledCategories(
                    mergePulledAccounts(mergePulled(base, remote.transactions),
                        remote.accounts),
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
          if (defaultAccount != null) {
            nextState = nextState.copyWith(defaultAccountId: defaultAccount.id);
          }
        }
        return nextState.copyWith(
            syncState: SyncState(
          serverVersion: remote.serverVersion,
          lastSyncedAt: DateTime.now().toIso8601String(),
        ));
      }, initialState: state);
      return next;
    } on ApiFailure catch (failure) {
      return state.copyWith(
          syncState: state.syncState.copyWith(error: failure.message));
    }
  }

  List<SyncOperation> _pendingConflictOperations(FinanceState state) {
    final queued = queue.pending();
    if (_pendingConflictClientOpIds.isNotEmpty) {
      final byOperation = queued
          .where((operation) =>
              _pendingConflictClientOpIds.contains(operation.clientOpId))
          .toList(growable: false);
      if (byOperation.isNotEmpty) return byOperation;
    }
    final entityIds = state.conflicts
        .where((item) => item.startsWith('sync:'))
        .map((item) => item.substring('sync:'.length))
        .toSet();
    return queued
        .where((operation) => entityIds.contains(operation.entityId))
        .toList(growable: false);
  }

  int _minimumConflictBaseVersion(
      List<SyncOperation> operations, int fallback) {
    final versions = operations
        .map((operation) => operation.payload['server_version'])
        .whereType<num>()
        .map((value) => value.toInt())
        .toList(growable: false);
    if (versions.isEmpty) return fallback;
    return versions.reduce((a, b) => a < b ? a : b);
  }

  Future<FinanceState> _completeConflictRecovery(FinanceState state,
      PullResult remote, List<SyncOperation> conflictOperations) async {
    bool hasAuthoritativeEntity(SyncOperation operation) {
      switch (operation.entity) {
        case 'transactions':
          return remote.transactions
              .any((item) => item.id == operation.entityId);
        case 'accounts':
          return remote.accounts.any((item) => item.id == operation.entityId);
        case 'categories':
          return remote.categories.any((item) => item.id == operation.entityId);
        case 'budgets':
          return remote.budgets.any((item) => item.id == operation.entityId);
        default:
          return false;
      }
    }

    if (conflictOperations
        .any((operation) => !hasAuthoritativeEntity(operation))) {
      final current = await session.load() ?? state;
      return current.copyWith(
          syncState: current.syncState.copyWith(error: '冲突数据尚未恢复，请稍后重试'));
    }

    final resolvedEntityIds = <String>{
      for (final operation in conflictOperations) operation.entityId,
    };
    await session.mutateQueue((pending) {
      for (final operation in conflictOperations) {
        pending.complete(operation.clientOpId);
        _pendingConflictClientOpIds.remove(operation.clientOpId);
      }
    });
    final nextState = await session.write((current) {
      final merged = mergePulledBudgets(
          mergePulledCategories(
              mergePulledAccounts(
                  mergePulled(current, remote.transactions), remote.accounts),
              remote.categories),
          remote.budgets);
      final remainingConflicts = current.conflicts.where((conflict) {
        if (conflict.startsWith('sync:')) {
          return !resolvedEntityIds
              .contains(conflict.substring('sync:'.length));
        }
        if (conflict.startsWith('transactions:')) {
          return !resolvedEntityIds
              .contains(conflict.substring('transactions:'.length));
        }
        return true;
      }).toList(growable: false);
      final nextVersion = current.syncState.serverVersion > remote.serverVersion
          ? current.syncState.serverVersion
          : remote.serverVersion;
      return merged.copyWith(
          conflicts: remainingConflicts,
          syncState: SyncState(
            serverVersion: nextVersion,
            lastSyncedAt: DateTime.now().toIso8601String(),
          ));
    }, initialState: state);
    return nextState;
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

  FinanceState _mergeCurrentWithRequested(
      FinanceState current, FinanceState requested) {
    return current.copyWith(
      currentMonth: current.currentMonth.isEmpty
          ? requested.currentMonth
          : current.currentMonth,
      accounts: _appendMissingById(current.accounts, requested.accounts,
          (item) => item.id),
      categories: _appendMissingById(current.categories, requested.categories,
          (item) => item.id),
      transactions: _appendMissingById(
          current.transactions, requested.transactions, (item) => item.id),
      budgets: _appendMissingById(
          current.budgets, requested.budgets, (item) => item.id),
      exchangeRates: _appendMissingById(
          current.exchangeRates,
          requested.exchangeRates,
          (item) => '${item.baseCurrency}:${item.quoteCurrency}'),
      goals: _appendMissingById(current.goals, requested.goals, (item) => item.id),
      reports: _appendMissingById(
          current.reports, requested.reports, (item) => item.id),
      conflicts: [
        ...current.conflicts,
        for (final conflict in requested.conflicts)
          if (!current.conflicts.contains(conflict)) conflict,
      ],
      quickMemories: _appendMissingById(
          current.quickMemories, requested.quickMemories, (item) => item.key),
      defaultAccountId: current.defaultAccountId ?? requested.defaultAccountId,
      syncState: current.syncState.serverVersion == 0
          ? requested.syncState
          : current.syncState,
    );
  }

  List<T> _appendMissingById<T>(
      List<T> current, List<T> requested, String Function(T item) id) {
    final merged = [...current];
    for (final item in requested) {
      if (!merged.any((existing) => id(existing) == id(item))) {
        merged.add(item);
      }
    }
    return merged;
  }
}
