import 'package:flutter/material.dart';

import '../../domain/models.dart';
import 'ui_helpers.dart';

class ProgressRow extends StatelessWidget {
  const ProgressRow(
      {required this.progress, required this.category, this.onTap, super.key});

  final BudgetProgress progress;
  final String category;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final color = progress.status == BudgetStatus.over
        ? const Color(0xFFB65B55)
        : progress.status == BudgetStatus.warning
            ? const Color(0xFFC18B27)
            : const Color(0xFF2F9F7D);
    final status = progress.status == BudgetStatus.over
        ? '已超支'
        : progress.status == BudgetStatus.warning
            ? '接近上限'
            : '进行中';
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 17),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text(category,
                style:
                    const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
            Text('${money(progress.spent)} / ${money(progress.budget.limit)}',
                style: const TextStyle(color: Color(0xFF6C7C74), fontSize: 10)),
          ]),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: LinearProgressIndicator(
                value: progress.ratio.clamp(0, 1).toDouble(),
                minHeight: 7,
                color: color,
                backgroundColor: const Color(0xFFEDF2EE)),
          ),
          const SizedBox(height: 6),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text(
                progress.status == BudgetStatus.over
                    ? '超出 ${money(progress.spent - progress.budget.limit)}'
                    : '剩余 ${money((progress.budget.limit - progress.spent).clamp(0, double.infinity).toDouble())}',
                style: const TextStyle(color: Color(0xFF87958F), fontSize: 10)),
            Text(progress.ratio == 1 ? '已用完' : status,
                style: TextStyle(
                    color: color, fontSize: 10, fontWeight: FontWeight.w700)),
          ]),
        ]),
      ),
    );
  }
}
