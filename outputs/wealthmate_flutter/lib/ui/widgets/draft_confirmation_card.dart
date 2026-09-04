import 'package:flutter/material.dart';

import '../../domain/finance_rules.dart';
import '../../domain/models.dart';
import 'ui_helpers.dart';

class DraftConfirmationCard extends StatelessWidget {
  const DraftConfirmationCard(
      {required this.draft,
      required this.state,
      required this.onConfirm,
      required this.onEdit,
      super.key});

  final AgentDraft draft;
  final FinanceState state;
  final Future<void> Function() onConfirm;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final canPost = FinanceRules.canPostDraft(draft);
    return Card(
      color: const Color(0xFFF7F6FF),
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: Color(0xFFE2E0FF))),
      child: Padding(
        padding: const EdgeInsets.all(15),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.auto_awesome, color: Color(0xFF4C4A9C), size: 16),
            const SizedBox(width: 7),
            const Text('已整理成待确认草稿',
                style: TextStyle(
                    color: Color(0xFF4C4A9C),
                    fontSize: 11,
                    fontWeight: FontWeight.w800)),
            const Spacer(),
            Text('置信度 ${(draft.confidence * 100).round()}%',
                style: TextStyle(
                    color: canPost
                        ? const Color(0xFF2F9F7D)
                        : const Color(0xFFC18B27),
                    fontSize: 10,
                    fontWeight: FontWeight.w700)),
          ]),
          const SizedBox(height: 14),
          Text(
              '${draft.type == TransactionType.income ? '+' : '-'}${money(draft.amount)}',
              style:
                  const TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
          const SizedBox(height: 5),
          Text(
              '${categoryName(state, draft.categoryId)} · ${accountName(state, draft.accountId)} · ${draft.date}',
              style: const TextStyle(color: Color(0xFF6C6B97), fontSize: 11)),
          if (draft.missingFacts.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text('待确认：${draft.missingFacts.join('、')}',
                style: const TextStyle(
                    color: Color(0xFFC18B27),
                    fontSize: 11,
                    fontWeight: FontWeight.w700)),
          ],
          const SizedBox(height: 14),
          Row(children: [
            Expanded(
                child: OutlinedButton(
                    onPressed: onEdit, child: const Text('修改'))),
            const SizedBox(width: 10),
            Expanded(
                child: FilledButton(
                    onPressed: canPost ? onConfirm : null,
                    child: Text(canPost ? '确认入账' : '补全后确认'))),
          ]),
        ]),
      ),
    );
  }
}
