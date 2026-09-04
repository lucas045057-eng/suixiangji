import 'package:flutter/material.dart';

import '../../domain/models.dart';

Future<AgentDraft?> showDraftEditor(BuildContext context,
    {required AgentDraft draft, required FinanceState state}) {
  return showDialog<AgentDraft>(
      context: context,
      builder: (_) => DraftEditorDialog(draft: draft, state: state));
}

class DraftEditorDialog extends StatefulWidget {
  const DraftEditorDialog(
      {required this.draft, required this.state, super.key});

  final AgentDraft draft;
  final FinanceState state;

  @override
  State<DraftEditorDialog> createState() => _DraftEditorDialogState();
}

class _DraftEditorDialogState extends State<DraftEditorDialog> {
  late final TextEditingController amountController;
  late final TextEditingController dateController;
  late final TextEditingController currencyController;
  late final TextEditingController noteController;
  late TransactionType type;
  late String? categoryId;
  late String? accountId;

  @override
  void initState() {
    super.initState();
    final draft = widget.draft;
    amountController = TextEditingController(text: draft.amount.toString());
    dateController = TextEditingController(text: draft.date);
    currencyController = TextEditingController(text: draft.currency);
    noteController = TextEditingController(text: draft.note);
    type = draft.type;
    categoryId = draft.categoryId;
    accountId = draft.accountId;
  }

  @override
  void dispose() {
    amountController.dispose();
    dateController.dispose();
    currencyController.dispose();
    noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final categories = widget.state.categories
        .where((item) => item.active && item.type == type)
        .toList(growable: false);
    final accounts = widget.state.accounts
        .where((item) => item.deletedAt == null)
        .toList(growable: false);
    return AlertDialog(
      title: const Text('修改快捷记'),
      content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(
            controller: amountController,
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: '金额')),
        const SizedBox(height: 10),
        SegmentedButton<TransactionType>(
          segments: const [
            ButtonSegment(
                value: TransactionType.expense, label: Text('支出')),
            ButtonSegment(value: TransactionType.income, label: Text('收入')),
          ],
          selected: {type},
          onSelectionChanged: (value) =>
              setState(() => type = value.first),
        ),
        const SizedBox(height: 10),
        DropdownButtonFormField<String>(
            initialValue: categories.any((item) => item.id == categoryId)
                ? categoryId
                : null,
            decoration: const InputDecoration(labelText: '分类'),
            items: categories
                .map((item) => DropdownMenuItem(
                    value: item.id, child: Text(item.name)))
                .toList(),
            onChanged: (value) => setState(() => categoryId = value)),
        const SizedBox(height: 10),
        DropdownButtonFormField<String>(
            initialValue: accounts.any((item) => item.id == accountId)
                ? accountId
                : null,
            decoration: const InputDecoration(labelText: '支付账户'),
            items: accounts
                .map((item) => DropdownMenuItem(
                    value: item.id, child: Text(item.name)))
                .toList(),
            onChanged: (value) => setState(() => accountId = value)),
        const SizedBox(height: 10),
        TextField(
            controller: dateController,
            decoration: const InputDecoration(labelText: '日期', hintText: 'YYYY-MM-DD'),
        ),
        const SizedBox(height: 10),
        TextField(
            controller: currencyController,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(labelText: '币种'),
        ),
        const SizedBox(height: 10),
        TextField(
            controller: noteController,
            maxLines: 2,
            decoration: const InputDecoration(labelText: '备注'),
        ),
      ])),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context), child: const Text('取消')),
        FilledButton(
            onPressed: _save,
            child: const Text('保存修改')),
      ],
    );
  }

  void _save() {
    final amount = double.tryParse(amountController.text.trim()) ?? 0;
    final date = dateController.text.trim();
    final currency = currencyController.text.trim().toUpperCase();
    final missingFacts = <String>[];
    if (amount <= 0) missingFacts.add('请输入金额');
    if (categoryId == null) missingFacts.add('请选择分类');
    if (accountId == null) missingFacts.add('请选择支付账户');
    if (date.length != 10) missingFacts.add('请输入正确日期');
    Navigator.pop(
        context,
        widget.draft.copyWith(
          amount: amount,
          type: type,
          categoryId: categoryId,
          accountId: accountId,
          date: date,
          currency: currency.isEmpty ? 'CNY' : currency,
          note: noteController.text.trim(),
          confidence: missingFacts.isEmpty ? .98 : .55,
          missingFacts: missingFacts,
        ));
  }
}
