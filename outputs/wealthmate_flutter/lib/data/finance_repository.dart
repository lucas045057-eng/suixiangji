import '../core/database/local_state_session.dart';
import 'api_client.dart';
import 'local_repository.dart';
import 'sync_queue.dart';
import '../domain/models.dart';
import '../features/assets/data/assets_remote_data_source.dart';
import '../features/assets/data/assets_repository.dart';
import '../features/ledger/data/ledger_repository.dart';
import '../features/budget/data/budget_remote_data_source.dart';
import '../features/budget/data/budget_repository.dart';

class FinanceRepository {
  FinanceRepository({
    required LocalRepository local,
    required this.queue,
    LocalStateSession? session,
    AssetsRepository? assetsRepository,
    LedgerRepository? ledgerRepository,
    BudgetRepository? budgetRepository,
    this.api,
  })  : _local = local,
        session = session ?? LocalStateSession(local: local, queue: queue) {
    _assetsRepository = assetsRepository ??
        AssetsRepository(
          session: this.session,
          remote: api == null ? null : AssetsRemoteDataSource(api: api!),
        );
    _ledgerRepository =
        ledgerRepository ?? LedgerRepository(session: this.session);
    _budgetRepository = budgetRepository ??
        BudgetRepository(
          session: this.session,
          remote: api == null ? null : BudgetRemoteDataSource(api: api!),
        );
  }

  final LocalRepository _local;
  LocalRepository get local =>
      _localOwnerUserId == null ? _local : _local.forUser(_localOwnerUserId!);
  final SyncQueue queue;
  final LocalStateSession session;
  late final AssetsRepository _assetsRepository;
  late final LedgerRepository _ledgerRepository;
  late final BudgetRepository _budgetRepository;
  final ApiClient? api;
  String? _localOwnerUserId;
  int? _boundApiGeneration;
  int _ownerGeneration = 0;
  (int, int) get sessionIdentity =>
      (_ownerGeneration, api?.sessionGeneration ?? 0);
  final Set<String> _pendingConflictClientOpIds = <String>{};

  AssetsRepository get assetsRepository => _assetsRepository;

  BudgetRepository get budgetRepository => _budgetRepository;

  String? get localOwnerUserId => _localOwnerUserId;

  bool get isLocalOwnerBound =>
      _localOwnerUserId != null &&
      (api == null || _boundApiGeneration == api!.sessionGeneration);

  Future<FinanceState?> loadForUser(String userId) async {
    final generation = api?.sessionGeneration;
    await ensureLocalOwner(userId);
    if (generation != api?.sessionGeneration) return null;
    return load();
  }

  Future<void> ensureLocalOwner(String userId) async {
    final normalizedUserId = userId.trim();
    if (normalizedUserId.isEmpty) {
      throw ArgumentError.value(userId, 'userId', '用户身份不能为空');
    }
    final generation = api?.sessionGeneration;
    await _local.migrateLegacy();
    if (generation != api?.sessionGeneration) return;
    final needsRebind = session.local.userId != normalizedUserId;
    if (_localOwnerUserId != normalizedUserId) {
      _ownerGeneration++;
      _pendingConflictClientOpIds.clear();
    }
    _localOwnerUserId = normalizedUserId;
    _boundApiGeneration = generation;
    await _local.saveOwnerUserId(normalizedUserId);
    if (needsRebind) await session.rebind(_local.forUser(normalizedUserId));
  }

  void unbindLocalOwner() {
    _ownerGeneration++;
    _localOwnerUserId = null;
    _boundApiGeneration = null;
  }

  Future<bool> restoreLocalOwnerForVerifiedSession() async {
    final generation = api?.sessionGeneration;
    if (api == null || api!.token == null || api!.token!.trim().isEmpty) {
      return false;
    }
    final verifiedUserId = api!.lastVerifiedUserId?.trim();
    if (verifiedUserId == null || verifiedUserId.isEmpty) return false;
    final storedOwner = await _local.loadOwnerUserId();
    if (storedOwner != verifiedUserId &&
        await _local
                .forUser(verifiedUserId)
                .readMetadata(LocalRepository.storageKey) ==
            null) {
      return false;
    }
    if (generation != api?.sessionGeneration) return false;
    await _local.migrateLegacy();
    if (generation != api?.sessionGeneration) return false;
    _localOwnerUserId = verifiedUserId;
    _boundApiGeneration = generation;
    await session.rebind(_local.forUser(verifiedUserId));
    return true;
  }

  Future<FinanceState?> load() async {
    final started = sessionIdentity;
    if (api != null && !isLocalOwnerBound) {
      final restored = await restoreLocalOwnerForVerifiedSession();
      if (sessionIdentity != started) return null;
      if (!restored) {
        await session.mutateQueue((pending) {
          if (sessionIdentity == started) pending.replace(const []);
        });
        return null;
      }
    }
    return session.load();
  }

  Future<void> save(FinanceState state) => session.replaceState(state);

  Future<void> persistQueue() => session.mutateQueue((_) {});

  Future<void> clearPendingOperations() =>
      session.mutateQueue((pending) => pending.replace(const []));

  Future<FinanceState> applyLocal(
      FinanceState state, FinanceTransaction transaction) async {
    return applyLocalTransaction(state, transaction);
  }

  Future<FinanceState> applyLocalTransaction(
          FinanceState state, FinanceTransaction transaction) =>
      _ledgerRepository.saveTransaction(transaction, baseState: state);

  /*
   * The remaining aggregate and sync methods stay below this boundary. They
   * use the same session instance, so changing the user only swaps its
   * partition and cache; it does not introduce a second write path.
   */

  Future<FinanceState> applyLocalBudget(
      FinanceState state, Budget budget) async {
    return _budgetRepository.saveBudget(budget, baseState: state);
  }

  Future<FinanceState> applyLocalAccount(FinanceState state, Account account) =>
      _assetsRepository.saveAccount(account, baseState: state);

  Future<FinanceState> applyLocalCategory(
          FinanceState state, Category category) =>
      _ledgerRepository.saveCategory(category, baseState: state);

  Future<FinanceState> softDelete(FinanceState state, String transactionId) =>
      _ledgerRepository.deleteTransaction(transactionId, baseState: state);

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
    if (api == null)
      return state.copyWith(syncState: const SyncState(error: '离线演示/待配置'));
    if (!isLocalOwnerBound) {
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
          if (defaultAccount != null)
            nextState = nextState.copyWith(defaultAccountId: defaultAccount.id);
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
