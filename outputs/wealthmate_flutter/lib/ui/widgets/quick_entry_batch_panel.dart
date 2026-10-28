import 'package:flutter/material.dart';

import '../../domain/models.dart';
import '../../features/quick_entry/domain/quick_entry_batch.dart';
import '../../features/quick_entry/domain/quick_entry_rules.dart';
import '../../features/quick_entry/state/quick_entry_store.dart';
import 'draft_editor.dart';
import 'ui_helpers.dart';

/// 随口记 multi-card review panel: compact candidate rows, explicit/approximate/
/// inferred markers, expandable evidence and推导, and one batch confirmation.
class QuickEntryBatchPanel extends StatefulWidget {
  const QuickEntryBatchPanel({
    required this.store,
    required this.state,
    this.onConfirmed,
    super.key,
  });

  final QuickEntryStore store;
  final FinanceState state;
  final VoidCallback? onConfirmed;

  @override
  State<QuickEntryBatchPanel> createState() => _QuickEntryBatchPanelState();
}

class _QuickEntryBatchPanelState extends State<QuickEntryBatchPanel> {
  static const _ink = Color(0xFF1A2621);
  static const _muted = Color(0xFF6C7B74);
  static const _purple = Color(0xFF4C4A9C);
  static const _mint = Color(0xFF2F9F7D);
  static const _amber = Color(0xFFC18B27);

  final Set<String> _expanded = <String>{};

