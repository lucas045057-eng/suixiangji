import 'package:flutter/material.dart';

import '../../domain/models.dart';
import '../theme.dart';
import 'ui_helpers.dart';

/// 预算行：发丝槽底 + 炭黑条面；只有超支才动用警示色。
class ProgressRow extends StatelessWidget {
  const ProgressRow(
      {required this.progress, required this.category, this.onTap, super.key});

  final BudgetProgress progress;
  final String category;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final over = progress.status == BudgetStatus.over;
    final color = over ? paWarn : paInk;
    final status = over
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
                style: const TextStyle(
                    color: paInk, fontSize: 12, fontWeight: FontWeight.w600)),
            Text('${money(progress.spent)} / ${money(progress.budget.limit)}',
                style: const TextStyle(
                    color: paInkSub,
                    fontSize: 10,
                    fontFeatures: paTabularFigures)),
          ]),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: LinearProgressIndicator(
                value: progress.ratio.clamp(0, 1).toDouble(),
                minHeight: 6,
                color: color,
                backgroundColor: paHairline),
          ),
          const SizedBox(height: 6),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text(
                over
                    ? '超出 ${money(progress.spent - progress.budget.limit)}'
                    : '剩余 ${money((progress.budget.limit - progress.spent).clamp(0, double.infinity).toDouble())}',
                style: const TextStyle(
                    color: paInkFaint,
                    fontSize: 10,
                    fontFeatures: paTabularFigures)),
            Text(progress.ratio == 1 ? '已用完' : status,
                style: TextStyle(
                    color: over ? paWarn : paInkSub,
                    fontSize: 10,
                    fontWeight: FontWeight.w600)),
          ]),
        ]),
      ),
    );
  }
}
