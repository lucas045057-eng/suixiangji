import 'package:flutter/material.dart';

import '../../domain/models.dart';
import '../../state/finance_store.dart';
import 'draft_confirmation_card.dart';
import 'draft_editor.dart';
import 'ui_helpers.dart';

class TransactionForm extends StatefulWidget {
  const TransactionForm(
      {required this.store, this.initial, this.smartMode = false, super.key});

  final FinanceStore store;
  final FinanceTransaction? initial;
  final bool smartMode;

  @override
  State<TransactionForm> createState() => _TransactionFormState();
}

class _TransactionFormState extends State<TransactionForm> {
  final formKey = GlobalKey<FormState>();
  late final TextEditingController amountController;
  late final TextEditingController noteController;
  late final TextEditingController smartController;
  late String type;
  late String categoryId;
  late String accountId;
  late String date;
  late String occurredAt;
  late String currency;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    amountController = TextEditingController(
        text: initial == null ? '' : initial.amount.toString());
    noteController = TextEditingController(text: initial?.note ?? '');
    smartController = TextEditingController();
    type = initial?.type.name ?? TransactionType.expense.name;
    categoryId = initial?.categoryId ??
        widget.store.state.categories.firstOrNull?.id ??
        '';
    accountId = initial?.accountId ??
        widget.store.state.defaultAccountId ??
        widget.store.state.accounts.firstOrNull?.id ??
        '';
    date = initial?.date ?? _dateKey(DateTime.now());
    occurredAt = initial?.occurredAt ?? '${date}T00:00:00';
    currency = initial?.currency ?? 'CNY';
  }

  @override
  void dispose() {
    amountController.dispose();
    noteController.dispose();
    smartController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
            20, 16, 20, MediaQuery.viewInsetsOf(context).bottom + 20),
        child: ListenableBuilder(
          listenable: widget.store,
          builder: (context, _) => _buildContent(context),
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    if (widget.smartMode && widget.store.draft != null) {
      return SingleChildScrollView(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _sheetHeader(context, '确认这笔草稿', 'Agent 只会整理，不会跳过你的确认。'),
        DraftConfirmationCard(
          draft: widget.store.draft!,
          state: widget.store.state,
          onEdit: () async {
            final edited = await showDraftEditor(context,
                draft: widget.store.draft!, state: widget.store.state);
            if (edited != null) widget.store.updateDraft(edited);
          },
          onConfirm: () async {
            final posted = await widget.store.confirmDraft(widget.store.draft!);
            if (posted && context.mounted) Navigator.pop(context);
          },
        ),
        TextButton(
            onPressed: widget.store.clearDraft, child: const Text('重新输入')),
      ]));
    }
    return SingleChildScrollView(
        child: Form(
            key: formKey,
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _sheetHeader(context, widget.initial == null ? '记一笔' : '编辑账目',
                  widget.initial == null ? '两步完成一笔日常记录。' : '修正后，预算和财富看板会同步更新。'),
              if (widget.smartMode)
                _buildSmartComposer(context)
              else
                _buildManualComposer(context),
            ])));
  }

  Widget _sheetHeader(BuildContext context, String title, String subtitle) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title,
              style:
                  const TextStyle(fontSize: 21, fontWeight: FontWeight.w800)),
          const SizedBox(height: 5),
          Text(subtitle,
              style: const TextStyle(color: Color(0xFF87958F), fontSize: 11)),
        ])),
        IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.close)),
      ]),
    );
  }

  Widget _buildSmartComposer(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      TextFormField(
        controller: smartController,
        maxLines: 4,
        decoration: const InputDecoration(
            labelText: '刚刚发生了什么？', hintText: '例如：今天中午外卖 32 元，支付宝'),
        validator: (value) =>
            value == null || value.trim().isEmpty ? '请先输入一件刚刚发生的事' : null,
      ),
      const SizedBox(height: 8),
      const Text('支持金额、分类、支付账户和“昨天/今天”等时间描述。',
          style: TextStyle(color: Color(0xFF87958F), fontSize: 10)),
      const SizedBox(height: 18),
      SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: () async {
              if (formKey.currentState!.validate())
                await widget.store.createDraft(smartController.text);
            },
            icon: const Icon(Icons.auto_awesome, size: 17),
            label: const Text('生成待确认草稿'),
          )),
    ]);
  }

  Widget _buildManualComposer(BuildContext context) {
    final accounts = widget.store.state.accounts
        .where((item) => item.deletedAt == null)
        .toList();
    final categories =
        widget.store.state.categories.where((item) => item.active).toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('账目类型',
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
      const SizedBox(height: 8),
      SegmentedButton<String>(
        segments: const [
          ButtonSegment(value: 'expense', label: Text('支出')),
          ButtonSegment(value: 'income', label: Text('收入'))
        ],
        selected: {type},
        onSelectionChanged: (value) => setState(() => type = value.first),
      ),
      const SizedBox(height: 14),
      TextFormField(
          controller: amountController,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: '金额', prefixText: '¥ '),
          validator: (value) =>
              double.tryParse(value ?? '') == null || double.parse(value!) <= 0
                  ? '请输入大于 0 的金额'
                  : null),
      const SizedBox(height: 12),
      TextFormField(
          initialValue: currency,
          decoration: const InputDecoration(labelText: '原始币种', hintText: 'CNY'),
          onChanged: (value) => currency = value.trim().toUpperCase(),
          validator: (value) => value == null || value.trim().length < 3
              ? '请输入币种代码，例如 CNY'
              : null),
      const SizedBox(height: 12),
      DropdownButtonFormField<String>(
          initialValue: categoryId.isEmpty ? null : categoryId,
          decoration: const InputDecoration(labelText: '分类'),
          items: categories
              .map((item) =>
                  DropdownMenuItem(value: item.id, child: Text(item.name)))
              .toList(),
          onChanged: (value) =>
              setState(() => categoryId = value ?? categoryId)),
      const SizedBox(height: 12),
      DropdownButtonFormField<String>(
          initialValue: accountId.isEmpty ? null : accountId,
          decoration: const InputDecoration(labelText: '账户'),
          items: accounts
              .map((item) => DropdownMenuItem(
                  value: item.id,
                  child: Text(
                      '${item.name}${item.type == AccountType.liability ? ' · 信用' : ''}')))
              .toList(),
          onChanged: (value) => setState(() => accountId = value ?? accountId),
          validator: (value) => value == null ? '请选择账户' : null),
      const SizedBox(height: 12),
      TextFormField(
          readOnly: true,
          controller: TextEditingController(text: date),
          decoration: const InputDecoration(
              labelText: '日期',
              suffixIcon: Icon(Icons.calendar_today_outlined, size: 17)),
          onTap: () async {
            final picked = await showDatePicker(
                context: context,
                initialDate: DateTime.tryParse(date) ?? DateTime.now(),
                firstDate: DateTime(2020),
                lastDate: DateTime(2100));
            if (picked != null) {
              setState(() {
                date = _dateKey(picked);
                occurredAt = '${date}T00:00:00';
              });
            }
          }),
      const SizedBox(height: 12),
      TextFormField(
          controller: noteController,
          decoration:
              const InputDecoration(labelText: '备注', hintText: '例如：午餐、通勤或房租')),
      const SizedBox(height: 20),
      SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
              onPressed: _saveManual,
              icon: const Icon(Icons.check, size: 17),
              label: Text(widget.initial == null ? '确认入账' : '保存修改'))),
    ]);
  }

  Future<void> _saveManual() async {
    if (!formKey.currentState!.validate()) return;
    final id =
        widget.initial?.id ?? 'tx-${DateTime.now().microsecondsSinceEpoch}';
    final transaction = FinanceTransaction(
      id: id,
      date: date,
      occurredAt: occurredAt,
      type: type == 'income' ? TransactionType.income : TransactionType.expense,
      amount: double.parse(amountController.text),
      currency: currency.isEmpty ? 'CNY' : currency,
      categoryId: categoryId,
      accountId: accountId,
      note: noteController.text.trim().isEmpty
          ? categoryName(widget.store.state, categoryId)
          : noteController.text.trim(),
      clientOpId: widget.initial?.clientOpId ?? id,
    );
    if (widget.initial == null) {
      await widget.store.addTransaction(transaction);
    } else {
      await widget.store.updateTransaction(transaction);
    }
    if (mounted) Navigator.pop(context);
  }

  static String _dateKey(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
}
