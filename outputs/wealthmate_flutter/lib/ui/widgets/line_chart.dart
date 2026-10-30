import 'package:flutter/material.dart';

import '../theme.dart';

class WealthLineChart extends StatelessWidget {
  const WealthLineChart({required this.values, super.key});

  final List<double> values;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
        height: 170,
        child: CustomPaint(
            painter: _LineChartPainter(values),
            child: const SizedBox.expand()));
  }
}

class _LineChartPainter extends CustomPainter {
  _LineChartPainter(this.values);

  final List<double> values;

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = paHairline
      ..strokeWidth = 1;
    for (var row = 1; row < 4; row += 1) {
      final y = size.height * row / 4;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }
    if (values.length < 2) return;
    final min = values.reduce((a, b) => a < b ? a : b);
    final max = values.reduce((a, b) => a > b ? a : b);
    final span = max - min == 0 ? 1 : max - min;
    final points = <Offset>[];
    for (var index = 0; index < values.length; index += 1) {
      final x = size.width * index / (values.length - 1);
      final y = size.height -
          ((values[index] - min) / span * (size.height - 24)) -
          12;
      points.add(Offset(x, y));
    }
    final line = Paint()
      ..color = paInk
      ..strokeWidth = 1.8
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (final point in points.skip(1)) {
      path.lineTo(point.dx, point.dy);
    }
    canvas.drawPath(path, line);
    final dot = Paint()
      ..color = paSurface
      ..style = PaintingStyle.fill;
    final ring = Paint()
      ..color = paInk
      ..strokeWidth = 1.4
      ..style = PaintingStyle.stroke;
    for (final point in points) {
      canvas.drawCircle(point, 3, dot);
      canvas.drawCircle(point, 3, ring);
    }
  }

  @override
  bool shouldRepaint(covariant _LineChartPainter oldDelegate) =>
      oldDelegate.values != values;
}
