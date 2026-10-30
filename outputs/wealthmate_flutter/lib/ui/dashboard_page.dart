import 'package:flutter/material.dart';

import '../features/budget/state/budget_store.dart';
import '../features/insights/state/insights_store.dart';
import '../features/ledger/state/ledger_store.dart';
import '../features/quick_entry/state/quick_entry_store.dart';
import '../domain/models.dart';
import 'theme.dart';
import 'widgets/draft_confirmation_card.dart';
import 'widgets/draft_editor.dart';
import 'widgets/quick_entry_batch_panel.dart';
import 'widgets/metric_card.dart';
import 'widgets/progress_row.dart';
import 'widgets/ui_helpers.dart';
import 'transaction_detail_page.dart';

typedef OpenDashboardComposer = void Function(BuildContext context,
    {bool smart});

class DashboardPage extends StatelessWidget {
  const DashboardPage({
    required this.ledger,
    this.insights,
    this.budget,
    this.budgetAlerts = const [],
    this.quickEntry,
    this.draft,
    required this.isDemoMode,
    this.message,
    this.displayName = '朋友',
    this.now,
    this.onSync,
    this.onViewAllTransactions,
    this.onUpdateDraft,
    this.onConfirmDraft,
    required this.openComposer,
    required this.openBudgets,
    super.key,
  });

  final LedgerStore ledger;
  final InsightsStore? insights;
  final BudgetStore? budget;
  final List<BudgetAlert> budgetAlerts;
  final QuickEntryStore? quickEntry;

  /// Compatibility inputs for callers that still compose Dashboard directly
  /// through FinanceStore. The AppShell path uses [quickEntry].
  final AgentDraft? draft;
  final bool isDemoMode;
  final String? message;
  final String displayName;
  final DateTime? now;
  final Future<void> Function()? onSync;
  final VoidCallback? onViewAllTransactions;
  final ValueChanged<AgentDraft>? onUpdateDraft;
  final Future<bool> Function(AgentDraft)? onConfirmDraft;
  final OpenDashboardComposer openComposer;
  final VoidCallback openBudgets;

  String _syncStatus(FinanceState state) {
    final sync = state.syncState;
    if (sync.isSyncing) return '同步中…';
    if (sync.error != null && sync.error != '离线演示/待配置') return '同步失败';
    if (state.conflicts.isNotEmpty) return '有冲突待处理';
    final pending = ledger.repository.queue.pending().length;
    if (pending > 0) return '有 $pending 条待同步数据';
    final last = sync.lastSyncedAt;
    if (last != null) {
      final date = DateTime.tryParse(last)?.toLocal();
      final time = date == null
          ? last
          : '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
      return '已同步 · $time';
    }
    return '离线演示/待配置';
  }

