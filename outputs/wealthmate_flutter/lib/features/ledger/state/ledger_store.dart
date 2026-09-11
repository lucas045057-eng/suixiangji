import 'dart:math';

import 'package:flutter/foundation.dart' show ChangeNotifier;

import '../../../domain/finance_rules.dart';
import '../../../domain/models.dart';
import '../../../data/sync_queue.dart';
import '../data/ledger_repository.dart';
import '../domain/ledger_rules.dart';

class LedgerStore extends ChangeNotifier {
  LedgerStore({required this.repository, FinanceState? initialState})
      : _state = initialState ?? const FinanceState(),
        _initialStatePending = initialState != null;

  final LedgerRepository repository;
  FinanceState _state;
  bool _initialStatePending;
  String? _message;

  /// Called when a Ledger mutation also needs to update a compatibility store.
  void Function(FinanceState state)? onStateChanged;

  FinanceState get state => _state;
  List<FinanceTransaction> get transactions =>
      List.unmodifiable(_state.transactions);
  List<Category> get activeCategories => LedgerRules.activeCategories(_state);
  String? get message => _message;
  bool get isDemoMode => repository.api == null;

  FinanceMetrics get metrics {
    final month = _state.currentMonth.isEmpty
        ? _monthKey(DateTime.now())
        : _state.currentMonth;
    return FinanceRules.deriveMetrics(_state, month);
  }

  void adoptState(FinanceState state, {bool notify = false}) {
    _state = state;
    _initialStatePending = false;
    if (notify) {
      onStateChanged?.call(state);
      notifyListeners();
    }
  }

  Future<bool> _apply(FinanceState Function(FinanceState) mutation,
      SyncOperation operation) async {
    final startedLocal = repository.session.local;
    final next = await repository.applyTransaction((current) {
      final base = _initialStatePending ? _state : current;
      _initialStatePending = false;
      return mutation(base);
    }, operation: operation);
    if (!identical(repository.session.local, startedLocal)) return false;
    _state = next;
    onStateChanged?.call(next);
    notifyListeners();
    return true;
  }

  Future<void> addTransaction(FinanceTransaction transaction) async {
    final applied = await _apply(
      (state) => LedgerRules.upsertTransaction(state, transaction),
      _transactionOperation(transaction),
    );
    if (!applied) return;
    _message = '已保存到本地';
  }

  Future<void> updateTransaction(FinanceTransaction transaction) async {
    final existing = _state.transactions
        .where((item) => item.id == transaction.id)
        .firstOrNull;
    if (existing == null) return;
    final effective = transaction.copyWith(
      id: existing.id,
      clientOpId: _isPendingCreate(existing)
          ? existing.clientOpId
          : _newEditOperationId(),
    );
    final applied = await _apply(
      (state) => LedgerRules.upsertTransaction(state, effective),
      _transactionOperation(effective),
    );
    if (!applied) return;
    _message = '账目已更新';
  }

  Future<void> deleteTransaction(String transactionId) async {
    final existing = _state.transactions
        .where((item) => item.id == transactionId)
        .firstOrNull;
    if (existing == null) return;
    final deletedAt = DateTime.now().toIso8601String();
    final deleted = existing.copyWith(deletedAt: deletedAt);
    final applied = await _apply(
      (state) =>
          LedgerRules.softDeleteTransaction(state, transactionId, deletedAt),
      SyncOperation(
        clientOpId: _newDeleteOperationId(),
        entity: 'transactions',
        entityId: transactionId,
        type: SyncOperationType.delete,
        payload: deleted.toJson(),
        createdAt: deletedAt,
      ),
    );
    if (!applied) return;
    _message = '账目已移入待同步删除队列';
  }

  Future<void> addCategory(
      {required String name, required TransactionType type}) async {
    final category = Category(
      id: 'category-${DateTime.now().microsecondsSinceEpoch}',
      name: name,
      type: type,
    );
    final applied = await _apply(
      (state) => LedgerRules.upsertCategory(state, category),
      _categoryOperation(category),
    );
    if (!applied) return;
    _message = '分类已保存';
  }

  Future<void> updateCategory(String categoryId,
      {required String name, required bool active}) async {
    final existing =
        _state.categories.where((item) => item.id == categoryId).firstOrNull;
    if (existing == null) return;
    final category = Category(
      id: existing.id,
      name: name,
      active: active,
      type: existing.type,
    );
    final applied = await _apply(
      (state) => LedgerRules.upsertCategory(state, category),
      _categoryOperation(category),
    );
    if (!applied) return;
    _message = active ? '分类已更新' : '分类已归档';
  }

  Future<void> archiveCategory(String categoryId) async {
    final existing =
        _state.categories.where((item) => item.id == categoryId).firstOrNull;
    if (existing == null) return;
    await updateCategory(categoryId, name: existing.name, active: false);
  }

  bool _isPendingCreate(FinanceTransaction transaction) {
    return transaction.serverVersion == null &&
        repository.queue.pending().any((operation) =>
            operation.entity == 'transactions' &&
            operation.entityId == transaction.id &&
            operation.type == SyncOperationType.upsert &&
            operation.clientOpId == transaction.clientOpId);
  }

  SyncOperation _transactionOperation(FinanceTransaction transaction) =>
      SyncOperation(
        clientOpId: transaction.clientOpId,
        entity: 'transactions',
        entityId: transaction.id,
        type: SyncOperationType.upsert,
        payload: transaction.toJson(),
        createdAt: DateTime.now().toIso8601String(),
      );

  SyncOperation _categoryOperation(Category category) => SyncOperation(
        clientOpId:
            'category:${category.id}:${DateTime.now().microsecondsSinceEpoch}',
        entity: 'categories',
        entityId: category.id,
        type: SyncOperationType.upsert,
        payload: category.toJson(),
        createdAt: DateTime.now().toIso8601String(),
      );

  String _newEditOperationId() =>
      'edit-${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 32)}';

  String _newDeleteOperationId() =>
      'delete-${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 32)}';

  static String _monthKey(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}';
}
