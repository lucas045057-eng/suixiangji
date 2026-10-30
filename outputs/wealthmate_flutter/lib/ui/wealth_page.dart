import 'package:flutter/material.dart';

import '../domain/models.dart';
import '../features/assets/state/asset_store.dart';
import '../features/ledger/state/ledger_store.dart';
import 'theme.dart';
import 'widgets/ui_helpers.dart';
import 'account_detail_page.dart';
import 'exchange_rates_page.dart';

class WealthPage extends StatelessWidget {
  const WealthPage({required this.store, required this.ledger, super.key});

  final AssetStore store;
  final LedgerStore ledger;

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
                            style: TextStyle(color: paInkSub, fontSize: 11)),
                        const SizedBox(height: 18),
                        Card(
                            child: Padding(
                                padding: const EdgeInsets.all(23),
                                child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Text('当前净资产',
                                          style: paSectionLabel),
                                      const SizedBox(height: 10),
                                      FittedBox(
                                          fit: BoxFit.scaleDown,
                                          alignment: Alignment.centerLeft,
                                          child: Text(money(metrics.netWorth),
                                              style: paNumberLarge)),
                                      const SizedBox(height: 17),
                                      Row(children: [
                                        _summary('资产', metrics.assetTotal),
                                        const SizedBox(width: 32),
                                        _summary('负债', metrics.liabilityTotal)
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
                      ])));
        });
  }

  Widget _summary(String label, double value) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: const TextStyle(color: paInkSub, fontSize: 10)),
        const SizedBox(height: 5),
        Text(money(value),
            style: const TextStyle(
                color: paInk,
                fontSize: 15,
                fontWeight: FontWeight.w600,
                fontFeatures: paTabularFigures))
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
                    style: TextStyle(color: paInkSub, fontSize: 11)),
              for (final item in accounts)
                InkWell(
                    onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                            builder: (_) => AccountDetailPage(
                                store: store, account: item.account))),
                    child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 11),
                        decoration: const BoxDecoration(
                            border:
                                Border(bottom: BorderSide(color: paHairline))),
                        child: Row(children: [
                          Icon(
                              positive
                                  ? Icons.account_balance_wallet_outlined
                                  : Icons.credit_card_outlined,
                              color: paInkFaint,
                              size: 16),
                          const SizedBox(width: 10),
                          Expanded(
                              child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                Text(item.account.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        color: paInk,
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w600)),
                                const SizedBox(height: 2),
                                Text(
                                    '${item.account.currency} · 可编辑配置或校准余额',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        color: paInkFaint, fontSize: 10)),
                              ])),
                          const SizedBox(width: 8),
                          Text(money(item.balance),
                              style: const TextStyle(
                                  color: paInk,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  fontFeatures: paTabularFigures)),
                          const SizedBox(width: 2),
                          const Icon(Icons.chevron_right,
                              size: 16, color: paInkFaint)
                        ]))),
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
