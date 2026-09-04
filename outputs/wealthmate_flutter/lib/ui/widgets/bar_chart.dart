import 'package:flutter/material.dart';

class BarChartItem {
  const BarChartItem(
      {required this.label,
      required this.value,
      this.color = const Color(0xFF2F9F7D)});

  final String label;
  final double value;
  final Color color;
}

class SpendingBarChart extends StatelessWidget {
  const SpendingBarChart({required this.items, super.key});

  final List<BarChartItem> items;

  @override
  Widget build(BuildContext context) {
    final maxValue = items.fold<double>(
        0, (max, item) => item.value > max ? item.value : max);
    if (items.isEmpty || maxValue <= 0)
      return const SizedBox(
          height: 24,
          child: Text('暂无可展示的分类支出',
              style: TextStyle(color: Color(0xFF87958F), fontSize: 11)));
    return RepaintBoundary(
      child: Column(
        children: [
          for (final item in items)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  SizedBox(
                      width: 64,
                      child: Text(item.label,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 11, fontWeight: FontWeight.w700))),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(5),
                      child: LinearProgressIndicator(
                          value: item.value / maxValue,
                          minHeight: 12,
                          color: item.color,
                          backgroundColor: const Color(0xFFEDF2EE)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                      width: 62,
                      child: Text('¥${item.value.toStringAsFixed(0)}',
                          textAlign: TextAlign.right,
                          style: const TextStyle(
                              fontSize: 10, fontWeight: FontWeight.w800))),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
