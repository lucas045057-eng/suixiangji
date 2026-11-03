import 'package:flutter/material.dart';

import '../domain/models.dart';
import '../state/finance_store.dart';
import '../features/assets/state/asset_store.dart';
import '../features/ledger/state/ledger_store.dart';
import 'theme.dart';
import 'widgets/transaction_form.dart';
import 'widgets/ui_helpers.dart';

class TransactionDetailPage extends StatelessWidget {
  TransactionDetailPage(
      {LedgerStore? ledger,
      FinanceStore? store,
      AssetStore? assets,
      required this.transaction,
      super.key})
      : ledger = ledger ?? store!.ledger,
        assets = assets ?? store?.assets;

  final LedgerStore ledger;
  final AssetStore? assets;
  final FinanceTransaction transaction;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
        listenable: ledger,
        builder: (context, _) {
          final current = ledger.transactions
              .where((item) => item.id == transaction.id)
              .firstOrNull;
          if (current == null) {
            return const Scaffold(body: Center(child: Text('这笔账目已不存在')));
          }
          return _buildDetail(context, current);
        });
  }

  Widget _buildDetail(BuildContext context, FinanceTransaction value) {
    if (value.isAdjustment) return _buildAdjustment(context, value);
    final isIncome = value.type == TransactionType.income;
    final currency = value.currency.toUpperCase();
    final converted = value.cnyAmount;
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
            child: Padding(
              padding: const EdgeInsets.all(22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(isIncome ? '收入' : '支出',
                      style: TextStyle(
                          color: isIncome ? paIncome : paInkSub,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 2)),
                  const SizedBox(height: 8),
                  Text(
                      '${isIncome ? '+' : '-'}${value.amount.toStringAsFixed(value.amount.truncateToDouble() == value.amount ? 0 : 2)} $currency',
                      style: TextStyle(
                          color: isIncome ? paIncome : paInk,
                          fontSize: 30,
                          fontWeight: FontWeight.w300,
                          letterSpacing: -.6,
                          fontFeatures: paTabularFigures)),
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
            _detailRow('发生时间', _occurredLabel(value)),
            _detailRow('分类', categoryName(ledger.state, value.categoryId)),
            _detailRow('支付账户/平台', accountName(ledger.state, value.accountId)),
            _detailRow('原始金额', '${value.amount.toStringAsFixed(2)} $currency'),
            _detailRow('人民币金额', converted == null ? '待补充汇率' : money(converted)),
            _detailRow('汇率状态', _exchangeLabel(value)),
            _detailRow('备注', value.note.isEmpty ? '无备注' : value.note),
          ])),
          if (value.type == TransactionType.transfer) ...[
            const SizedBox(height: 14),
            Card(
                child: Column(children: [
              _detailRow(
                  '转出账户', accountName(ledger.state, value.fromAccountId)),
              _detailRow('转入账户', accountName(ledger.state, value.toAccountId))
            ])),
          ],
        ],
      ),
    );
  }

  Widget _buildAdjustment(BuildContext context, FinanceTransaction value) {
    final meta = value.adjustmentMeta ?? const <String, Object?>{};
    final positive = value.amount >= 0;
    final reversible = !value.isReversal && assets != null;
    return Scaffold(
      appBar: AppBar(
        title: const Text('账目详情'),
        actions: [
          if (reversible)
            IconButton(
                onPressed: () => _reverse(context, value),
                icon: const Icon(Icons.undo),
                tooltip: '撤销校准'),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(22, 10, 22, 32),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(adjustmentLabel(value),
                      style: const TextStyle(
                          color: paInkSub,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 2)),
                  const SizedBox(height: 8),
                  Text(signedMoney(value.amount),
                      style: TextStyle(
                          color: positive ? paIncome : paExpense,
                          fontSize: 30,
                          fontWeight: FontWeight.w300,
                          letterSpacing: -.6,
                          fontFeatures: paTabularFigures)),
                  const SizedBox(height: 6),
                  const Text('校准只调整账面余额，不计入收入、支出或预算。',
                      style: TextStyle(color: paInkFaint, fontSize: 10)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          Card(
              child: Column(children: [
            _detailRow('发生时间', _occurredLabel(value)),
            _detailRow('账户', accountName(ledger.state, value.accountId)),
            _detailRow('校准原因', adjustmentReason(value)),
            if (meta['basis_balance_cny'] != null)
              _detailRow('校准前账面额', _cnyText(meta['basis_balance_cny'])),
            if (meta['target_cny'] != null)
              _detailRow('目标账面额', _cnyText(meta['target_cny'])),
            _detailRow('生效日期', (meta['effective_on'] ?? value.date).toString()),
            if (value.isReversal)
              _detailRow('撤销的原校准', value.reversesTransactionId ?? '-'),
            _detailRow('备注', value.note.isEmpty ? '无备注' : value.note),
          ])),
        ],
      ),
    );
  }

  String _cnyText(Object? value) {
    final parsed = value is num ? value.toDouble() : double.tryParse('$value');
    return parsed == null ? '$value' : money(parsed);
  }

  Future<void> _reverse(
      BuildContext context, FinanceTransaction value) async {
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
                title: const Text('撤销校准'),
                content: const Text('将生成一条相反的调整流水，原校准保持不变。'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(dialogContext, false),
                      child: const Text('取消')),
                  FilledButton(
                      onPressed: () => Navigator.pop(dialogContext, true),
                      child: const Text('确认撤销'))
                ]));
    if (confirmed != true || assets == null) return;
    await assets!.reverseAdjustment(value);
    final message = assets!.message ?? '撤销失败';
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
    if (message == '校准已撤销') Navigator.pop(context);
  }

  Widget _detailRow(String label, String value) => Padding(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
            width: 104,
            child: Text(label,
                style:
                    const TextStyle(color: paInkSub, fontSize: 11))),
        Expanded(
            child: Text(value,
                textAlign: TextAlign.right,
                style:
                    const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)))
      ]));

  String _occurredLabel(FinanceTransaction value) {
    final date = ledgerFullDate(value.date);
    final time = recordedTime(value.occurredAt);
    return time == null ? '$date（时间未记录）' : '$date $time';
  }

  String _exchangeLabel(FinanceTransaction value) {
    if (value.currency.toUpperCase() == 'CNY') return '人民币原生金额';
    if (value.conversionStatus == 'pending' || value.cnyAmount == null)
      return '待补充汇率';
    return '${value.exchangeRateSource ?? '已核验'} · ${value.exchangeRateDate ?? '日期未知'} · ${value.exchangeRate?.toStringAsFixed(4) ?? '-'}';
  }

  Future<void> _edit(BuildContext context) async {
    final current = ledger.transactions
        .where((item) => item.id == transaction.id)
        .firstOrNull;
    if (current == null) {
      if (context.mounted) Navigator.pop(context);
      return;
    }
    await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (_) => TransactionForm(ledger: ledger, initial: current));
  }

  Future<void> _delete(BuildContext context) async {
    await ledger.deleteTransaction(transaction.id);
    if (context.mounted) Navigator.pop(context);
  }
}
