import 'package:flutter/material.dart';

import '../domain/models.dart';
import '../state/finance_store.dart';
import 'widgets/transaction_form.dart';
import 'widgets/ui_helpers.dart';
import 'transaction_detail_page.dart';

class LedgerPage extends StatefulWidget {
  const LedgerPage({required this.store, super.key});

  final FinanceStore store;

  @override
  State<LedgerPage> createState() => _LedgerPageState();
}

class _LedgerPageState extends State<LedgerPage> {
  String query = '';
  TransactionType? filter;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.store,
      builder: (context, _) {
        final transactions = widget.store.state.transactions
            .where((item) {
              if (item.deletedAt != null ||
                  (filter != null && item.type != filter)) return false;
              final haystack =
                  '${item.note} ${categoryName(widget.store.state, item.categoryId)} ${accountName(widget.store.state, item.accountId)}';
              return haystack.contains(query);
            })
            .toList()
            .reversed
            .toList();
        return SafeArea(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
              padding: const EdgeInsets.fromLTRB(22, 24, 22, 12),
              child: Row(children: [
                const Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text('账本',
                          style: TextStyle(
                              fontSize: 27, fontWeight: FontWeight.w800)),
                      SizedBox(height: 5),
                      Text('每一笔都值得被看见',
                          style:
                              TextStyle(color: Color(0xFF87958F), fontSize: 11))
                    ])),
                IconButton(
                    onPressed: () => _openNew(context),
                    icon: const Icon(Icons.add_circle_outline_rounded),
                    tooltip: '记一笔'),
              ])),
          Padding(
              padding: const EdgeInsets.symmetric(horizontal: 22),
              child: TextField(
                  decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search), hintText: '搜索商户、备注或分类'),
                  onChanged: (value) => setState(() => query = value))),
          SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(22, 12, 22, 12),
              child: Row(children: [
                FilterChip(
                    label: const Text('全部'),
                    selected: filter == null,
                    onSelected: (_) => setState(() => filter = null)),
                const SizedBox(width: 8),
                FilterChip(
                    label: const Text('支出'),
                    selected: filter == TransactionType.expense,
                    onSelected: (_) =>
                        setState(() => filter = TransactionType.expense)),
                const SizedBox(width: 8),
                FilterChip(
                    label: const Text('收入'),
                    selected: filter == TransactionType.income,
                    onSelected: (_) =>
                        setState(() => filter = TransactionType.income)),
              ])),
          Expanded(
              child: transactions.isEmpty
                  ? const Center(
                      child: Text('没有符合条件的账目',
                          style: TextStyle(color: Color(0xFF87958F))))
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(22, 4, 22, 100),
                      itemCount: transactions.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) =>
                          _row(context, transactions[index]))),
        ]));
      },
    );
  }

  Widget _row(BuildContext context, FinanceTransaction transaction) {
    final income = transaction.type == TransactionType.income;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(vertical: 5),
      onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => TransactionDetailPage(
              store: widget.store, transaction: transaction))),
      leading: CircleAvatar(
          backgroundColor:
              income ? const Color(0xFFE6F6EF) : const Color(0xFFFFF1E4),
          child: Icon(income ? Icons.south_west : Icons.restaurant_outlined,
              color: income ? const Color(0xFF2F9F7D) : const Color(0xFFC77C3E),
              size: 17)),
      title: Text(
          transaction.note.isEmpty
              ? categoryName(widget.store.state, transaction.categoryId)
              : transaction.note,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
      subtitle: Text(
          '${transaction.date} · ${categoryName(widget.store.state, transaction.categoryId)} · ${accountName(widget.store.state, transaction.accountId)} · ${transaction.currency}${transaction.conversionStatus == 'pending' ? ' · 待补充汇率' : ''}',
          style: const TextStyle(fontSize: 10)),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        Text(
            '${income ? '+' : '-'}${money(transaction.amount)} ${transaction.currency}',
            style: TextStyle(
                color:
                    income ? const Color(0xFF2F9F7D) : const Color(0xFF1A2621),
                fontWeight: FontWeight.w800,
                fontSize: 12)),
        PopupMenuButton<String>(
            onSelected: (value) async {
              if (value == 'edit') _openEdit(context, transaction);
              if (value == 'delete')
                await widget.store.deleteTransaction(transaction.id);
            },
            itemBuilder: (_) => const [
                  PopupMenuItem(value: 'edit', child: Text('编辑')),
                  PopupMenuItem(value: 'delete', child: Text('删除'))
                ]),
      ]),
    );
  }

  void _openNew(BuildContext context) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => TransactionForm(store: widget.store));

  void _openEdit(BuildContext context, FinanceTransaction transaction) =>
      showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          builder: (_) =>
              TransactionForm(store: widget.store, initial: transaction));
}
