import 'dart:math';

import '../../../core/database/local_state_session.dart';
import '../../../data/api_client.dart';
import '../../../data/sync_queue.dart';
import '../../../domain/models.dart';
import 'ledger_remote_data_source.dart';
import '../domain/ledger_rules.dart';

class LedgerRepository {
  LedgerRepository({required this.session, this.remote});

  final LocalStateSession session;
  final LedgerRemoteDataSource? remote;

  ApiClient? get api => remote?.api;
  SyncQueue get queue => session.queue;

  Future<FinanceState?> load() => session.load();

  Future<FinanceState> applyTransaction(
    FinanceState Function(FinanceState) mutation, {
    required SyncOperation operation,
  }) {
    return session.write(
      mutation,
      appendOperations: [operation],
    );
  }

  Future<FinanceState> saveTransaction(FinanceTransaction transaction,
      {FinanceState? baseState}) {
    return applyTransaction(
      (current) =>
          LedgerRules.upsertTransaction(baseState ?? current, transaction),
      operation: SyncOperation(
        clientOpId: transaction.clientOpId,
        entity: 'transactions',
        entityId: transaction.id,
        type: SyncOperationType.upsert,
        payload: transaction.toJson(),
        createdAt: DateTime.now().toIso8601String(),
      ),
    );
  }

  Future<FinanceState> saveCategory(Category category,
      {FinanceState? baseState}) {
    return applyTransaction(
      (current) => LedgerRules.upsertCategory(baseState ?? current, category),
      operation: SyncOperation(
        clientOpId:
            'category:${category.id}:${DateTime.now().microsecondsSinceEpoch}',
        entity: 'categories',
        entityId: category.id,
        type: SyncOperationType.upsert,
        payload: category.toJson(),
        createdAt: DateTime.now().toIso8601String(),
      ),
    );
  }

  Future<FinanceState> deleteTransaction(String transactionId,
      {FinanceState? baseState, String? deletedAt}) async {
    final state = baseState ?? await session.load() ?? const FinanceState();
    final existing =
        state.transactions.firstWhere((item) => item.id == transactionId);
    final timestamp = deletedAt ?? DateTime.now().toIso8601String();
    final deleted = existing.copyWith(deletedAt: timestamp);
    return applyTransaction(
      (current) => LedgerRules.softDeleteTransaction(
          baseState ?? current, transactionId, timestamp),
      operation: SyncOperation(
        clientOpId:
            'delete-${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 32)}',
        entity: 'transactions',
        entityId: transactionId,
        type: SyncOperationType.delete,
        payload: deleted.toJson(),
        createdAt: timestamp,
      ),
    );
  }
}
