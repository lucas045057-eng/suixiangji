import 'package:flutter/material.dart';

import '../features/budget/state/budget_store.dart';
import '../features/insights/state/insights_store.dart';
import '../features/ledger/state/ledger_store.dart';
import '../features/quick_entry/state/quick_entry_store.dart';
import '../domain/models.dart';
import 'widgets/draft_confirmation_card.dart';
import 'widgets/draft_editor.dart';
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
    this.onSync,
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
  final Future<void> Function()? onSync;
  final ValueChanged<AgentDraft>? onUpdateDraft;
  final Future<bool> Function(AgentDraft)? onConfirmDraft;
  final OpenDashboardComposer openComposer;
  final VoidCallback openBudgets;

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
              const Text('个人财务空间',
                  style: TextStyle(
                      color: Color(0xFF87958F),
                      fontSize: 11,
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 5),
              Row(children: [
                const Expanded(
                    child: Text('早上好，林默 👋',
                        style: TextStyle(
                            fontSize: 27,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -.7))),
                IconButton(
                    onPressed: onSync,
                    tooltip: '同步',
                    icon: const Icon(Icons.sync_rounded)),
              ]),
              Text('${state.currentMonth} · 这是你的财务节奏',
                  style:
                      const TextStyle(color: Color(0xFF87958F), fontSize: 11)),
              const SizedBox(height: 20),
              if (alerts.isNotEmpty) ...[
                _newAlertBanner(alerts),
                const SizedBox(height: 12),
              ],
              Card(
                color: const Color(0xFF12201D),
                child: Padding(
                  padding: const EdgeInsets.all(23),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('现金流状态',
                            style: TextStyle(
                                color: Color(0xFFA7CCB9),
                                fontSize: 11,
                                fontWeight: FontWeight.w700)),
                        const SizedBox(height: 12),
                        Text('这个月，你留住了 ${money(metrics.savings)}',
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 24,
                                fontWeight: FontWeight.w800)),
                        const SizedBox(height: 8),
                        Text(
                            '储蓄率 ${(metrics.savingsRate * 100).round()}%，当前净资产 ${money(metrics.netWorth)}。${isDemoMode ? '当前为本地演示，数据只保存在本机。' : '同步服务已配置。'}',
                            style: const TextStyle(
                                color: Color(0xFFA9BDB5),
                                fontSize: 11,
                                height: 1.6)),
                        const SizedBox(height: 18),
                        Row(children: [
                          FilledButton.tonalIcon(
                              onPressed: () =>
                                  _openComposer(context, smart: true),
                              icon: const Icon(Icons.auto_awesome, size: 16),
                              label: const Text('快捷记')),
                          const SizedBox(width: 10),
                          OutlinedButton.icon(
                            onPressed: () => _openComposer(context),
                            icon: const Icon(Icons.add, size: 16),
                            label: const Text('记一笔'),
                            style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.white,
                                side:
                                    const BorderSide(color: Color(0x558FAFA1))),
                          ),
                        ]),
                      ]),
                ),
              ),
              const SizedBox(height: 16),
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
              if (currentDraft != null) ...[
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
                trailing:
                    TextButton(onPressed: () {}, child: const Text('查看全部')),
                child: recent.isEmpty
                    ? const Text('还没有账目，记下第一笔吧。',
                        style:
                            TextStyle(color: Color(0xFF87958F), fontSize: 12))
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
                        style:
                            TextStyle(color: Color(0xFF87958F), fontSize: 12))
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
                        color: Color(0xFF2F9F7D),
                        fontSize: 11,
                        fontWeight: FontWeight.w700)),
              ],
            ]),
          ),
        );
      },
    );
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
                              fontSize: 15, fontWeight: FontWeight.w800))),
                  if (trailing != null) trailing
                ],
              ),
              const SizedBox(height: 15),
              child,
            ])));
  }

  Widget _transactionRow(BuildContext context, FinanceTransaction transaction) {
    final income = transaction.type == TransactionType.income;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) =>
              TransactionDetailPage(ledger: ledger, transaction: transaction))),
      leading: CircleAvatar(
          backgroundColor:
              income ? const Color(0xFFE6F6EF) : const Color(0xFFFFF1E4),
          child: Icon(income ? Icons.south_west : Icons.restaurant_outlined,
              color: income ? const Color(0xFF2F9F7D) : const Color(0xFFC77C3E),
              size: 17)),
      title: Text(
          transaction.note.isEmpty
              ? categoryName(ledger.state, transaction.categoryId)
              : transaction.note,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
      subtitle: Text(
          '${categoryName(ledger.state, transaction.categoryId)} · ${accountName(ledger.state, transaction.accountId)}',
          style: const TextStyle(fontSize: 10)),
      trailing: Text('${income ? '+' : '-'}${money(transaction.amount)}',
          style: TextStyle(
              color: income ? const Color(0xFF2F9F7D) : const Color(0xFF1A2621),
              fontWeight: FontWeight.w800,
              fontSize: 12)),
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
            color: const Color(0xFFFFF3E8),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFF0C69C))),
        child: Row(children: [
          const Icon(Icons.notifications_active_outlined,
              color: Color(0xFFC77C3E), size: 18),
          const SizedBox(width: 9),
          Expanded(
              child: Text(
                  '预算提醒：${categoryName(ledger.state, first.budget.categoryId)} $label，已使用 ${money(first.spent)}。',
                  style: const TextStyle(
                      color: Color(0xFFA05B2C),
                      fontSize: 11,
                      fontWeight: FontWeight.w700)))
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
