import 'package:flutter/material.dart';

import 'ui_helpers.dart';

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
        padding: const EdgeInsets.all(18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text(label,
                style: const TextStyle(
                    color: Color(0xFF6C7C74),
                    fontSize: 11,
                    fontWeight: FontWeight.w700)),
            CircleAvatar(
                radius: 15,
                backgroundColor: positive
                    ? const Color(0xFFE6F6EF)
                    : const Color(0xFFF0EEFF),
                child: Icon(icon,
                    size: 16,
                    color: positive
                        ? const Color(0xFF2F9F7D)
                        : const Color(0xFF6A6CF4))),
          ]),
          const SizedBox(height: 15),
          Text(money(value),
              style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -.5)),
          if (caption != null) ...[
            const SizedBox(height: 6),
            Text(caption!,
                style: TextStyle(
                    color: positive
                        ? const Color(0xFF2F9F7D)
                        : const Color(0xFF87958F),
                    fontSize: 10,
                    fontWeight: FontWeight.w600)),
          ],
        ]),
      ),
    );
  }
}
