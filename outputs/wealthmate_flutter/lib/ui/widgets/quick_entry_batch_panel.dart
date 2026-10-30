import 'package:flutter/material.dart';

import '../../domain/models.dart';
import '../../features/quick_entry/domain/quick_entry_batch.dart';
import '../../features/quick_entry/domain/quick_entry_rules.dart';
import '../../features/quick_entry/domain/quick_entry_stream.dart';
import '../../features/quick_entry/state/quick_entry_store.dart';
import '../theme.dart';
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
        if (batch == null) {
          if (!store.isStreamLocked && store.preview == null) {
            return const SizedBox.shrink();
          }
          return _streamingCard(context);
        }
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

  /// 生成中：只读预览。没有骨架、没有闪光、没有百分比 —— 只呈现已经到达的
  /// 完整事项；确认与编辑在 completed 通过整批校验前一律不出现。
  Widget _streamingCard(BuildContext context) {
    final preview = store.preview;
    final phase = store.streamPhase;
    final items = preview?.items ?? const <QuickEntryPreviewItem>[];
    final reference = preview?.reference;
    final quote = preview?.sourceText ?? store.sourceText ?? '';
    final reducedMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(15),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
                width: 6,
                height: 6,
                decoration: const BoxDecoration(
                    color: paAi, shape: BoxShape.circle)),
            const SizedBox(width: 7),
            Flexible(
              child: Text('随口记 · ${phase.label}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: paInk, fontSize: 12, fontWeight: FontWeight.w700)),
            ),
            const SizedBox(width: 8),
            const Text('识别中 · 预览',
                style: TextStyle(color: paInkFaint, fontSize: 10.5)),
          ]),
          if (quote.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text('「$quote」',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: paInkFaint,
                    fontSize: 11,
                    fontStyle: FontStyle.italic)),
          ],
          if (items.isEmpty && reference == null) ...[
            const SizedBox(height: 12),
            const Text('正在从原话里整理事项…',
                style: TextStyle(color: paInkFaint, fontSize: 11)),
          ] else ...[
            const SizedBox(height: 4),
            _StreamingPreviewList(
              items: items,
              reference: reference,
              reducedMotion: reducedMotion,
            ),
          ],
          const SizedBox(height: 8),
          Row(children: [
            const Expanded(
              child: Text('整理完成后可确认',
                  style: TextStyle(color: paInkFaint, fontSize: 10)),
            ),
            TextButton(
              key: const Key('quick-entry-stream-cancel'),
              onPressed: store.cancelStream,
              style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: const Size(0, 30),
                  foregroundColor: paInkSub),
              child: const Text('取消', style: TextStyle(fontSize: 11)),
            ),
          ]),
        ]),
      ),
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

/// 生成中的逐项预览列表。只在用户本来就在底部时跟随；否则累计“新增 N 项”，
/// 不把视线反复拉走（v2 §9）。
class _StreamingPreviewList extends StatefulWidget {
  const _StreamingPreviewList({
    required this.items,
    required this.reference,
    required this.reducedMotion,
  });

  final List<QuickEntryPreviewItem> items;
  final QuickEntryPreviewReference? reference;
  final bool reducedMotion;

  @override
  State<_StreamingPreviewList> createState() => _StreamingPreviewListState();
}

class _StreamingPreviewListState extends State<_StreamingPreviewList> {
  final ScrollController _controller = ScrollController();
  int _pending = 0;
  int _seen = 0;

  @override
  void initState() {
    super.initState();
    _seen = widget.items.length;
  }