  @override
  Widget build(BuildContext context) {
    final listenables = <Listenable>[ledger];
    if (insights != null) listenables.add(insights!);
    if (budget != null) listenables.add(budget!);
    if (quickEntry != null) listenables.add(quickEntry!);
    final listenable = listenables.length == 1
        ? listenables.single
        : Listenable.merge(listenables);
    return ListenableBuilder(
      listenable: listenable,
      builder: (context, _) {
        final metrics = insights?.metrics ?? ledger.metrics;
        final state = ledger.state;
        final alerts = budget?.alerts ?? budgetAlerts;
        final progress = budget?.progress ?? metrics.budgetProgress;
        final currentDraft = quickEntry?.draft ?? draft;
        final quickEntryStore = quickEntry;
        final recent = state.transactions
            .where((item) => item.deletedAt == null)
            .toList()
            .reversed
            .take(5)
            .toList();
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(22, 24, 22, 100),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const Expanded(
                  child: Text('个人财务空间', style: paSectionLabel),
                ),
                IconButton(
                    onPressed: state.syncState.isSyncing ? null : onSync,
                    tooltip: '同步',
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.sync_rounded, size: 18)),
              ]),
              const SizedBox(height: 4),
              Text(
                  '${greeting(now ?? DateTime.now())}，${displayName.trim().isEmpty ? '朋友' : displayName}',
                  style: const TextStyle(
                      color: paInk,
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -.4)),
              const SizedBox(height: 4),
              Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: [
                Text(state.currentMonth,
                    style: const TextStyle(color: paInkFaint, fontSize: 11)),
                const Text(' · ',
                    style: TextStyle(color: paInkFaint, fontSize: 11)),
                Text(_syncStatus(state),
                    style: const TextStyle(color: paInkFaint, fontSize: 11)),
              ]),
              const SizedBox(height: 26),
              Text(_balanceLabel(state.currentMonth), style: paSectionLabel),
              const SizedBox(height: 6),
              Text(money(metrics.savings), style: paNumberLarge),
              const SizedBox(height: 10),
              Wrap(spacing: 16, runSpacing: 4, children: [
                _inlineAmount('支出', money(metrics.expense), paExpense),
                _inlineAmount('收入', money(metrics.income), paIncome),
              ]),
              const SizedBox(height: 12),
              Text(
                  '储蓄率 ${(metrics.savingsRate * 100).round()}% · 当前净资产 ${money(metrics.netWorth)}${isDemoMode ? ' · 本地演示' : ''}',
                  style: const TextStyle(
                      color: paInkFaint, fontSize: 11, height: 1.5)),
              const SizedBox(height: 20),
              Row(children: [
                FilledButton.icon(
                    onPressed: () => _openComposer(context, smart: true),
                    icon: const Icon(Icons.auto_awesome, size: 16),
                    label: const Text('快捷记')),
                const SizedBox(width: 10),
                OutlinedButton.icon(
                  onPressed: () => _openComposer(context),
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('记一笔'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: paInk,
                    side: const BorderSide(color: paHairline),
                  ),
                ),
              ]),
              const SizedBox(height: 20),
              if (alerts.isNotEmpty) ...[
                _newAlertBanner(alerts),
                const SizedBox(height: 12),
              ],
              LayoutBuilder(builder: (context, constraints) {
                final width = (constraints.maxWidth - 12) / 2;
                return Wrap(spacing: 12, runSpacing: 12, children: [
                  SizedBox(
                      width: width,
                      child: MetricCard(
                          label: '本月收入',
                          value: metrics.income,
                          icon: Icons.south_west_rounded,
                          caption: '收入到账后先留存',
                          positive: true)),
                  SizedBox(
                      width: width,
                      child: MetricCard(
                          label: '本月支出',
                          value: metrics.expense,
                          icon: Icons.north_east_rounded,
                          caption: '转账不计入支出')),
                  SizedBox(
                      width: width,
                      child: MetricCard(
                          label: '本月储蓄率',
                          value: metrics.savingsRate * 100,
                          icon: Icons.savings_outlined,
                          caption: '健康区间 > 30%',
                          positive: metrics.savingsRate >= .3)),
                  SizedBox(
                      width: width,
                      child: MetricCard(
                          label: '当前净资产',
                          value: metrics.netWorth,
                          icon: Icons.account_balance_wallet_outlined,
                          caption: '资产 − 负债',
                          positive: metrics.netWorth >= 0)),
                ]);
              }),
              const SizedBox(height: 16),
              if (quickEntryStore != null &&
                  (quickEntryStore.batch != null ||
                      quickEntryStore.isStreamLocked)) ...[
                QuickEntryBatchPanel(store: quickEntryStore, state: state),
                const SizedBox(height: 16),
              ] else if (currentDraft != null) ...[
                DraftConfirmationCard(
                    draft: currentDraft,
                    state: state,
                    onEdit: () async {
                      final edited = await showDraftEditor(context,
                          draft: currentDraft, state: state);
                      if (edited != null) _updateDraft(edited);
                    },
                    onConfirm: () async {
                      await _confirmDraft(currentDraft);
                    }),
                const SizedBox(height: 16),
              ],
              _sectionCard(
                title: '最近账目',
                trailing: TextButton(
                    onPressed: onViewAllTransactions,
                    child: const Text('查看全部')),
                child: recent.isEmpty
                    ? const Text('还没有账目，记下第一笔吧。',
                        style: TextStyle(color: paInkFaint, fontSize: 12))
                    : Column(
                        children: recent
                            .map((item) => _transactionRow(context, item))
                            .toList()),
              ),
              const SizedBox(height: 16),
              _sectionCard(
                title: '本月预算',
                trailing:
                    TextButton(onPressed: openBudgets, child: const Text('管理')),
                child: progress.isEmpty
                    ? const Text('还没有预算，可以在预算页添加。',
                        style: TextStyle(color: paInkFaint, fontSize: 12))
                    : Column(
                        children: progress
                            .take(4)
                            .map((item) => ProgressRow(
                                progress: item,
                                category: categoryName(
                                    state, item.budget.categoryId)))
                            .toList()),
              ),
              if ((message ?? quickEntry?.message ?? ledger.message) !=
                  null) ...[
                const SizedBox(height: 12),
                Text(message ?? quickEntry?.message ?? ledger.message!,
                    style: const TextStyle(
                        color: paInkSub,
                        fontSize: 11,
                        fontWeight: FontWeight.w600)),
              ],
            ]),
          ),
        );
      },
    );
  }

  /// 首页大数字的标题：2026-10 → 十月结余。
  static String _balanceLabel(String currentMonth) {
    const names = [
      '一月',
      '二月',
      '三月',
      '四月',
      '五月',
      '六月',
      '七月',
      '八月',
      '九月',
      '十月',
      '十一月',
      '十二月',
    ];
    final parts = currentMonth.split('-');
    final month = parts.length == 2 ? int.tryParse(parts[1]) : null;
    if (month == null || month < 1 || month > 12) return '本月结余';
    return '${names[month - 1]}结余';
  }

  static String greeting(DateTime value) => value.hour < 6
      ? '夜深了'
      : value.hour < 12
          ? '早上好'
          : value.hour < 18
              ? '下午好'
              : '晚上好';

  Widget _inlineAmount(String label, String value, Color color) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Text(label,
          style: const TextStyle(color: paInkSub, fontSize: 11.5)),
      const SizedBox(width: 5),
      Text(value,
          style: TextStyle(
              color: color,
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              fontFeatures: paTabularFigures)),
    ]);
  }

  Widget _sectionCard(
      {required String title, required Widget child, Widget? trailing}) {
    return Card(
        child: Padding(
            padding: const EdgeInsets.all(20),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(
                children: [
                  Expanded(
                      child: Text(title,
                          style: const TextStyle(
                              color: paInk,
                              fontSize: 15,
                              fontWeight: FontWeight.w700))),
                  if (trailing != null) trailing
                ],
              ),
              const SizedBox(height: 10),
              child,
            ])));
  }

  /// 1px 发丝线行；收入是唯一带色的金额。
  Widget _transactionRow(
      BuildContext context, FinanceTransaction transaction) {
    final income = transaction.type == TransactionType.income;
    return InkWell(
      onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) =>
              TransactionDetailPage(ledger: ledger, transaction: transaction))),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 11),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: paHairline)),
        ),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                  transaction.note.isEmpty
                      ? categoryName(ledger.state, transaction.categoryId)
                      : transaction.note,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: paInk,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              Text(
                  '${categoryName(ledger.state, transaction.categoryId)} · ${accountName(ledger.state, transaction.accountId)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: paInkFaint, fontSize: 10.5)),
            ]),
          ),
          const SizedBox(width: 10),
          Text('${income ? '+' : '-'}${money(transaction.amount)}',
              style: TextStyle(
                  color: income ? paIncome : paExpense,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  fontFeatures: paTabularFigures)),
        ]),
      ),
    );
  }

  Widget _newAlertBanner(List<BudgetAlert> alerts) {
    final first = alerts.first;
    final label = first.level == BudgetAlertLevel.over
        ? '已超支'
        : first.level == BudgetAlertLevel.exhausted
            ? '已用完'
            : '已接近上限';
    return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
            color: paWarn.withValues(alpha: .06),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: paWarn.withValues(alpha: .28))),
        child: Row(children: [
          const Icon(Icons.notifications_active_outlined,
              color: paWarn, size: 18),
          const SizedBox(width: 9),
          Expanded(
              child: Text(
                  '预算提醒：${categoryName(ledger.state, first.budget.categoryId)} $label，已使用 ${money(first.spent)}。',
                  style: const TextStyle(
                      color: paWarn,
                      fontSize: 11,
                      fontWeight: FontWeight.w600)))
        ]));
  }

  void _openComposer(BuildContext context, {bool smart = false}) {
    openComposer(context, smart: smart);
  }

  void _updateDraft(AgentDraft draft) {
    final store = quickEntry;
    if (store != null) {
      store.updateDraft(draft);
    } else {
      onUpdateDraft?.call(draft);
    }
  }

  Future<bool> _confirmDraft(AgentDraft draft) {
    final store = quickEntry;
    if (store != null) {
      return store.confirmDraft(draft, store.sourceText, ledger.addTransaction);
    }
    final callback = onConfirmDraft;
    return callback == null ? Future<bool>.value(false) : callback(draft);
  }
}
