import 'package:flutter/material.dart';

import '../../domain/finance_rules.dart';
import '../../domain/models.dart';
import '../theme.dart';
import 'ui_helpers.dart';

/// 待确认草稿：白卡发丝线，橄榄色只留给 AI 标识，确认是碳黑胶囊。
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
    final income = draft.type == TransactionType.income;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(15),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
                width: 5,
                height: 5,
                decoration: const BoxDecoration(
                    color: paAi, shape: BoxShape.circle)),
            const SizedBox(width: 8),
            const Text('已整理成待确认草稿',
                style: TextStyle(
                    color: paAi,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: .6)),
            const Spacer(),
            Text('置信度 ${(draft.confidence * 100).round()}%',
                style: TextStyle(
                    color: canPost ? paIncome : paWarn,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    fontFeatures: paTabularFigures)),
          ]),
          const SizedBox(height: 14),
          Text('${income ? '+' : '-'}${money(draft.amount)}',
              style: TextStyle(
                  color: income ? paIncome : paInk,
                  fontSize: 28,
                  fontWeight: FontWeight.w300,
                  letterSpacing: -.6,
                  fontFeatures: paTabularFigures)),
          const SizedBox(height: 6),
          Text(
              '${categoryName(state, draft.categoryId)} · ${accountName(state, draft.accountId)} · ${draft.date}',
              style: const TextStyle(color: paInkFaint, fontSize: 11)),
          if (draft.missingFacts.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text('待确认：${draft.missingFacts.join('、')}',
                style: const TextStyle(
                    color: paWarn,
                    fontSize: 11,
                    fontWeight: FontWeight.w600)),
          ],
          const SizedBox(height: 14),
          Row(children: [
            Expanded(
                child: OutlinedButton(
                    onPressed: onEdit,
                    style: OutlinedButton.styleFrom(
                        foregroundColor: paInk,
                        side: const BorderSide(color: paHairline),
                        shape: const StadiumBorder()),
                    child: const Text('修改'))),
            const SizedBox(width: 10),
            Expanded(
                child: FilledButton(
                    onPressed: canPost ? onConfirm : null,
                    style: FilledButton.styleFrom(
                        backgroundColor: paInk,
                        foregroundColor: Colors.white,
                        shape: const StadiumBorder()),
                    child: Text(canPost ? '确认入账' : '补全后确认'))),
          ]),
        ]),
      ),
    );
  }
}
