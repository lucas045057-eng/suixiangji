import 'package:flutter/material.dart';

import '../../../data/api_client.dart';
import '../../../domain/models.dart';
import '../data/insights_repository.dart';
import '../domain/insight_rules.dart';

class InsightsStore extends ChangeNotifier {
  InsightsStore({required this.repository, FinanceState? initialState})
      : _state = initialState ?? const FinanceState(),
        _initialStatePending = initialState != null;

  final InsightsRepository repository;
  FinanceState _state;
  bool _initialStatePending;
  String? _selectedMonth;
  String? _message;
  FinanceMetrics? _metricsCache;
  String? _metricsCacheMonth;

  FinanceState get state => _state;
  String get monthKey => _selectedMonth ??
      (_state.currentMonth.isEmpty
          ? _formatMonth(DateTime.now())
          : _state.currentMonth);
  FinanceMetrics get metrics {
    final month = monthKey;
    final cached = _metricsCache;
    if (cached != null && _metricsCacheMonth == month) return cached;
    final derived = InsightRules.deriveMetrics(_state, month);
    _metricsCache = derived;
    _metricsCacheMonth = month;
    return derived;
  }
  String? get message => _message;
  List<PeriodPoint> trend(DateTimeRange range) =>
      InsightRules.periodExpenseSeries(_state, range);
  Map<String, double> expenseByCategory(DateTimeRange range) =>
      InsightRules.expenseByCategory(_state, range);
  Map<String, double> expenseByAccount(DateTimeRange range) =>
      InsightRules.expenseByAccount(_state, range);

  void adoptState(FinanceState state, {bool notify = false}) {
    _state = state;
    _metricsCache = null;
    _metricsCacheMonth = null;
    _initialStatePending = false;
    if (notify) notifyListeners();
  }

  Future<void> refresh({String? month}) async {
    if (month != null && month.isNotEmpty) _selectedMonth = month;
    final remote = repository.remote;
    if (remote != null) {
      try {
        await repository.fetchStats(monthKey);
        _message = '统计已更新';
      } on ApiFailure {
        _message = '统计服务暂不可用，显示本地统计';
      }
    }
    notifyListeners();
  }

  Future<void> generateMonthlyReport() async {
    final month = monthKey;
    if (repository.remote != null) {
      try {
        final result =
            await repository.fetchMonthlyReport(month, force: true);
        final report = Report(
          id: '${result['id'] ?? 'report-$month'}',
          month: result['month'] as String? ?? month,
          title: ((result['ai_status'] as String?) == 'success')
              ? 'AI 月度财务分析'
              : '本月程序统计（AI 未配置）',
          summary: result['summary'] as String? ?? '当前数据不足，无法判断。',
          generatedAt: result['generated_at'] as String? ??
              DateTime.now().toIso8601String(),
        );
        _state = await repository.saveReport(
          report,
          baseState: _initialStatePending ? _state : null,
        );
        _initialStatePending = false;
        _message = '月度报告已从服务端更新';
        notifyListeners();
        return;
      } on ApiFailure {
        _message = '报告服务暂不可用，保留本地程序统计';
      }
    }

    final current = metrics;
    final report = Report(
      id: 'report-${current.monthKey}',
      month: current.monthKey,
      title: current.savings >= 0 ? '本月结余正在形成安全垫' : '本月支出超过收入，需要留意节奏',
      summary:
          '本月收入 ${current.income.toStringAsFixed(0)} 元，支出 ${current.expense.toStringAsFixed(0)} 元，储蓄率 ${(current.savingsRate * 100).round()}%。',
      generatedAt: DateTime.now().toIso8601String(),
    );
    _state = await repository.saveReport(
      report,
      baseState: _initialStatePending ? _state : null,
    );
    _initialStatePending = false;
    if (repository.remote == null) {
      _message = '月度报告已更新';
    }
    notifyListeners();
  }

  static String _formatMonth(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}';
}
