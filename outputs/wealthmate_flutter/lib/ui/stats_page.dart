import 'package:flutter/material.dart';

import '../features/insights/state/insights_store.dart';
import '../features/ledger/state/ledger_store.dart';
import '../domain/models.dart';
import '../domain/transaction_query.dart';
import 'ledger_page.dart';
import 'widgets/bar_chart.dart';
import 'widgets/line_chart.dart';
import 'widgets/pie_chart.dart';
import 'widgets/ui_helpers.dart';

enum StatsPeriod { day, week, month, custom }

class StatsPage extends StatefulWidget {
  const StatsPage({required this.insights, this.ledger, this.now, super.key});

  final InsightsStore insights;
  final LedgerStore? ledger;
  final DateTime? now;

  @override
  State<StatsPage> createState() => _StatsPageState();
}

class _StatsPageState extends State<StatsPage> {
  StatsPeriod period = StatsPeriod.month;
  bool byAccount = false;
  int chart = 0;
  DateTimeRange? customRange;
  DateTime get today => day(widget.now ?? DateTime.now());

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.insights,
      builder: (context, _) {
        final selectedRange =
            _rangeFor(period, widget.insights.metrics.monthKey);
        final range = selectedRange;
        final points = widget.insights.trend(range);
        final categoryTotals = widget.insights.expenseByCategory(range);
        final accountTotals = widget.insights.expenseByAccount(range);
        final categories =
            _sortedCategoryItems(byAccount ? accountTotals : categoryTotals);
        final totalExpense =
            categoryTotals.values.fold<double>(0, (sum, value) => sum + value);
        final highestCategory =
            categories.isEmpty ? '暂无' : categories.first.label;
        final highestAccount = accountTotals.isEmpty
            ? '暂无'
            : accountTotals.entries
                .reduce((a, b) => a.value >= b.value ? a : b)
                .key;
        final elapsedExpense = knownTotal(TransactionQuery(
                start: range.start,
                end: range.end.isAfter(today) ? today : range.end,
                type: TransactionType.expense)
            .select(widget.insights.state));
        final average = dailyAverage(
            elapsedExpense, selectedRange.start, selectedRange.end, today);
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
                SegmentedButton<StatsPeriod>(segments: const [
                  ButtonSegment(value: StatsPeriod.day, label: Text('本日')),
                  ButtonSegment(value: StatsPeriod.week, label: Text('本周')),
                  ButtonSegment(value: StatsPeriod.month, label: Text('本月')),
                  ButtonSegment(value: StatsPeriod.custom, label: Text('自选')),
                ], selected: {
                  period
                }, onSelectionChanged: (value) => _selectPeriod(value.first)),
                if (period == StatsPeriod.month)
                  Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    IconButton(
                        tooltip: '上个月',
                        onPressed: () => _changeMonth(-1),
                        icon: const Icon(Icons.chevron_left)),
                    Text(widget.insights.monthKey),
                    IconButton(
                        tooltip: '下个月',
                        onPressed: () => _changeMonth(1),
                        icon: const Icon(Icons.chevron_right)),
                  ]),
                Text(
                    '日均仅计截至今日的账目，按已过去的 ${averageDays(selectedRange.start, selectedRange.end, today)} 天计算；历史月份按整月计算。',
                    style: const TextStyle(fontSize: 10)),
                const SizedBox(height: 10),
                SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(value: false, label: Text('按分类')),
                      ButtonSegment(value: true, label: Text('按账户'))
                    ],
                    selected: {
                      byAccount
                    },
                    onSelectionChanged: (value) =>
                        setState(() => byAccount = value.first)),
                const SizedBox(height: 14),
                _summaryGrid(
                    totalExpense, average, highestCategory, highestAccount),
                const SizedBox(height: 14),
                SegmentedButton<int>(
                    segments: const [
                      ButtonSegment(value: 0, label: Text('趋势')),
                      ButtonSegment(value: 1, label: Text('柱状')),
                      ButtonSegment(value: 2, label: Text('占比')),
                    ],
                    selected: {
                      chart
                    },
                    onSelectionChanged: (value) =>
                        setState(() => chart = value.first)),
                const SizedBox(height: 12),
                if (chart == 0)
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
                if (chart == 1)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(byAccount ? '账户支出柱状图' : '分类支出柱状图',
                                style: const TextStyle(
                                    fontSize: 15, fontWeight: FontWeight.w800)),
                            const SizedBox(height: 4),
                            const Text('金额越长，代表本时段占用越多',
                                style: TextStyle(
                                    color: Color(0xFF87958F), fontSize: 10)),
                            const SizedBox(height: 15),
                            SpendingBarChart(
                                items: categories,
                                onTap: (item) => _drill(item, range)),
                          ]),
                    ),
                  ),
                const SizedBox(height: 14),
                if (chart == 2)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(byAccount ? '账户占比' : '分类占比',
                                style: const TextStyle(
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
                                      onTap: (index) =>
                                          _drill(categories[index], range),
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
                                          InkWell(
                                              onTap: () => _drill(item, range),
                                              child: _pieLegend(
                                                  item, totalExpense))
                                      ])),
                                ],
                              ),
                          ]),
                    ),
                  ),
                if (widget.insights.metrics.pendingConversionCount > 0) ...[
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
            accountName(widget.insights.state, highestAccount),
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
    final top = entries;
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
            id: top[index].key,
            label: byAccount
                ? accountName(widget.insights.state, top[index].key)
                : top[index].key == 'uncategorized'
                    ? '未分类'
                    : top[index].key == 'other'
                        ? '其他'
                        : categoryName(widget.insights.state, top[index].key),
            value: top[index].value,
            color: colors[index % colors.length])
    ];
  }

  DateTimeRange _rangeFor(StatsPeriod selected, String monthKey) {
    final now = today;
    if (selected == StatsPeriod.custom && customRange != null)
      return customRange!;
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
        StatsPeriod.month => '本月',
        StatsPeriod.custom => '自选时段'
      };

  Future<void> _changeMonth(int delta) async {
    final current = DateTime.parse('${widget.insights.monthKey}-01');
    final next = DateTime(current.year, current.month + delta, 1);
    await widget.insights.refresh(
        month: '${next.year}-${next.month.toString().padLeft(2, '0')}');
  }

  Future<void> _selectPeriod(StatsPeriod value) async {
    if (value == StatsPeriod.custom) {
      final selected = await showDateRangePicker(
          context: context,
          firstDate: DateTime(2000),
          lastDate: DateTime(2100),
          initialDateRange: customRange);
      if (selected == null || !mounted) return;
      customRange = selected;
    }
    setState(() => period = value);
  }

  void _drill(BarChartItem item, DateTimeRange range) {
    final ledger = widget.ledger;
    if (ledger == null) return;
    Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => Scaffold(
            appBar: AppBar(title: Text('${item.label} · 支出明细')),
            body: LedgerPage(
                ledger: ledger,
                initialQuery: TransactionQuery(
                    start: range.start,
                    end: range.end,
                    type: TransactionType.expense,
                    categoryIds: byAccount ? null : {item.id!},
                    accountId: byAccount ? item.id : null)))));
  }

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