  @override
  void didUpdateWidget(covariant _StreamingPreviewList oldWidget) {
    super.didUpdateWidget(oldWidget);
    final added = widget.items.length - _seen;
    _seen = widget.items.length;
    if (added <= 0) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_isAtBottom) {
        _scrollToBottom();
      } else {
        setState(() => _pending += added);
      }
    });
  }

  bool get _isAtBottom {
    if (!_controller.hasClients) return true;
    final position = _controller.position;
    return position.maxScrollExtent - position.pixels <= 24;
  }

  void _scrollToBottom() {
    if (!mounted) return;
    setState(() => _pending = 0);
    if (!_controller.hasClients) return;
    final target = _controller.position.maxScrollExtent;
    if (widget.reducedMotion) {
      _controller.jumpTo(target);
    } else {
      _controller.animateTo(target,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[
      for (final item in widget.items)
        _FadeSlideIn(
          key: ValueKey<String>(item.previewId),
          animate: !widget.reducedMotion,
          child: _PreviewRow(item: item),
        ),
      if (widget.reference != null)
        _FadeSlideIn(
          key: const ValueKey<String>('reference'),
          animate: !widget.reducedMotion,
          child: _PreviewReferenceRow(reference: widget.reference!),
        ),
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 320),
        child: ListView(
          shrinkWrap: true,
          controller: _controller,
          padding: EdgeInsets.zero,
          children: rows,
        ),
      ),
      if (_pending > 0)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: GestureDetector(
            onTap: _scrollToBottom,
            child: Text('新增 $_pending 项 ↓',
                style: const TextStyle(
                    color: paAi, fontSize: 10.5, fontWeight: FontWeight.w600)),
          ),
        ),
    ]);
  }
}

class _PreviewRow extends StatelessWidget {
  const _PreviewRow({required this.item});

  final QuickEntryPreviewItem item;

  @override
  Widget build(BuildContext context) {
    final meta = [item.categoryHint ?? '分类待核对', item.date].join(' · ');
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: paHairline)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 22,
          height: 22,
          alignment: Alignment.center,
          decoration: BoxDecoration(
              border: Border.all(color: paHairline), shape: BoxShape.circle),
          child: Text('${item.ordinal + 1}',
              style: const TextStyle(color: paInkSub, fontSize: 10.5)),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(item.note.isEmpty ? '未命名事项' : item.note,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: paInk, fontSize: 13.5, fontWeight: FontWeight.w600)),
            const SizedBox(height: 2),
            Text(meta,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: paInkFaint, fontSize: 10.5)),
            if (item.quote.isNotEmpty) ...[
              const SizedBox(height: 3),
              Text('「${item.quote}」',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: paInkFaint,
                    fontSize: 10,
                    decoration: TextDecoration.underline,
                    decorationStyle: TextDecorationStyle.dotted,
                    decorationColor: paHairline,
                  )),
            ],
          ]),
        ),
        const SizedBox(width: 10),
        _amount(),
      ]),
    );
  }

  /// A missing amount stays missing: previews never invent a number.
  Widget _amount() {
    final value = item.amount;
    if (value == null) {
      return const Text('金额待补',
          style: TextStyle(color: paInkFaint, fontSize: 12));
    }
    return Text(
      '${item.isApproximate ? '≈' : ''}${item.isIncome ? '+' : '-'}${money(value)}',
      style: const TextStyle(
        color: paInk,
        fontSize: 15,
        fontWeight: FontWeight.w600,
        fontFeatures: paTabularFigures,
      ),
    );
  }
}

class _PreviewReferenceRow extends StatelessWidget {
  const _PreviewReferenceRow({required this.reference});

  final QuickEntryPreviewReference reference;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: paHairline)),
      ),
      child: Row(children: [
        const Icon(Icons.history, size: 15, color: paInkFaint),
        const SizedBox(width: 8),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('检测到昨日参照，等待核算',
                style: TextStyle(color: paInkSub, fontSize: 11.5)),
            const SizedBox(height: 2),
            Text('「${reference.quote}」',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: paInkFaint, fontSize: 10)),
          ]),
        ),
      ]),
    );
  }
}

/// 240ms 渐显 + 轻微上移；系统减弱动效时直接切换。
class _FadeSlideIn extends StatelessWidget {
  const _FadeSlideIn({required this.child, required this.animate, super.key});

  final Widget child;
  final bool animate;

  @override
  Widget build(BuildContext context) {
    if (!animate) return child;
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) => Opacity(
        opacity: value,
        child: Transform.translate(
            offset: Offset(0, 6 * (1 - value)), child: child),
      ),
      child: child,
    );
  }
}
