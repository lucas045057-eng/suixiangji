import 'package:flutter/material.dart';

import '../features/ledger/state/ledger_store.dart';
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
    required this.budgetAlerts,
    required this.draft,
    required this.isDemoMode,
    required this.message,
    required this.onSync,
    required this.onUpdateDraft,
    required this.onConfirmDraft,
    required this.openComposer,
    required this.openBudgets,
    super.key,
  });

  final LedgerStore ledger;
  final List<BudgetAlert> budgetAlerts;
  final AgentDraft? draft;
  final bool isDemoMode;
  final String? message;
  final Future<void> Function()? onSync;
  final ValueChanged<AgentDraft> onUpdateDraft;
  final Future<bool> Function(AgentDraft) onConfirmDraft;
  final OpenDashboardComposer openComposer;
  final VoidCallback openBudgets;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ledger,
      builder: (context, _) {
        final metrics = ledger.metrics;
        final state = ledger.state;
        final currentDraft = draft;
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
              if (budgetAlerts.isNotEmpty) ...[
                _newAlertBanner(budgetAlerts),
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
                      if (edited != null) onUpdateDraft(edited);
                    },
                    onConfirm: () async {
                      await onConfirmDraft(currentDraft);
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
                child: metrics.budgetProgress.isEmpty
                    ? const Text('还没有预算，可以在预算页添加。',
                        style:
                            TextStyle(color: Color(0xFF87958F), fontSize: 12))
                    : Column(
                        children: metrics.budgetProgress
                            .take(4)
                            .map((item) => ProgressRow(
                                progress: item,
                                category: categoryName(
                                    state, item.budget.categoryId)))
                            .toList()),
              ),
              if ((message ?? ledger.message) != null) ...[
                const SizedBox(height: 12),
                Text(message ?? ledger.message!,
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
}
