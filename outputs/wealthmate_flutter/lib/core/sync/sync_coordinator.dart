import 'dart:math' show max, Random;

import 'package:flutter/foundation.dart' show mapEquals;

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
    var pushWatermark = state.syncState.serverVersion;
    var ready = state;
    if ((await session.pendingOperations())
        .any((op) => op.conflictClientOpId != null)) {
      ready = await _pullChanges(state, isCurrent: isCurrent);
      if (ready.syncState.error != null) return ready;
    }
    final pushed = await _pushPending(ready,
        onWatermark: (version) => pushWatermark = max(pushWatermark, version),
        isCurrent: isCurrent);
    if (isCurrent != null && !isCurrent()) return pushed;
    if (pushed.syncState.error != null) return pushed;
    return _pullChanges(pushed,
        minimumServerVersion: pushWatermark, isCurrent: isCurrent);
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
      } else if (remote.serverVersion == null ||
          merged[index].serverVersion == null ||
          remote.serverVersion! >= merged[index].serverVersion!) {
        merged[index] = remote;
      }
    }
    return localState.copyWith(budgets: merged);
  }

  Future<FinanceState> pushPending(FinanceState state,
          {bool Function()? isCurrent}) =>
      _pushPending(state, isCurrent: isCurrent);

  Future<FinanceState> _pushPending(FinanceState state,
      {void Function(int)? onWatermark, bool Function()? isCurrent}) async {
    if (isCurrent != null && !isCurrent()) return state;
    if (api == null) {
      return state.copyWith(
          syncState: state.syncState.copyWith(error: '离线演示/待配置'));
    }
    if (!isLocalOwnerBound()) {
      return state.copyWith(
          syncState: state.syncState.copyWith(error: '当前用户身份尚未确认，暂不上传本地数据'));
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
      if ((await session.pendingOperations()).any((op) =>
          op.entity == 'budgets' &&
          op.submittedOperation == null &&
          op.conflictClientOpId == null)) {
        await session.mutateQueue((pendingQueue) {
          for (final op in pendingQueue.pending()) {
            if (op.entity != 'budgets' ||
                op.submittedOperation != null ||
                op.conflictClientOpId != null) continue;
            pendingQueue.enqueue(SyncOperation(
                clientOpId: op.clientOpId,
                entity: op.entity,
                entityId: op.entityId,
                type: op.type,
                payload: op.payload,
                createdAt: op.createdAt,
                submittedOperation: op.toJson()));
          }
        });
      }
      final operations = (await session.pendingOperations())
          .map((op) => op.submittedOperation == null
              ? op
              : SyncOperation.fromJson(op.submittedOperation!))
          .toList();
      final result = await api!.push(operations);
      onWatermark?.call((result['server_version'] as num?)?.toInt() ?? 0);
      if (result['results'] is List) {
        return await _applyV2Push(state, operations, result,
            isCurrent: isCurrent);
      }
      final accepted =
          ((result['accepted'] as List<Object?>?) ?? const <Object?>[])
              .map((item) => (item! as Map).cast<String, Object?>())
              .toList();
      if (isCurrent != null && !isCurrent()) return state;
      final acceptedByOperation = <String, Map<String, Object?>>{
        for (final item in accepted) item['client_op_id']! as String: item,
      };
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
          final pending = queue
              .pending()
              .where((item) =>
                  item.entity == operation.entity &&
                  item.entityId == operation.entityId)
              .firstOrNull;
          if (pending == null) continue;
          final snapshot = _entitySnapshot(base, operation);
          if (pending.clientOpId != operation.clientOpId ||
              pending.type != operation.type ||
              !mapEquals(pending.payload, operation.payload) ||
              !_matchesSnapshot(snapshot, operation.payload)) {
            // The receipt belongs to the preceding snapshot. Keep the edit
            // queued against that accepted base; never reuse an accepted ID.
            final nextId = pending.clientOpId == operation.clientOpId
                ? 'edit-${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 32)}'
                : pending.clientOpId;
            if (pending.entity == 'budgets') queue.complete(pending.clientOpId);
            queue.enqueue(SyncOperation(
              clientOpId: nextId,
              entity: pending.entity,
              entityId: pending.entityId,
              type: pending.type,
              payload: {
                ...pending.payload,
                if (pending.entity != 'categories')
                  'server_version': serverVersion,
                if (pending.entity == 'transactions') 'client_op_id': nextId
              },
              createdAt: pending.createdAt,
            ));
            if (pending.entity == 'transactions') {
              final index = nextTransactions
                  .indexWhere((item) => item.id == pending.entityId);
              if (index >= 0) {
                nextTransactions[index] =
                    nextTransactions[index].copyWith(clientOpId: nextId);
              }
            }
            continue;
          }
          // Queue completion and the matching entity version are persisted
          // together by this serialized LocalStateSession write.
          queue.complete(operation.clientOpId);
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
        for (final conflict in conflictItems) {
          final sent = operations
              .where((op) => op.clientOpId == conflict['client_op_id'])
              .firstOrNull;
          if (sent == null || sent.entity != 'budgets') continue;
          final pending = queue
              .pending()
              .where((op) =>
                  op.entity == 'budgets' && op.entityId == sent.entityId)
              .firstOrNull;
          if (pending == null) continue;
          queue.complete(pending.clientOpId);
          queue.enqueue(SyncOperation(
              clientOpId: pending.clientOpId,
              entity: pending.entity,
              entityId: pending.entityId,
              type: pending.type,
              payload: pending.payload,
              createdAt: pending.createdAt,
              conflictClientOpId:
                  pending.conflictClientOpId ?? sent.clientOpId));
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
                // A push receipt acknowledges writes, not downloaded records.
                // Persist the download cursor only after pull completes.
                serverVersion: base.syncState.serverVersion,
                lastSyncedAt: base.syncState.lastSyncedAt));
      }, initialState: state);
      return nextState;
    } on ApiFailure catch (failure) {
      return _recordFailure(state, failure.message,
          isCurrent: isCurrent, failure: failure);
    }
  }

  Future<FinanceState> pullChanges(FinanceState state,
          {bool Function()? isCurrent}) =>
      _pullChanges(state, isCurrent: isCurrent);

  /// Applies a V2 `{results, rejected, conflicts}` push response.
  ///
  /// Every sent operation receives exactly one outcome. The queue must drain:
  /// a rejected operation is rolled back locally, its intent is kept as a
  /// durable [SyncIssue], and later operations still apply. Version races
  /// adopt the authoritative row; field conflicts are already resolved by the
  /// server and arrive as a normal `merged` result carrying the complete row.
  Future<FinanceState> _applyV2Push(
    FinanceState state,
    List<SyncOperation> operations,
    Map<String, Object?> result, {
    bool Function()? isCurrent,
  }) async {
    if (isCurrent != null && !isCurrent()) return state;
    Map<String, Map<String, Object?>> byOp(Object? value) => {
          for (final item in ((value as List<Object?>?) ?? const <Object?>[])
              .map((item) => (item! as Map).cast<String, Object?>()))
            if (item['op_id'] is String) item['op_id']! as String: item,
        };
    final results = byOp(result['results']);
    final rejected = byOp(result['rejected']);
    final conflicts = byOp(result['conflicts']);
    final nextState = await session.write((current) {
      final base = _mergeCurrentWithRequested(current, state);
      var next = base;
      final issues = [...base.syncIssues];
      final pendingAtResponse = queue.pending();

      void addIssue(SyncOperation operation, Map<String, Object?> detail) {
        final code = (detail['code'] as String?) ?? 'rejected';
        if (code == 'no_change' || code == 'balance_unchanged') return;
        if (issues.any((issue) =>
            issue.clientOpId == operation.clientOpId && issue.code == code)) {
          return;
        }
        issues.add(SyncIssue(
          clientOpId: operation.clientOpId,
          entity: operation.entity,
          entityId: operation.entityId,
          code: code,
          detail: (detail['detail'] as String?) ?? '',
          field: detail['field'] as String?,
          createdAt: DateTime.now().toIso8601String(),
        ));
      }

      for (final operation in operations) {
        final resultItem = results[operation.clientOpId];
        final rejectedItem = rejected[operation.clientOpId];
        final conflictItem = conflicts[operation.clientOpId];
        if (resultItem == null &&
            rejectedItem == null &&
            conflictItem == null) {
          // No receipt for this operation: keep it queued instead of losing
          // the local intent.
          continue;
        }
        final pending = pendingAtResponse
            .where((item) =>
                item.entity == operation.entity &&
                item.entityId == operation.entityId)
            .firstOrNull;
        // A local edit made while the push was in flight is a newer intent.
        // Never overwrite it with a receipt for the preceding snapshot.
        final canApply = pending != null &&
            pending.clientOpId == operation.clientOpId &&
            pending.type == operation.type &&
            mapEquals(pending.payload, operation.payload) &&
            _matchesSnapshot(
                _entitySnapshot(base, operation), operation.payload);
        final row = _rowOf(resultItem?['row']) ??
            _rowOf(conflictItem?['authoritative_row']);
        final rejectedCode = (rejectedItem?['code'] as String?) ??
            (resultItem?['status'] == 'rejected' ? 'rejected' : null);

        if (rejectedCode != null) {
          if (canApply) next = _rollbackOperation(next, operation);
          addIssue(
              operation,
              rejectedItem ??
                  <String, Object?>{
                    'code': rejectedCode,
                    'detail': resultItem?['detail'],
                  });
          final newId = _retireV2Operation(operation, pending,
              canApply: canApply, row: null);
          if (newId != null) {
            next = _relabelTransaction(next, operation.entityId, newId);
          }
        } else if (conflictItem != null) {
          final reason =
              (conflictItem['reason'] as String?) ?? 'version_conflict';
          if (canApply) {
            if (row != null) {
              next = _adoptV2Row(next, operation, row);
            } else if (reason == 'balance_changed') {
              // The adjustment was never applied; drop the optimistic row so
              // the local balance does not count it.
              next = _rollbackOperation(next, operation);
            }
          }
          addIssue(operation, {
            'code': reason,
            'detail': conflictItem['detail'],
          });
          final newId = _retireV2Operation(operation, pending,
              canApply: canApply, row: row);
          if (newId != null) {
            next = _relabelTransaction(next, operation.entityId, newId);
          }
        } else {
          if (canApply && row != null) {
            next = _adoptV2Row(next, operation, row);
          }
          final newId = _retireV2Operation(operation, pending,
              canApply: canApply, row: row);
          if (newId != null) {
            next = _relabelTransaction(next, operation.entityId, newId);
          }
        }
      }

      while (issues.length > 50) {
        issues.removeAt(0);
      }

      return next.copyWith(
        syncIssues: issues,
        syncState: SyncState(
          // A push receipt acknowledges writes, not downloaded records.
          serverVersion: base.syncState.serverVersion,
          lastSyncedAt: base.syncState.lastSyncedAt,
        ),
      );
    }, initialState: state);
    return nextState;
  }

  Map<String, Object?>? _rowOf(Object? value) =>
      value is Map ? value.cast<String, Object?>() : null;

  String _newOperationId() =>
      'edit-${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 32)}';

  /// Completes the sent operation. When a newer local edit is still queued,
  /// it is re-issued under a fresh operation ID (a V2 ID cannot be reused with
  /// different contents) and rebased onto any authoritative row.
  String? _retireV2Operation(
    SyncOperation sent,
    SyncOperation? pending, {
    required bool canApply,
    Map<String, Object?>? row,
  }) {
    if (pending == null || canApply) {
      queue.complete(sent.clientOpId);
      return null;
    }
    final sharesId = pending.clientOpId == sent.clientOpId;
    final newId = sharesId ? _newOperationId() : pending.clientOpId;
    final version = (row?['server_version'] as num?)?.toInt();
    if (sharesId) queue.complete(pending.clientOpId);
    queue.enqueue(SyncOperation(
      clientOpId: newId,
      entity: pending.entity,
      entityId: pending.entityId,
      type: pending.type,
      payload: {
        ...pending.payload,
        if (version != null) 'server_version': version,
        if (pending.entity == 'transactions') 'client_op_id': newId,
      },
      createdAt: pending.createdAt,
      baseVersion: version ?? pending.baseVersion,
      base: row ?? pending.base,
    ));
    return sharesId && pending.entity == 'transactions' ? newId : null;
  }

  FinanceState _relabelTransaction(
      FinanceState state, String entityId, String clientOpId) {
    return state.copyWith(transactions: [
      for (final item in state.transactions)
        item.id == entityId ? item.copyWith(clientOpId: clientOpId) : item,
    ]);
  }

  FinanceState _adoptV2Row(
      FinanceState state, SyncOperation operation, Map<String, Object?> row) {
    switch (operation.entity) {
      case 'accounts':
        final account = Account.fromJson(row);
        return state.copyWith(accounts: [
          ...state.accounts.where(
              (item) => item.id != operation.entityId && item.id != account.id),
          account,
        ]);
      case 'transactions':
        final transaction = FinanceTransaction.fromJson(row);
        return state.copyWith(transactions: [
          ...state.transactions.where((item) =>
              item.id != operation.entityId && item.id != transaction.id),
          transaction,
        ]);
      case 'categories':
        final category = Category.fromJson(row);
        return state.copyWith(categories: [
          ...state.categories.where((item) =>
              item.id != operation.entityId && item.id != category.id),
          category,
        ]);
      case 'budgets':
        final budget = Budget.fromJson(row);
        return state.copyWith(budgets: [
          ...state.budgets.where(
              (item) => item.id != operation.entityId && item.id != budget.id),
          budget,
        ]);
      case 'user_preferences':
        return _projectV2Preference(state, UserPreference.fromJson(row));
      default:
        return state;
    }
  }

  /// Rolls one rejected/conflicted operation back to its captured baseline.
  /// Without a baseline (an optimistic create) the entity is discarded.
  FinanceState _rollbackOperation(FinanceState state, SyncOperation operation) {
    final base = operation.base;
    if (base != null) {
      switch (operation.entity) {
        case 'accounts':
          final account = Account.fromJson(base);
          return state.copyWith(accounts: [
            ...state.accounts.where((item) => item.id != operation.entityId),
            account,
          ]);
        case 'transactions':
          final transaction = FinanceTransaction.fromJson(base);
          return state.copyWith(transactions: [
            ...state.transactions
                .where((item) => item.id != operation.entityId),
            transaction,
          ]);
        case 'categories':
          final category = Category.fromJson(base);
          return state.copyWith(categories: [
            ...state.categories.where((item) => item.id != operation.entityId),
            category,
          ]);
        case 'budgets':
          final budget = Budget.fromJson(base);
          return state.copyWith(budgets: [
            ...state.budgets.where((item) => item.id != operation.entityId),
            budget,
          ]);
        case 'user_preferences':
          return _projectV2Preference(state, UserPreference.fromJson(base));
        default:
          return state;
      }
    }
    switch (operation.entity) {
      case 'accounts':
        final remaining = state.accounts
            .where((item) => item.id != operation.entityId)
            .toList();
        final cleared = state.defaultAccountId == operation.entityId
            ? state.copyWith(clearDefaultAccountId: true)
            : state;
        return cleared.copyWith(accounts: [
          for (final account in remaining)
            account.isDefaultPayment && state.defaultAccountId == account.id
                ? account.copyWith(isDefaultPayment: false)
                : account,
        ]);
      case 'transactions':
        return state.copyWith(
            transactions: state.transactions
                .where((item) => item.id != operation.entityId)
                .toList());
      case 'categories':
        return state.copyWith(
            categories: state.categories
                .where((item) => item.id != operation.entityId)
                .toList());
      case 'budgets':
        return state.copyWith(
            budgets: state.budgets
                .where((item) => item.id != operation.entityId)
                .toList());
      case 'user_preferences':
        return _projectV2Preference(
            state.copyWith(clearPreference: true), const UserPreference());
      default:
        return state;
    }
  }

  /// `is_default_payment` is only a local projection of the singleton
  /// preference row.
  FinanceState _projectV2Preference(
      FinanceState state, UserPreference preference) {
    final id = preference.defaultAccountId;
    final scoped = id == null
        ? state.copyWith(clearDefaultAccountId: true, preference: preference)
        : state.copyWith(defaultAccountId: id, preference: preference);
    return scoped.copyWith(accounts: [
      for (final account in scoped.accounts)
        account.isDefaultPayment == (account.id == id)
            ? account
            : account.copyWith(isDefaultPayment: account.id == id),
    ]);
  }

  Future<FinanceState> _pullChanges(FinanceState state,
      {int minimumServerVersion = 0, bool Function()? isCurrent}) async {
    if (isCurrent != null && !isCurrent()) return state;
    if (api == null) {
      return state.copyWith(
          syncState: state.syncState.copyWith(error: '离线演示/待配置'));
    }
    if (!isLocalOwnerBound()) {
      return state.copyWith(
          syncState: state.syncState.copyWith(error: '当前用户身份尚未确认，暂不下载本地数据'));
    }
    try {
      final conflictOperations = _pendingConflictOperations(state);
      // Upgrading from a build that never saw adjustments (1) or category
      // versions (2) must re-read the whole history: its old cursor already
      // skipped those rows. Version 3 backfills Category.serverVersion so the
      // next category edit carries a real CAS baseline instead of silently
      // overwriting another device.
      final needsFullPull = state.financialSchemaVersion < 3;
      final pullSince = needsFullPull
          ? 0
          : conflictOperations.isEmpty
              ? state.syncState.serverVersion
              : conflictOperations.any((op) => op.entity == 'budgets')
                  ? 0
                  : _minimumConflictBaseVersion(
                      conflictOperations, state.syncState.serverVersion);
      final remote = await api!.pullChanges(pullSince);
      if (isCurrent != null && !isCurrent()) return state;
      if (conflictOperations.isNotEmpty) {
        return await _completeConflictRecovery(
            state, remote, conflictOperations);
      }
      final next = await session.write((current) {
        final base = _mergeCurrentWithRequested(current, state);
        // Categories have no per-record version in their local JSON. The
        // response watermark guards the entire batch, including categories.
        if (remote.serverVersion < base.syncState.serverVersion) return base;
        bool pending(String entity, String id) => queue
            .pending()
            .any((item) => item.entity == entity && item.entityId == id);
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
                    mergePulledAccounts(
                        mergePulled(
                            base,
                            remote.transactions
                                .where(
                                    (item) => !pending('transactions', item.id))
                                .toList()),
                        remote.accounts
                            .where((item) => !pending('accounts', item.id))
                            .toList()),
                    remote.categories
                        .where((item) => !pending('categories', item.id))
                        .toList()),
                remote.budgets
                    .where((item) => !pending('budgets', item.id))
                    .toList());
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
        // `preferences: []` means "no preference written yet", not "cleared".
        // A local preference op still in flight is the newer intent.
        final remotePreference = remote.preference;
        final preferencePending =
            pending('user_preferences', UserPreference.singletonId);
        if (remotePreference != null && !preferencePending) {
          final localVersion = nextState.preference?.serverVersion;
          if (localVersion == null ||
              (remotePreference.serverVersion ?? 0) >= localVersion) {
            nextState = _projectV2Preference(
                nextState.copyWith(preference: remotePreference),
                remotePreference);
          }
        }
        return nextState.copyWith(
            financialSchemaVersion: 3,
            syncState: SyncState(
              serverVersion: max(minimumServerVersion,
                  max(base.syncState.serverVersion, remote.serverVersion)),
              lastSyncedAt:
                  queue.pending().isEmpty && nextState.conflicts.isEmpty
                      ? DateTime.now().toIso8601String()
                      : base.syncState.lastSyncedAt,
            ));
      }, initialState: state);
      return next;
    } on ApiFailure catch (failure) {
      return _recordFailure(state, failure.message,
          isCurrent: isCurrent, failure: failure);
    }
  }

  Future<FinanceState> _recordFailure(FinanceState state, String message,
      {bool Function()? isCurrent, ApiFailure? failure}) {
    if (isCurrent != null && !isCurrent()) return Future.value(state);
    return session.write((current) {
      final base = _mergeCurrentWithRequested(current, state);
      // 426 is sticky only when this build is actually below the server's
      // requirement (or the server did not name one). A capable client keeps
      // retrying; a stale persisted gate is cleared here instead of trapping
      // the user forever. A missing `min_protocol` stays null — it is an
      // unknown requirement, never a fabricated version.
      final upgradeFailure = failure?.kind == ApiFailureKind.upgradeRequired;
      final needsClientUpgrade = upgradeFailure && failure!.clientNeedsUpgrade;
      final requiredProtocol = needsClientUpgrade ? failure.minProtocol : null;
      return base.copyWith(
          syncState: base.syncState.copyWith(
              isSyncing: false,
              error: message,
              upgradeRequiredProtocol: requiredProtocol,
              upgradeRequiredWithoutVersion:
                  needsClientUpgrade ? requiredProtocol == null : null,
              clearUpgradeRequired: upgradeFailure && !needsClientUpgrade));
    }, initialState: state);
  }

  Map<String, Object?>? _entitySnapshot(FinanceState state, SyncOperation op) {
    return switch (op.entity) {
      'transactions' => state.transactions
          .where((item) => item.id == op.entityId)
          .firstOrNull
          ?.toJson(),
      'accounts' => state.accounts
          .where((item) => item.id == op.entityId)
          .firstOrNull
          ?.toJson(),
      'categories' => state.categories
          .where((item) => item.id == op.entityId)
          .firstOrNull
          ?.toJson(),
      'budgets' => state.budgets
          .where((item) => item.id == op.entityId)
          .firstOrNull
          ?.toJson(),
      'user_preferences' => state.preference?.toJson(),
      _ => null,
    };
  }

  bool _matchesSnapshot(
      Map<String, Object?>? current, Map<String, Object?> sent) {
    // Legacy queues may omit optional fields. Compare every sent field except
    // the server base, which may have been rebased by a preceding receipt.
    return current != null &&
        sent.entries.every((entry) =>
            entry.key == 'server_version' || current[entry.key] == entry.value);
  }

  List<SyncOperation> _pendingConflictOperations(FinanceState state) {
    final queued = queue.pending();
    final budgetConflicts = queued
        .where((op) => op.conflictClientOpId != null)
        .map((op) => SyncOperation(
            clientOpId: op.conflictClientOpId!,
            entity: op.entity,
            entityId: op.entityId,
            type: op.type,
            payload: op.payload,
            createdAt: op.createdAt))
        .toList();
    if (budgetConflicts.isNotEmpty) return budgetConflicts;
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
    final nextState = await session.write((current) {
      // A local edit may replace the conflicted queue item while the recovery
      // pull is in flight. Only an operation with the same id, type and payload
      // is still the operation whose conflict can be resolved by this response.
      final pendingAtRecovery = queue.pending();
      bool isSameOperation(SyncOperation expected, SyncOperation actual) =>
          expected.clientOpId == actual.clientOpId &&
          expected.entity == actual.entity &&
          expected.entityId == actual.entityId &&
          expected.type == actual.type &&
          mapEquals(expected.payload, actual.payload);
      final activeConflictOperations = conflictOperations
          .where((operation) =>
              pendingAtRecovery.any((item) => isSameOperation(operation, item)))
          .toList(growable: false);
      final protectedEntityKeys = pendingAtRecovery
          .where((pending) => !activeConflictOperations
              .any((operation) => isSameOperation(operation, pending)))
          .map((operation) => '${operation.entity}:${operation.entityId}')
          .toSet();
      bool isProtected(String entity, String id) =>
          protectedEntityKeys.contains('$entity:$id');

      bool hasAuthoritativeEntity(SyncOperation operation) {
        switch (operation.entity) {
          case 'transactions':
            return remote.transactions
                .any((item) => item.id == operation.entityId);
          case 'accounts':
            return remote.accounts.any((item) => item.id == operation.entityId);
          case 'categories':
            return remote.categories
                .any((item) => item.id == operation.entityId);
          case 'budgets':
            return remote.budgets.any((item) =>
                item.id == operation.entityId ||
                (item.month == operation.payload['month'] &&
                    item.categoryId == operation.payload['category_id']));
          default:
            return false;
        }
      }

      if (activeConflictOperations
          .any((operation) => !hasAuthoritativeEntity(operation))) {
        return current.copyWith(
            syncState: current.syncState.copyWith(error: '冲突数据尚未恢复，请稍后重试'));
      }

      final resolvedEntityIds = <String>{
        for (final operation in conflictOperations) operation.entityId,
      };
      for (final operation in activeConflictOperations) {
        queue.complete(operation.clientOpId);
      }
      for (final operation in conflictOperations) {
        _pendingConflictClientOpIds.remove(operation.clientOpId);
      }
      final budgetAliases = activeConflictOperations
          .where((op) =>
              op.entity == 'budgets' &&
              !remote.budgets.any((item) => item.id == op.entityId))
          .map((op) => op.entityId)
          .toSet();
      final canonicalBudgets = <String, Budget>{};
      for (final pending in pendingAtRecovery) {
        if (pending.entity != 'budgets' ||
            !isProtected(pending.entity, pending.entityId)) continue;
        final canonical = remote.budgets
            .where((item) =>
                item.month == pending.payload['month'] &&
                item.categoryId == pending.payload['category_id'])
            .firstOrNull;
        if (canonical != null && canonical.id != pending.entityId) {
          canonicalBudgets[pending.entityId] = canonical;
          protectedEntityKeys.add('budgets:${canonical.id}');
        }
      }
      final retainedBudgets = current.budgets
          .where((item) =>
              !budgetAliases.contains(item.id) &&
              !canonicalBudgets.values
                  .any((canonical) => canonical.id == item.id))
          .map((item) => canonicalBudgets.containsKey(item.id)
              ? Budget.fromJson({
                  ...item.toJson(),
                  'id': canonicalBudgets[item.id]!.id,
                  'server_version': canonicalBudgets[item.id]!.serverVersion
                })
              : item)
          .toList();
      final merged = mergePulledBudgets(
          mergePulledCategories(
              mergePulledAccounts(
                  mergePulled(
                      current.copyWith(budgets: retainedBudgets),
                      remote.transactions
                          .where(
                              (item) => !isProtected('transactions', item.id))
                          .toList()),
                  remote.accounts
                      .where((item) => !isProtected('accounts', item.id))
                      .toList()),
              remote.categories
                  .where((item) => !isProtected('categories', item.id))
                  .toList()),
          remote.budgets
              .where((item) => !isProtected('budgets', item.id))
              .toList());
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
      // A newer local edit made while the conflict pull was blocked is still
      // protected from the remote merge. Rebase its optimistic base to the
      // authoritative watermark so the serialized drain can submit it in the
      // next round instead of treating it as the same stale conflict again.
      for (final pending in pendingAtRecovery) {
        if (!isProtected(pending.entity, pending.entityId)) {
          continue;
        }
        final canonical = canonicalBudgets[pending.entityId];
        queue.complete(pending.clientOpId);
        queue.enqueue(SyncOperation(
          clientOpId: pending.clientOpId,
          entity: pending.entity,
          entityId: canonical?.id ?? pending.entityId,
          type: pending.type,
          payload: {
            ...pending.payload,
            if (canonical != null) 'id': canonical.id,
            'server_version': canonical?.serverVersion ?? nextVersion
          },
          createdAt: pending.createdAt,
        ));
      }
      final hasPending = queue.pending().isNotEmpty;
      return merged.copyWith(
          financialSchemaVersion: 3,
          conflicts: remainingConflicts,
          syncState: SyncState(
            serverVersion: nextVersion,
            lastSyncedAt: hasPending || remainingConflicts.isNotEmpty
                ? current.syncState.lastSyncedAt
                : DateTime.now().toIso8601String(),
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
      accounts: _appendMissingById(
          current.accounts, requested.accounts, (item) => item.id),
      categories: _appendMissingById(
          current.categories, requested.categories, (item) => item.id),
      transactions: _appendMissingById(
          current.transactions, requested.transactions, (item) => item.id),
      budgets: _appendMissingById(
          current.budgets, requested.budgets, (item) => item.id),
      exchangeRates: _appendMissingById(
          current.exchangeRates,
          requested.exchangeRates,
          (item) => '${item.baseCurrency}:${item.quoteCurrency}'),
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
