import 'dart:math' as math;

import 'package:flutter/material.dart';

class PieChartItem {
  const PieChartItem(
      {required this.label, required this.value, required this.color});

  final String label;
  final double value;
  final Color color;
}

class ExpensePieChart extends StatelessWidget {
  const ExpensePieChart({required this.items, this.onTap, super.key});

  final List<PieChartItem> items;
  final ValueChanged<int>? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
        onTapUp: onTap == null
            ? null
            : (details) {
                final point = details.localPosition - const Offset(75, 75);
                var angle = (math.atan2(point.dy, point.dx) + math.pi / 2) %
                    (math.pi * 2);
                final total = items.fold<double>(0, (s, i) => s + i.value);
                if (total <= 0) return;
                for (var i = 0; i < items.length; i++) {
                  final sweep = items[i].value / total * math.pi * 2;
                  if (angle <= sweep) {
                    onTap!(i);
                    return;
                  }
                  angle -= sweep;
                }
              },
        child: RepaintBoundary(
            child: SizedBox(
                width: 150,
                height: 150,
                child: CustomPaint(painter: _PiePainter(items)))));
  }
}

class _PiePainter extends CustomPainter {
  _PiePainter(this.items);

  final List<PieChartItem> items;

  @override
  void paint(Canvas canvas, Size size) {
    final total = items.fold<double>(0, (sum, item) => sum + item.value);
    if (total <= 0) return;
    final rect = Offset.zero & size;
    var start = -math.pi / 2;
    for (final item in items) {
      final sweep = item.value / total * math.pi * 2;
      canvas.drawArc(
          rect.deflate(3), start, sweep, true, Paint()..color = item.color);
      start += sweep;
    }
    canvas.drawCircle(size.center(Offset.zero), size.shortestSide * .23,
        Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(covariant _PiePainter oldDelegate) =>
      oldDelegate.items != items;
}
