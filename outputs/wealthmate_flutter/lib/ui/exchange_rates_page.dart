import 'package:flutter/material.dart';

import '../domain/models.dart';
import '../state/finance_store.dart';

class ExchangeRatesPage extends StatelessWidget {
  const ExchangeRatesPage({required this.store, super.key});

  final FinanceStore store;

  @override
  Widget build(BuildContext context) {
    final currencies = <String>{
      ...store.state.accounts.map((item) => item.currency.toUpperCase()),
      ...store.state.transactions.map((item) => item.currency.toUpperCase()),
    }..remove('CNY');
    return Scaffold(
      appBar: AppBar(title: const Text('汇率管理')),
      body: ListenableBuilder(
        listenable: store,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.fromLTRB(22, 10, 22, 32),
          children: [
            const Text('汇率采用低频核验；没有可靠数据时不会猜测人民币金额。',
                style: TextStyle(
                    color: Color(0xFF87958F), fontSize: 11, height: 1.5)),
            const SizedBox(height: 14),
            if (currencies.isEmpty)
              const Card(
                  child: Padding(
                      padding: EdgeInsets.all(20),
                      child: Text('当前没有外币账户或账目。',
                          style: TextStyle(
                              color: Color(0xFF87958F), fontSize: 12)))),
            for (final currency in currencies) _rateCard(context, currency),
            if (store.message != null) ...[
              const SizedBox(height: 12),
              Text(store.message!,
                  style: const TextStyle(
                      color: Color(0xFF2F9F7D),
                      fontSize: 11,
                      fontWeight: FontWeight.w700))
            ],
          ],
        ),
      ),
    );
  }

  Widget _rateCard(BuildContext context, String currency) {
    final snapshot = store.state.exchangeRates
        .where((item) =>
            item.baseCurrency == currency && item.quoteCurrency == 'CNY')
        .firstOrNull;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
                child: Text('$currency / CNY',
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w800))),
            Text(snapshot == null ? '待补充汇率' : snapshot.rate.toStringAsFixed(4),
                style: TextStyle(
                    color: snapshot == null
                        ? const Color(0xFFB65B55)
                        : const Color(0xFF2F9F7D),
                    fontSize: 18,
                    fontWeight: FontWeight.w800))
          ]),
          const SizedBox(height: 6),
          Text(
              snapshot == null
                  ? '暂无来源和日期'
                  : '${snapshot.source} · ${snapshot.rateDate}',
              style: const TextStyle(color: Color(0xFF87958F), fontSize: 10)),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(
                child: OutlinedButton.icon(
                    onPressed: () => store.refreshExchangeRate(currency),
                    icon: const Icon(Icons.refresh, size: 16),
                    label: const Text('获取汇率'))),
            const SizedBox(width: 10),
            Expanded(
                child: FilledButton.tonalIcon(
                    onPressed: () => _manual(context, currency, snapshot),
                    icon: const Icon(Icons.edit_outlined, size: 16),
                    label: const Text('手动录入')))
          ]),
        ]),
      ),
    );
  }

  Future<void> _manual(BuildContext context, String currency,
      ExchangeRateSnapshot? existing) async {
    final rateController =
        TextEditingController(text: existing?.rate.toString() ?? '');
    final dateController = TextEditingController(
        text: existing?.rateDate ?? _dateKey(DateTime.now()));
    final sourceController =
        TextEditingController(text: existing?.source ?? '手动核验');
    final saved = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
                title: Text('录入 $currency 汇率'),
                content: Column(mainAxisSize: MainAxisSize.min, children: [
                  TextField(
                      controller: rateController,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                          labelText: '1 单位外币 = 人民币', suffixText: 'CNY')),
                  const SizedBox(height: 10),
                  TextField(
                      controller: dateController,
                      decoration: const InputDecoration(
                          labelText: '汇率日期', hintText: 'YYYY-MM-DD')),
                  const SizedBox(height: 10),
                  TextField(
                      controller: sourceController,
                      decoration: const InputDecoration(labelText: '来源'))
                ]),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(dialogContext, false),
                      child: const Text('取消')),
                  FilledButton(
                      onPressed: () => Navigator.pop(
                          dialogContext,
                          double.tryParse(rateController.text) != null &&
                              sourceController.text.trim().isNotEmpty),
                      child: const Text('保存'))
                ]));
    if (saved == true)
      await store.saveManualExchangeRate(
          baseCurrency: currency,
          rate: double.parse(rateController.text),
          rateDate: dateController.text.trim(),
          source: sourceController.text.trim());
    rateController.dispose();
    dateController.dispose();
    sourceController.dispose();
  }

  static String _dateKey(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
}
