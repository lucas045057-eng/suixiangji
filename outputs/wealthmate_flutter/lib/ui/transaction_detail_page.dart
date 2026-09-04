import 'package:flutter/material.dart';

import '../domain/models.dart';
import '../state/finance_store.dart';
import 'widgets/transaction_form.dart';
import 'widgets/ui_helpers.dart';

class TransactionDetailPage extends StatelessWidget {
  const TransactionDetailPage(
      {required this.store, required this.transaction, super.key});

  final FinanceStore store;
  final FinanceTransaction transaction;

  @override
  Widget build(BuildContext context) {
    final isIncome = transaction.type == TransactionType.income;
    final currency = transaction.currency.toUpperCase();
    final converted = transaction.cnyAmount;
    return Scaffold(
      appBar: AppBar(
        title: const Text('账目详情'),
        actions: [
          IconButton(
              onPressed: () => _edit(context),
              icon: const Icon(Icons.edit_outlined),
              tooltip: '编辑'),
          IconButton(
              onPressed: () => _delete(context),
              icon: const Icon(Icons.delete_outline),
              tooltip: '删除'),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(22, 10, 22, 32),
        children: [
          Card(
            color: isIncome ? const Color(0xFFE6F6EF) : const Color(0xFFFFF1E4),
            child: Padding(
              padding: const EdgeInsets.all(22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(isIncome ? '收入' : '支出',
                      style: TextStyle(
                          color: isIncome
                              ? const Color(0xFF2F9F7D)
                              : const Color(0xFFC77C3E),
                          fontSize: 12,
                          fontWeight: FontWeight.w800)),
                  const SizedBox(height: 8),
                  Text(
                      '${isIncome ? '+' : '-'}${transaction.amount.toStringAsFixed(transaction.amount.truncateToDouble() == transaction.amount ? 0 : 2)} $currency',
                      style: const TextStyle(
                          fontSize: 30, fontWeight: FontWeight.w800)),
                  if (converted != null && currency != 'CNY') ...[
                    const SizedBox(height: 6),
                    Text('折合人民币 ${money(converted)}',
                        style: const TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w700)),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          Card(
              child: Column(children: [
            _detailRow('发生时间', _occurredLabel(transaction)),
            _detailRow('分类', categoryName(store.state, transaction.categoryId)),
            _detailRow(
                '支付账户/平台', accountName(store.state, transaction.accountId)),
            _detailRow(
                '原始金额', '${transaction.amount.toStringAsFixed(2)} $currency'),
            _detailRow('人民币金额', converted == null ? '待补充汇率' : money(converted)),
            _detailRow('汇率状态', _exchangeLabel(transaction)),
            _detailRow(
                '备注', transaction.note.isEmpty ? '无备注' : transaction.note),
          ])),
          if (transaction.type == TransactionType.transfer) ...[
            const SizedBox(height: 14),
            Card(
                child: Column(children: [
              _detailRow(
                  '转出账户', accountName(store.state, transaction.fromAccountId)),
              _detailRow(
                  '转入账户', accountName(store.state, transaction.toAccountId))
            ])),
          ],
        ],
      ),
    );
  }

  Widget _detailRow(String label, String value) => Padding(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
            width: 104,
            child: Text(label,
                style:
                    const TextStyle(color: Color(0xFF87958F), fontSize: 11))),
        Expanded(
            child: Text(value,
                textAlign: TextAlign.right,
                style:
                    const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)))
      ]));

  String _occurredLabel(FinanceTransaction value) {
    final raw = value.occurredAt;
    if (raw == null || raw.isEmpty) return value.date;
    if (raw.length >= 16 && raw[10] == 'T')
      return '${raw.substring(0, 10)} ${raw.substring(11, 16)}';
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) return raw.replaceFirst('T', ' ').split('.').first;
    return '${parsed.year.toString().padLeft(4, '0')}-${parsed.month.toString().padLeft(2, '0')}-${parsed.day.toString().padLeft(2, '0')} ${parsed.hour.toString().padLeft(2, '0')}:${parsed.minute.toString().padLeft(2, '0')}';
  }

  String _exchangeLabel(FinanceTransaction value) {
    if (value.currency.toUpperCase() == 'CNY') return '人民币原生金额';
    if (value.conversionStatus == 'pending' || value.cnyAmount == null)
      return '待补充汇率';
    return '${value.exchangeRateSource ?? '已核验'} · ${value.exchangeRateDate ?? '日期未知'} · ${value.exchangeRate?.toStringAsFixed(4) ?? '-'}';
  }

  Future<void> _edit(BuildContext context) async {
    await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (_) => TransactionForm(store: store, initial: transaction));
  }

  Future<void> _delete(BuildContext context) async {
    await store.deleteTransaction(transaction.id);
    if (context.mounted) Navigator.pop(context);
  }
}
