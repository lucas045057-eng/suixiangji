import 'package:flutter/material.dart';

import '../domain/finance_rules.dart';
import '../state/finance_store.dart';
import 'widgets/bar_chart.dart';
import 'widgets/line_chart.dart';
import 'widgets/pie_chart.dart';
import 'widgets/ui_helpers.dart';

enum StatsPeriod { day, week, month }

class StatsPage extends StatefulWidget {
  const StatsPage({required this.store, super.key});

  final FinanceStore store;

  @override
  State<StatsPage> createState() => _StatsPageState();
}

class _StatsPageState extends State<StatsPage> {
  StatsPeriod period = StatsPeriod.month;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.store,
      builder: (context, _) {
        final range = _rangeFor(period, widget.store.metrics.monthKey);
        final points =
            FinanceRules.periodExpenseSeries(widget.store.state, range);
        final categoryTotals =
            FinanceRules.expenseByCategory(widget.store.state, range);
        final accountTotals =
            FinanceRules.expenseByAccount(widget.store.state, range);
        final categories = _sortedCategoryItems(categoryTotals);
        final totalExpense =
            categoryTotals.values.fold<double>(0, (sum, value) => sum + value);
        final highestCategory =
            categories.isEmpty ? '暂无' : categories.first.label;
        final highestAccount = accountTotals.isEmpty
            ? '暂无'
            : accountTotals.entries
                .reduce((a, b) => a.value >= b.value ? a : b)
                .key;
        final average = totalExpense == 0
            ? 0.0
            : totalExpense /
                (period == StatsPeriod.day
                    ? 1.0
                    : (range.duration.inDays + 1).toDouble());
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(22, 24, 22, 100),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('统计',
                    style:
                        TextStyle(fontSize: 27, fontWeight: FontWeight.w800)),
                const SizedBox(height: 5),
                Text('${_periodLabel(period)} · 看见钱流向哪里',
                    style: const TextStyle(
                        color: Color(0xFF87958F), fontSize: 11)),
                const SizedBox(height: 16),
                SegmentedButton<StatsPeriod>(
                    segments: const [
                      ButtonSegment(value: StatsPeriod.day, label: Text('本日')),
                      ButtonSegment(value: StatsPeriod.week, label: Text('本周')),
                      ButtonSegment(value: StatsPeriod.month, label: Text('本月'))
                    ],
                    selected: {
                      period
                    },
                    onSelectionChanged: (value) =>
                        setState(() => period = value.first)),
                const SizedBox(height: 14),
                _summaryGrid(
                    totalExpense, average, highestCategory, highestAccount),
                const SizedBox(height: 14),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('支出趋势',
                              style: TextStyle(
                                  fontSize: 15, fontWeight: FontWeight.w800)),
                          const SizedBox(height: 4),
                          Text(
                              '${_formatDate(range.start)} - ${_formatDate(range.end)} · 按${period == StatsPeriod.day ? '小时' : '天'}统计',
                              style: const TextStyle(
                                  color: Color(0xFF87958F), fontSize: 10)),
                          const SizedBox(height: 14),
                          if (points.every((point) => point.expense == 0))
                            const Text('当前时段还没有支出',
                                style: TextStyle(
                                    color: Color(0xFF87958F), fontSize: 12))
                          else
                            WealthLineChart(
                                values: points
                                    .map((point) => point.expense)
                                    .toList()),
                          if (points.any((point) => point.expense > 0))
                            _legend(
                                '支出', totalExpense, const Color(0xFFC77C3E)),
                        ]),
                  ),
                ),
                const SizedBox(height: 14),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('分类支出柱状图',
                              style: TextStyle(
                                  fontSize: 15, fontWeight: FontWeight.w800)),
                          const SizedBox(height: 4),
                          const Text('金额越长，代表本时段占用越多',
                              style: TextStyle(
                                  color: Color(0xFF87958F), fontSize: 10)),
                          const SizedBox(height: 15),
                          SpendingBarChart(items: categories),
                        ]),
                  ),
                ),
                const SizedBox(height: 14),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('分类占比',
                              style: TextStyle(
                                  fontSize: 15, fontWeight: FontWeight.w800)),
                          const SizedBox(height: 15),
                          if (categories.isEmpty)
                            const Text('当前时段还没有可统计的支出',
                                style: TextStyle(
                                    color: Color(0xFF87958F), fontSize: 12))
                          else
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                ExpensePieChart(
                                    items: categories
                                        .map((item) => PieChartItem(
                                            label: item.label,
                                            value: item.value,
                                            color: item.color))
                                        .toList()),
                                const SizedBox(width: 16),
                                Expanded(
                                    child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                      for (final item in categories)
                                        _pieLegend(item, totalExpense)
                                    ])),
                              ],
                            ),
                        ]),
                  ),
                ),
                if (widget.store.metrics.pendingConversionCount > 0) ...[
                  const SizedBox(height: 12),
                  const Text('有外币账目缺少可靠汇率，已从人民币统计中暂时排除。',
                      style: TextStyle(color: Color(0xFFB65B55), fontSize: 11)),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _summaryGrid(double expense, double average, String highestCategory,
      String highestAccount) {
    return LayoutBuilder(builder: (context, constraints) {
      final width = (constraints.maxWidth - 12) / 2;
      return Wrap(spacing: 12, runSpacing: 12, children: [
        _summaryCard(width, '总支出', money(expense), Icons.north_east_rounded),
        _summaryCard(width, '日均支出', money(average), Icons.today_outlined),
        _summaryCard(width, '最高分类', highestCategory, Icons.category_outlined),
        _summaryCard(
            width,
            '最高支付账户',
            accountName(widget.store.state, highestAccount),
            Icons.account_balance_wallet_outlined),
      ]);
    });
  }

  Widget _summaryCard(double width, String label, String value, IconData icon) {
    return SizedBox(
      width: width,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(15),
          child: Row(
            children: [
              Icon(icon, size: 17, color: const Color(0xFF2F9F7D)),
              const SizedBox(width: 10),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text(label,
                        style: const TextStyle(
                            color: Color(0xFF87958F), fontSize: 10)),
                    const SizedBox(height: 5),
                    Text(value,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w800))
                  ])),
            ],
          ),
        ),
      ),
    );
  }

  Widget _pieLegend(BarChartItem item, double total) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Container(
              width: 8,
              height: 8,
              decoration:
                  BoxDecoration(color: item.color, shape: BoxShape.circle)),
          const SizedBox(width: 6),
          Expanded(
              child: Text(item.label,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11))),
          Text('${(item.value / total * 100).round()}%',
              style:
                  const TextStyle(fontSize: 11, fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }

  List<BarChartItem> _sortedCategoryItems(Map<String, double> values) {
    final entries = values.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final top = entries.take(6).toList();
    final other =
        entries.skip(6).fold<double>(0, (sum, item) => sum + item.value);
    if (other > 0) top.add(MapEntry('other', other));
    const colors = [
      Color(0xFF2F9F7D),
      Color(0xFF6A6CF4),
      Color(0xFFE79E6C),
      Color(0xFF5AA9A0),
      Color(0xFFB87DC4),
      Color(0xFFC18B27),
      Color(0xFF9AA7A0)
    ];
    return [
      for (var index = 0; index < top.length; index += 1)
        BarChartItem(
            label: top[index].key == 'uncategorized'
                ? '未分类'
                : top[index].key == 'other'
                    ? '其他'
                    : categoryName(widget.store.state, top[index].key),
            value: top[index].value,
            color: colors[index % colors.length])
    ];
  }

  DateTimeRange _rangeFor(StatsPeriod selected, String monthKey) {
    final now = DateTime.now();
    if (selected == StatsPeriod.day)
      return DateTimeRange(
          start: DateTime(now.year, now.month, now.day),
          end: DateTime(now.year, now.month, now.day));
    if (selected == StatsPeriod.week) {
      final monday = DateTime(now.year, now.month, now.day)
          .subtract(Duration(days: now.weekday - 1));
      return DateTimeRange(
          start: monday, end: monday.add(const Duration(days: 6)));
    }
    final parsed = DateTime.tryParse('$monthKey-01') ?? now;
    final first = DateTime(parsed.year, parsed.month, 1);
    return DateTimeRange(
        start: first, end: DateTime(parsed.year, parsed.month + 1, 0));
  }

  String _periodLabel(StatsPeriod value) => switch (value) {
        StatsPeriod.day => '本日',
        StatsPeriod.week => '本周',
        StatsPeriod.month => '本月'
      };

  String _formatDate(DateTime value) => '${value.month}/${value.day}';

  Widget _legend(String label, double value, Color color) => Row(children: [
        Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text('$label ${money(value)}',
            style: const TextStyle(color: Color(0xFF6C7C74), fontSize: 10))
      ]);
}
