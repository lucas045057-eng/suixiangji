import 'package:flutter/material.dart';

import '../domain/models.dart';
import '../state/finance_store.dart';
import 'widgets/ui_helpers.dart';

class AccountDetailPage extends StatefulWidget {
  const AccountDetailPage(
      {required this.store, required this.account, super.key});

  final FinanceStore store;
  final Account account;

  @override
  State<AccountDetailPage> createState() => _AccountDetailPageState();
}

class _AccountDetailPageState extends State<AccountDetailPage> {
  late final TextEditingController nameController;
  late final TextEditingController currencyController;
  late final TextEditingController openingController;
  late AccountType type;
  late AccountKind accountKind;
  late bool isLiquid;
  late bool isDefaultPayment;

  @override
  void initState() {
    super.initState();
    final account = widget.account;
    nameController = TextEditingController(text: account.name);
    currencyController = TextEditingController(text: account.currency);
    openingController =
        TextEditingController(text: account.openingBalance.toString());
    type = account.type;
    accountKind = account.accountKind;
    isLiquid = account.isLiquid;
    isDefaultPayment = account.isDefaultPayment;
  }

  @override
  void dispose() {
    nameController.dispose();
    currencyController.dispose();
    openingController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('账户配置')),
      body: ListenableBuilder(
        listenable: widget.store,
        builder: (context, _) {
          final balance = widget.store.metrics.accountBalances
                  .where((item) => item.account.id == widget.account.id)
                  .firstOrNull
                  ?.balance ??
              0;
          return ListView(
            padding: const EdgeInsets.fromLTRB(22, 10, 22, 32),
            children: [
              Card(
                color: const Color(0xFF12201D),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('当前计算余额',
                          style: TextStyle(
                              color: Color(0xFF91B1A4), fontSize: 11)),
                      const SizedBox(height: 8),
                      Text(money(balance),
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 30,
                              fontWeight: FontWeight.w800)),
                      const SizedBox(height: 5),
                      const Text('余额由初始余额和已确认账目计算，不直接覆盖。',
                          style: TextStyle(
                              color: Color(0xFFA9E3CB), fontSize: 10)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                  controller: nameController,
                  decoration: const InputDecoration(labelText: '账户名称')),
              const SizedBox(height: 12),
              DropdownButtonFormField<AccountKind>(
                  initialValue: accountKind,
                  decoration: const InputDecoration(labelText: '账户用途'),
                  items: AccountKind.values
                      .map((item) => DropdownMenuItem(
                          value: item, child: Text(_accountKindLabel(item))))
                      .toList(),
                  onChanged: (value) =>
                      setState(() => accountKind = value ?? accountKind)),
              const SizedBox(height: 12),
              DropdownButtonFormField<AccountType>(
                  initialValue: type,
                  decoration: const InputDecoration(labelText: '资产/负债'),
                  items: const [
                    DropdownMenuItem(
                        value: AccountType.asset, child: Text('资产')),
                    DropdownMenuItem(
                        value: AccountType.liability, child: Text('负债'))
                  ],
                  onChanged: (value) => setState(() => type = value ?? type)),
              const SizedBox(height: 12),
              TextField(
                  controller: currencyController,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(labelText: '币种代码')),
              const SizedBox(height: 12),
              TextField(
                  controller: openingController,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: '初始余额')),
              SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('计入流动资产'),
                  subtitle: const Text('应急金计算会使用此开关'),
                  value: isLiquid,
                  onChanged: (value) => setState(() => isLiquid = value)),
              SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('默认支付账户'),
                  value: isDefaultPayment,
                  onChanged: (value) =>
                      setState(() => isDefaultPayment = value)),
              const SizedBox(height: 8),
              FilledButton(onPressed: _save, child: const Text('保存账户配置')),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                  onPressed: () => _adjustBalance(context, balance),
                  icon: const Icon(Icons.tune),
                  label: const Text('余额调整')),
              const SizedBox(height: 8),
              TextButton.icon(
                  onPressed: _archive,
                  icon: const Icon(Icons.archive_outlined),
                  label: const Text('归档账户'),
                  style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFFB65B55))),
            ],
          );
        },
      ),
    );
  }

  Future<void> _save() async {
    final name = nameController.text.trim();
    final currency = currencyController.text.trim().toUpperCase();
    final opening = double.tryParse(openingController.text.trim());
    if (name.isEmpty || currency.length < 3 || opening == null) {
      _showMessage('请填写有效的账户名称、币种和初始余额');
      return;
    }
    await widget.store.updateAccount(widget.account.copyWith(
        name: name,
        type: type,
        accountKind: accountKind,
        currency: currency,
        openingBalance: opening,
        isLiquid: isLiquid,
        isDefaultPayment: isDefaultPayment));
    if (widget.store.message == '账户名称不能重复') {
      _showMessage(widget.store.message!);
      return;
    }
    if (mounted) Navigator.pop(context);
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _archive() async {
    await widget.store.updateAccount(
        widget.account.copyWith(deletedAt: DateTime.now().toIso8601String()));
    if (mounted) Navigator.pop(context);
  }

  Future<void> _adjustBalance(
      BuildContext context, double currentBalance) async {
    final controller = TextEditingController();
    final delta = await showDialog<double>(
        context: context,
        builder: (dialogContext) => AlertDialog(
                title: const Text('余额调整'),
                content: TextField(
                    controller: controller,
                    autofocus: true,
                    keyboardType: const TextInputType.numberWithOptions(
                        decimal: true, signed: true),
                    decoration: const InputDecoration(
                        labelText: '调整金额', hintText: '增加填正数，减少填负数')),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(dialogContext),
                      child: const Text('取消')),
                  FilledButton(
                      onPressed: () => Navigator.pop(dialogContext,
                          double.tryParse(controller.text.trim())),
                      child: const Text('生成账目'))
                ]));
    controller.dispose();
    if (delta == null || delta == 0) return;
    final isIncrease = delta > 0;
    final transactionType = widget.account.type == AccountType.asset
        ? (isIncrease ? TransactionType.income : TransactionType.expense)
        : (isIncrease ? TransactionType.expense : TransactionType.income);
    final transaction = FinanceTransaction(
        id: 'tx-adjust-${DateTime.now().microsecondsSinceEpoch}',
        date: _dateKey(DateTime.now()),
        occurredAt: DateTime.now().toIso8601String(),
        type: transactionType,
        amount: delta.abs(),
        accountId: widget.account.id,
        note: '余额调整（调整前 ${money(currentBalance)}）');
    await widget.store.addTransaction(transaction);
  }

  static String _accountKindLabel(AccountKind value) => const {
        AccountKind.cash: '现金',
        AccountKind.bankCard: '银行卡',
        AccountKind.wechat: '微信',
        AccountKind.alipay: '支付宝',
        AccountKind.foreign: '外币账户',
        AccountKind.fundInvestment: '基金/投资账户（仅记录总额）',
        AccountKind.creditCard: '信用卡',
        AccountKind.loan: '借款',
        AccountKind.other: '其他'
      }[value]!;

  static String _dateKey(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
}
