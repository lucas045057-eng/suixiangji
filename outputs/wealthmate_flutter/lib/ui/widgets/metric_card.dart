import 'package:flutter/material.dart';

import '../theme.dart';
import 'ui_helpers.dart';

/// 白卡 + 发丝线，数字用碳黑 w300 等宽；只有语义色（收入/正向）允许点缀。
class MetricCard extends StatelessWidget {
  const MetricCard(
      {required this.label,
      required this.value,
      required this.icon,
      this.caption,
      this.positive = false,
      super.key});

  final String label;
  final double value;
  final IconData icon;
  final String? caption;
  final bool positive;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Flexible(
                child: Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: paSectionLabel.copyWith(letterSpacing: 2))),
            Icon(icon, size: 15, color: paInkFaint),
          ]),
          const SizedBox(height: 14),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(money(value),
                style: const TextStyle(
                    color: paInk,
                    fontSize: 22,
                    fontWeight: FontWeight.w300,
                    letterSpacing: -.5,
                    fontFeatures: paTabularFigures)),
          ),
          if (caption != null) ...[
            const SizedBox(height: 6),
            Text(caption!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: positive ? paIncome : paInkFaint,
                    fontSize: 10,
                    fontWeight: FontWeight.w500)),
          ],
        ]),
      ),
    );
  }
}
