import 'package:flutter/material.dart';

import '../theme.dart';

class BarChartItem {
  const BarChartItem(
      {required this.label,
      this.id,
      required this.value,
      this.color = paInk});

  final String label;
  final String? id;
  final double value;
  final Color color;
}

/// 支出柱：炭黑细柱 + 发丝槽底；点击只加字重，不换颜色。
class SpendingBarChart extends StatelessWidget {
  const SpendingBarChart({required this.items, this.onTap, super.key});

  final List<BarChartItem> items;
  final ValueChanged<BarChartItem>? onTap;

  @override
  Widget build(BuildContext context) {
    final maxValue = items.fold<double>(
        0, (max, item) => item.value > max ? item.value : max);
    if (items.isEmpty || maxValue <= 0)
      return const SizedBox(
          height: 24,
          child: Text('暂无可展示的分类支出',
              style: TextStyle(color: paInkSub, fontSize: 11)));
    return RepaintBoundary(
      child: Column(
        children: [
          for (final item in items)
            InkWell(
                onTap: onTap == null ? null : () => onTap!(item),
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 11),
                  child: Row(
                    children: [
                      SizedBox(
                          width: 64,
                          child: Text(item.label,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  color: paInkSub,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500))),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(3),
                          child: LinearProgressIndicator(
                              value: item.value / maxValue,
                              minHeight: 7,
                              color: paInk,
                              backgroundColor: paHairline),
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                          width: 62,
                          child: Text('¥${item.value.toStringAsFixed(0)}',
                              textAlign: TextAlign.right,
                              style: const TextStyle(
                                  color: paInkSub,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  fontFeatures: paTabularFigures))),
                    ],
                  ),
                )),
        ],
      ),
    );
  }
}
