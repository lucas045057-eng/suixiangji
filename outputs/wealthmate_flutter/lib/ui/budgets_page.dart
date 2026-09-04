import 'package:flutter/material.dart';

import '../domain/models.dart';
import '../state/finance_store.dart';
import 'widgets/progress_row.dart';
import 'widgets/ui_helpers.dart';

class BudgetsPage extends StatefulWidget {
  const BudgetsPage({required this.store, super.key});

  final FinanceStore store;

  @override
  State<BudgetsPage> createState() => _BudgetsPageState();
}

class _BudgetsPageState extends State<BudgetsPage> {
  @override
  void initState() {
    super.initState();
    Future<void>.microtask(widget.store.checkBudgetAlerts);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('预算'), actions: [
        IconButton(
            onPressed: () => _openBudgetEditor(context),
            tooltip: '新增预算',
            icon: const Icon(Icons.add))
      ]),
      body: ListenableBuilder(
        listenable: widget.store,
        builder: (context, _) {
          final metrics = widget.store.metrics;
          final alerts = metrics.budgetProgress
              .where((item) => item.ratio >= .8)
              .toList(growable: false);
          return ListView(
            padding: const EdgeInsets.fromLTRB(22, 8, 22, 30),
            children: [
              Text('${metrics.monthKey} · 给支出设一个轻量边界',
                  style:
                      const TextStyle(color: Color(0xFF87958F), fontSize: 11)),
              const SizedBox(height: 12),
              for (final item in alerts)
                _alertBanner(item,
                    categoryName(widget.store.state, item.budget.categoryId)),
              if (alerts.isNotEmpty) const SizedBox(height: 6),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      if (metrics.budgetProgress.isEmpty)
                        const Text('还没有预算记录',
                            style: TextStyle(
                                color: Color(0xFF87958F), fontSize: 12)),
                      for (final item in metrics.budgetProgress)
                        ProgressRow(
                            progress: item,
                            category: categoryName(
                                widget.store.state, item.budget.categoryId),
                            onTap: () => _openBudgetEditor(context,
                                existing: item.budget)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              const Text('预算可以随时调整月份、分类和额度。转账不会影响预算。',
                  style: TextStyle(
                      color: Color(0xFF87958F), fontSize: 10, height: 1.5)),
            ],
          );
        },
      ),
    );
  }

  Widget _alertBanner(BudgetProgress progress, String category) {
    final over = progress.ratio > 1;
    final exhausted = progress.ratio == 1;
    final color = over
        ? const Color(0xFFB65B55)
        : exhausted
            ? const Color(0xFFC9783C)
            : const Color(0xFFC18B27);
    final title = over
        ? '注意消费：$category 已超出预算'
        : exhausted
            ? '预算已用完：$category'
            : '预算提醒：$category 已使用 ${(progress.ratio * 100).round()}%';
    final detail = over
        ? '已超出 ${money(progress.spent - progress.budget.limit)}，建议暂停非必要消费。'
        : exhausted
            ? '本月额度已经用完，请留意接下来的支出。'
            : '剩余 ${money(progress.budget.limit - progress.spent)}，接近本月上限。';
    return Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
            color: color.withValues(alpha: .1),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: color.withValues(alpha: .28))),
        child: Row(children: [
          Icon(Icons.notifications_active_outlined, color: color, size: 19),
          const SizedBox(width: 10),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(title,
                    style: TextStyle(
                        color: color,
                        fontSize: 12,
                        fontWeight: FontWeight.w800)),
                const SizedBox(height: 3),
                Text(detail, style: TextStyle(color: color, fontSize: 10))
              ]))
        ]));
  }

  Future<void> _openBudgetEditor(BuildContext context,
      {Budget? existing}) async {
    final categoryId = ValueNotifier<String>(existing?.categoryId ??
        widget.store.activeCategories.firstOrNull?.id ??
        '');
    final monthController = TextEditingController(
        text: existing?.month ?? widget.store.metrics.monthKey);
    final limitController = TextEditingController(
        text: existing == null ? '' : existing.limit.toString());
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(existing == null ? '新增预算' : '编辑预算'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
                controller: monthController,
                decoration: const InputDecoration(
                    labelText: '月份', hintText: 'YYYY-MM')),
            const SizedBox(height: 12),
            ValueListenableBuilder<String>(
                valueListenable: categoryId,
                builder: (_, value, __) => DropdownButtonFormField<String>(
                    initialValue: value.isEmpty ? null : value,
                    decoration: const InputDecoration(labelText: '分类'),
                    items: widget.store.activeCategories
                        .map((item) => DropdownMenuItem(
                            value: item.id, child: Text(item.name)))
                        .toList(),
                    onChanged: (next) => categoryId.value = next ?? value)),
            const SizedBox(height: 12),
            TextField(
                controller: limitController,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration:
                    const InputDecoration(labelText: '月度上限', prefixText: '¥ ')),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () {
                final limit = double.tryParse(limitController.text);
                final month = monthController.text.trim();
                if (categoryId.value.isNotEmpty &&
                    limit != null &&
                    limit > 0 &&
                    RegExp(r'^\d{4}-\d{2}$').hasMatch(month))
                  Navigator.pop(dialogContext, true);
              },
              child: const Text('保存')),
        ],
      ),
    );
    if (saved == true)
      await widget.store.upsertBudget(
          id: existing?.id,
          month: monthController.text.trim(),
          categoryId: categoryId.value,
          limit: double.parse(limitController.text));
    categoryId.dispose();
    monthController.dispose();
    limitController.dispose();
  }
}
