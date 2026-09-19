import 'package:flutter/foundation.dart' show ChangeNotifier;

import '../../../domain/models.dart';
import '../data/budget_repository.dart';
import '../domain/budget_rules.dart' as rules;

class BudgetStore extends ChangeNotifier {
  BudgetStore({required this.repository, FinanceState? initialState})
      : _state = initialState ?? const FinanceState(),
        _initialStatePending = initialState != null;

  final BudgetRepository repository;
  FinanceState _state;
  bool _initialStatePending;
  List<BudgetAlert> _alerts = const [];

  void Function(FinanceState state)? onStateChanged;
  void Function(String reason)? onLocalMutation;

  FinanceState get state => _state;
  List<Budget> get budgets => List.unmodifiable(_state.budgets);
  List<Category> get activeCategories =>
      _state.categories.where((item) => item.active).toList(growable: false);
  List<BudgetAlert> get alerts => List.unmodifiable(_alerts);
  List<BudgetProgress> get progress =>
      rules.progressForMonth(_state, _monthKey);
  String get _monthKey => _state.currentMonth.isEmpty
      ? _formatMonth(DateTime.now())
      : _state.currentMonth;

  void adoptState(FinanceState state, {bool notify = false}) {
    _state = state;
    _initialStatePending = false;
    if (notify) {
      onStateChanged?.call(state);
      notifyListeners();
    }
  }

  List<BudgetProgress> progressForMonth(String month) =>
      rules.progressForMonth(_state, month);

  Future<void> upsertBudget({
    String? id,
    required String month,
    required String categoryId,
    required double limit,
  }) async {
    final budget = Budget(
      id: id ?? 'budget-${DateTime.now().microsecondsSinceEpoch}',
      month: month,
      categoryId: categoryId,
      limit: limit,
    );
    final baseState = _initialStatePending ? _state : null;
    _initialStatePending = false;
    final next = await repository.saveBudget(budget, baseState: baseState);
    _state = next;
    onStateChanged?.call(next);
    notifyListeners();
    onLocalMutation?.call('budget.upsert');
  }

  Future<List<BudgetAlert>> checkBudgetAlerts() async {
    final seen = await repository.readAlertKeys();
    final next = <BudgetAlert>[];
    for (final item in progress) {
      final level = rules.levelForRatio(item.ratio);
      if (level == null) continue;
      final alert =
          BudgetAlert(budget: item.budget, spent: item.spent, level: level);
      if (seen.add(alert.key)) next.add(alert);
    }
    if (next.isNotEmpty) await repository.writeAlertKeys(seen);
    _alerts = next;
    notifyListeners();
    return next;
  }

  void clearAlerts() {
    _alerts = const [];
    notifyListeners();
  }

  static String _formatMonth(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}';
}
