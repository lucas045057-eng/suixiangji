import 'package:flutter/material.dart';

import '../domain/models.dart';
import '../state/finance_store.dart';
import 'widgets/ui_helpers.dart';
import 'account_detail_page.dart';
import 'exchange_rates_page.dart';

class WealthPage extends StatelessWidget {
  const WealthPage({required this.store, super.key});

  final FinanceStore store;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
        listenable: store,
        builder: (context, _) {
          final metrics = store.metrics;
          final assets = metrics.accountBalances
              .where((item) => item.account.type == AccountType.asset)
              .toList();
          final liabilities = metrics.accountBalances
              .where((item) => item.account.type == AccountType.liability)
              .toList();
          final goal = store.state.goals.firstOrNull;
          return SafeArea(
              child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(22, 24, 22, 100),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('财富',
                            style: TextStyle(
                                fontSize: 27, fontWeight: FontWeight.w800)),
                        const SizedBox(height: 5),
                        const Text('资产、负债和离目标还有多远',
                            style: TextStyle(
                                color: Color(0xFF87958F), fontSize: 11)),
                        const SizedBox(height: 18),
                        Card(
                            color: const Color(0xFF12201D),
                            child: Padding(
                                padding: const EdgeInsets.all(23),
                                child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Text('当前净资产',
                                          style: TextStyle(
                                              color: Color(0xFF91B1A4),
                                              fontSize: 11,
                                              fontWeight: FontWeight.w700)),
                                      const SizedBox(height: 10),
                                      Text(money(metrics.netWorth),
                                          style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 36,
                                              fontWeight: FontWeight.w800)),
                                      const SizedBox(height: 17),
                                      Row(children: [
                                        _summary('资产', metrics.assetTotal,
                                            const Color(0xFFA9E3CB)),
                                        const SizedBox(width: 32),
                                        _summary('负债', metrics.liabilityTotal,
                                            const Color(0xFFFAC6A5))
                                      ]),
                                    ]))),
                        const SizedBox(height: 16),
                        _accountSection(context, '资产账户', assets,
                            positive: true),
                        const SizedBox(height: 12),
                        _accountSection(context, '负债账户', liabilities,
                            positive: false),
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                            onPressed: () => _openAddAccount(context),
                            icon: const Icon(Icons.add),
                            label: const Text('新增账户')),
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                            onPressed: () => Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                    builder: (_) =>
                                        ExchangeRatesPage(store: store))),
                            icon: const Icon(Icons.currency_exchange),
                            label: const Text('管理汇率')),
                        if (goal != null) ...[
                          const SizedBox(height: 16),
                          Card(
                              color: const Color(0xFFFFF0E5),
                              child: Padding(
                                  padding: const EdgeInsets.all(20),
                                  child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(children: [
                                          const Expanded(
                                            child: Text('应急金',
                                                style: TextStyle(
                                                    fontSize: 15,
                                                    fontWeight:
                                                        FontWeight.w800)),
                                          ),
                                          Text(
                                              '${(metrics.goalProgress * 100).round()}%',
                                              style: const TextStyle(
                                                  color: Color(0xFFBD7245),
                                                  fontSize: 23,
                                                  fontWeight: FontWeight.w800))
                                        ]),
                                        const SizedBox(height: 5),
                                        Text(
                                            '目标 ${money(goal.target)} · 当前口径为已选流动资产',
                                            style: const TextStyle(
                                                color: Color(0xFFA77B5C),
                                                fontSize: 10)),
                                        const SizedBox(height: 16),
                                        ClipRRect(
                                            borderRadius:
                                                BorderRadius.circular(10),
                                            child: LinearProgressIndicator(
                                                value: metrics.goalProgress,
                                                minHeight: 9,
                                                color: const Color(0xFFE79E6C),
                                                backgroundColor:
                                                    Colors.white54)),
                                        const SizedBox(height: 8),
                                        Text(
                                            metrics.emergencyFundError ??
                                                (metrics.remainingMonths > 0
                                                    ? '按本月结余速度，预计还需 ${metrics.remainingMonths} 个月。'
                                                    : '当前已达到目标。'),
                                            style: TextStyle(
                                                color:
                                                    metrics.emergencyFundError ==
                                                            null
                                                        ? const Color(
                                                            0xFFA77B5C)
                                                        : const Color(
                                                            0xFFB65B55),
                                                fontSize: 10,
                                                fontWeight: FontWeight.w700)),
                                      ]))),
                        ],
                      ])));
        });
  }

  Widget _summary(String label, double value, Color color) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label,
            style: const TextStyle(color: Color(0xFF91B1A4), fontSize: 10)),
        const SizedBox(height: 5),
        Text(money(value),
            style: TextStyle(
                color: color, fontSize: 15, fontWeight: FontWeight.w800))
      ]);

  Widget _accountSection(
      BuildContext context, String title, List<AccountBalance> accounts,
      {required bool positive}) {
    return Card(
        child: Padding(
            padding: const EdgeInsets.all(20),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title,
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w800)),
              const SizedBox(height: 10),
              if (accounts.isEmpty)
                const Text('暂无账户',
                    style: TextStyle(color: Color(0xFF87958F), fontSize: 11)),
              for (final item in accounts)
                ListTile(
                    onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                            builder: (_) => AccountDetailPage(
                                store: store, account: item.account))),
                    contentPadding: EdgeInsets.zero,
                    leading: CircleAvatar(
                        backgroundColor: positive
                            ? const Color(0xFFE6F6EF)
                            : const Color(0xFFFFF1E4),
                        child: Icon(
                            positive
                                ? Icons.account_balance_wallet_outlined
                                : Icons.credit_card_outlined,
                            color: positive
                                ? const Color(0xFF2F9F7D)
                                : const Color(0xFFC77C3E),
                            size: 17)),
                    title: Text(item.account.name,
                        style: const TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w700)),
                    subtitle: Text(
                        '${item.account.currency} · ${item.account.isLiquid ? '流动资产 · 应急金口径' : '点击编辑账户配置'}',
                        style: const TextStyle(fontSize: 10)),
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      Text(money(item.balance),
                          style: TextStyle(
                              color: positive
                                  ? const Color(0xFF1A2621)
                                  : const Color(0xFFB65B55),
                              fontSize: 12,
                              fontWeight: FontWeight.w800)),
                      const SizedBox(width: 5),
                      const Icon(Icons.chevron_right, size: 17)
                    ])),
            ])));
  }

  Future<void> _openAddAccount(BuildContext context) async {
    final nameController = TextEditingController();
    final amountController = TextEditingController(text: '0');
    var type = AccountType.asset;
    var currency = 'CNY';
    await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
              title: const Text('新增账户'),
              content: StatefulBuilder(
                  builder: (context, setState) =>
                      Column(mainAxisSize: MainAxisSize.min, children: [
                        TextField(
                            controller: nameController,
                            decoration: const InputDecoration(
                                labelText: '账户名称', hintText: '例如：美元账户')),
                        const SizedBox(height: 10),
                        TextField(
                            controller: amountController,
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true),
                            decoration:
                                const InputDecoration(labelText: '初始余额')),
                        const SizedBox(height: 10),
                        TextField(
                            decoration: const InputDecoration(
                                labelText: '币种代码', hintText: 'CNY'),
                            onChanged: (value) =>
                                currency = value.trim().toUpperCase()),
                        const SizedBox(height: 10),
                        DropdownButtonFormField<AccountType>(
                            initialValue: type,
                            decoration:
                                const InputDecoration(labelText: '账户类型'),
                            items: const [
                              DropdownMenuItem(
                                  value: AccountType.asset, child: Text('资产')),
                              DropdownMenuItem(
                                  value: AccountType.liability,
                                  child: Text('负债'))
                            ],
                            onChanged: (value) {
                              if (value != null) setState(() => type = value);
                            }),
                      ])),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(dialogContext),
                    child: const Text('取消')),
                FilledButton(
                    onPressed: () async {
                      final name = nameController.text.trim();
                      final amount =
                          double.tryParse(amountController.text) ?? 0;
                      if (name.isEmpty || currency.length < 3) return;
                      await store.addAccount(
                          name: name,
                          type: type,
                          currency: currency,
                          openingBalance: amount);
                      if (dialogContext.mounted) Navigator.pop(dialogContext);
                    },
                    child: const Text('保存'))
              ],
            ));
    nameController.dispose();
    amountController.dispose();
  }
}