  QuickEntryStore get store => widget.store;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final batch = store.batch;
        if (batch == null) return const SizedBox.shrink();
        return Card(
          color: const Color(0xFFF7F6FF),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: const BorderSide(color: Color(0xFFE2E0FF))),
          child: Padding(
            padding: const EdgeInsets.all(15),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _header(context, batch),
                  const SizedBox(height: 10),
                  for (final notice in batch.notices) _noticeRow(notice),
                  if (batch.candidates.isEmpty)
                    Text(
                      batch.status == QuickEntryBatchStatus.needsSplit
                          ? '内容较多，请分两次说。'
                          : '没有可安全生成的事项，请手动输入。',
                      style: const TextStyle(color: _muted, fontSize: 11),
                    ),
                  for (var index = 0;
                      index < batch.candidates.length;
                      index += 1)
                    _candidateRow(index, batch.candidates[index]),
                  const SizedBox(height: 12),
                  _footer(context, batch),
                ]),
          ),
        );
      },
    );
  }

  Widget _header(BuildContext context, QuickEntryBatch batch) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Icon(batch.isCloud ? Icons.auto_awesome : Icons.offline_bolt_outlined,
            color: _purple, size: 16),
        const SizedBox(width: 7),
        const Text('已整理成待确认草稿',
            style: TextStyle(
                color: _purple, fontSize: 11, fontWeight: FontWeight.w800)),
        const SizedBox(width: 8),
        _badge(batch.isCloud ? '云端 AI' : '本地规则',
            const Color(0xFFEAE8FF), _purple),
        const Spacer(),
        if (store.isParsing)
          const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2)),
      ]),
      if (batch.sourceText.isNotEmpty) ...[
        const SizedBox(height: 6),
        Text('「${batch.sourceText}」',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: _muted, fontSize: 11)),
      ],
    ]);
  }

  Widget _noticeRow(QuickEntryNotice notice) {
    final manualEntry = notice.code == 'reference_unavailable' ||
        notice.code == 'no_actionable_items';
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(children: [
        const Icon(Icons.info_outline, color: _amber, size: 14),
        const SizedBox(width: 6),
        Expanded(
            child: Text(notice.message,
                style: const TextStyle(
                    color: _amber, fontSize: 11, height: 1.4))),
        if (manualEntry)
          TextButton(
            onPressed: () => _manualTotal(context),
            style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                minimumSize: const Size(0, 30),
                foregroundColor: _amber),
            child: const Text('手输今日总额', style: TextStyle(fontSize: 11)),
          ),
      ]),
    );
  }

  Widget _candidateRow(int index, QuickEntryCandidate candidate) {
    final draft = candidate.draft;
    final expanded = _expanded.contains(candidate.id);
    final incomplete = QuickEntryRules.incompleteReason(draft);
    final amountLabel = draft.amount > 0
        ? '${draft.isApproximate ? '≈' : ''}${draft.type == TransactionType.income ? '+' : '-'}${money(draft.amount)}'
        : '金额待填';
    final row = Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.fromLTRB(4, 6, 4, 6),
      decoration: BoxDecoration(
        color: candidate.isInferred ? Colors.transparent : Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          Checkbox(
            value: candidate.selected,
            visualDensity: VisualDensity.compact,
            onChanged: (value) =>
                store.toggleCandidate(candidate.id, value ?? false),
          ),
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    _badge(
                      candidate.isInferred ? '推算' : '明确',
                      candidate.isInferred
                          ? const Color(0xFFF0EEFF)
                          : const Color(0xFFE6F6EF),
                      candidate.isInferred ? _purple : _mint,
                    ),
                    if (draft.isApproximate && !candidate.isInferred) ...[
                      const SizedBox(width: 5),
                      _badge('约', const Color(0xFFFFF3E8), _amber),
                    ],
                    if (candidate.userEdited) ...[
                      const SizedBox(width: 5),
                      _badge('已修改', const Color(0xFFF1F1F1), _muted),
                    ],
                    if (candidate.stale) ...[
                      const SizedBox(width: 5),
                      _badge('账本已变化', const Color(0xFFFFEBE9), Color(0xFFB65B55)),
                    ],
                    const SizedBox(width: 8),
                    Flexible(
                        child: Text(amountLabel,
                            style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                                color: _ink))),
                  ]),
                  const SizedBox(height: 2),
                  Text(
                    [
                      draft.note.isEmpty ? '未命名' : draft.note,
                      categoryName(widget.state, draft.categoryId),
                      accountName(widget.state, draft.accountId),
                      draft.currency,
                      draft.date,
                    ].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: _muted, fontSize: 10),
                  ),
                  if (incomplete != null)
                    Text('待补全：$incomplete',
                        style: const TextStyle(
                            color: _amber,
                            fontSize: 10,
                            fontWeight: FontWeight.w700)),
                ]),
          ),
          IconButton(
            tooltip: '修改',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.edit_outlined, size: 17),
            onPressed: () => _edit(candidate),
          ),
          IconButton(
            tooltip: '删除',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.close, size: 17),
            onPressed: () => store.removeCandidate(candidate.id),
          ),
          IconButton(
            tooltip: expanded ? '收起依据' : '查看依据',
            visualDensity: VisualDensity.compact,
            icon: Icon(
                expanded ? Icons.expand_less : Icons.expand_more,
                size: 18),
            onPressed: () => setState(() {
              if (!_expanded.remove(candidate.id)) _expanded.add(candidate.id);
            }),
          ),
        ]),
        if (expanded) _evidenceBlock(draft),
      ]),
    );
    if (!candidate.isInferred) return row;
    return CustomPaint(
      foregroundPainter: _DashedBorderPainter(
          color: const Color(0xFFB9B5F0), radius: 12),
      child: row,
    );
  }

  Widget _evidenceBlock(AgentDraft draft) {
    final lines = <Widget>[];
    for (final evidence in draft.evidence) {
      lines.add(Text(
        evidence.kind == DraftEvidenceKind.sourceText
            ? '原话：「${evidence.quote ?? ''}」'
            : '依据：昨日已记消费汇总${evidence.referenceDate == null ? '' : '（${evidence.referenceDate}）'}',
        style: const TextStyle(color: _muted, fontSize: 10, height: 1.5),
      ));
    }
    final range = draft.amountRange;
    if (range != null) {
      lines.add(Text(
        '金额区间：¥${range.lower.toStringAsFixed(0)} ~ ¥${range.upper.toStringAsFixed(0)}，按中值约记，可直接改。',
        style: const TextStyle(color: _amber, fontSize: 10, height: 1.5),
      ));
    }
    final derivation = draft.derivation;
    if (derivation != null) {
      lines.add(const Text('推导（基于昨日已记账面，不是实际消费全量）：',
          style: TextStyle(
              color: _purple, fontSize: 10, fontWeight: FontWeight.w700)));
      for (final operand in derivation.operands) {
        lines.add(Text(
          '· ${operand.label}：${operand.isApproximate ? '约 ' : ''}${money(operand.amount)}',
          style: const TextStyle(color: _muted, fontSize: 10, height: 1.5),
        ));
      }
      lines.add(Text('= ${money(derivation.result)}',
          style: const TextStyle(
              color: _purple, fontSize: 10, fontWeight: FontWeight.w800)));
      lines.add(const Text('推算卡默认不勾选，可一键删除或改金额；不确认就不会入账。',
          style: TextStyle(color: _muted, fontSize: 10, height: 1.5)));
    }
    if (lines.isEmpty) {
      lines.add(const Text('这张卡没有可展示的依据。',
          style: TextStyle(color: _muted, fontSize: 10)));
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(40, 6, 8, 2),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: lines),
    );
  }

  Widget _footer(BuildContext context, QuickEntryBatch batch) {
    final selected = store.selectedCandidates;
    final incompleteIndex = store.firstIncompleteSelectedIndex;
    final canConfirm = store.canConfirmBatch;
    return Row(children: [
      TextButton(
        onPressed: batch.candidates.isEmpty ? null : store.selectAllExplicit,
        style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 6)),
        child: const Text('全选明确卡', style: TextStyle(fontSize: 11)),
      ),
      TextButton(
        onPressed: store.clearDraft,
        style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 6)),
        child: const Text('重新输入', style: TextStyle(fontSize: 11)),
      ),
      const Spacer(),
      FilledButton(
        onPressed: canConfirm ? () => _confirm(context) : null,
        child: Text(
          incompleteIndex != null
              ? '第${incompleteIndex + 1}张卡待补全'
              : selected.length > 1
                  ? '确认入账 ${selected.length} 笔'
                  : '确认入账',
          style: const TextStyle(fontSize: 12),
        ),
      ),
    ]);
  }

  Future<void> _confirm(BuildContext context) async {
    final confirmed = await store.confirmBatch();
    if (!confirmed || !context.mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.showSnackBar(
        const SnackBar(content: Text('已保存到本地，随后自动同步')));
    widget.onConfirmed?.call();
  }

  Future<void> _edit(QuickEntryCandidate candidate) async {
    final edited = await showDraftEditor(context,
        draft: candidate.draft, state: widget.state);
    if (edited == null) return;
    store.updateCandidate(candidate.id, edited);
  }

  Future<void> _manualTotal(BuildContext context) async {
    final controller = TextEditingController();
    final amount = await showDialog<double>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('手输今日总额'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: '今日总支出'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('取消')),
          FilledButton(
            onPressed: () => Navigator.pop(
                dialogContext, double.tryParse(controller.text.trim())),
            child: const Text('添加卡片'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (amount == null || amount <= 0) return;
    store.addManualCandidate(amount);
  }

  Widget _badge(String text, Color background, Color foreground) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration:
          BoxDecoration(color: background, borderRadius: BorderRadius.circular(6)),
      child: Text(text,
          style: TextStyle(
              color: foreground, fontSize: 9, fontWeight: FontWeight.w800)),
    );
  }
}

class _DashedBorderPainter extends CustomPainter {
  const _DashedBorderPainter({required this.color, required this.radius});

  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..addRRect(RRect.fromRectAndRadius(
          Offset.zero & size, Radius.circular(radius)));
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final end = (distance + 5).clamp(0.0, metric.length);
        canvas.drawPath(metric.extractPath(distance, end), paint);
        distance = end + 4;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedBorderPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.radius != radius;
}
