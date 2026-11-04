import 'package:flutter/material.dart';

import '../domain/models.dart';
import '../features/assets/state/asset_store.dart';
import 'theme.dart';
import 'widgets/ui_helpers.dart';

class AccountDetailPage extends StatefulWidget {
  const AccountDetailPage(
      {required this.store, required this.account, super.key});

  final AssetStore store;
  final Account account;

  @override
  State<AccountDetailPage> createState() => _AccountDetailPageState();
}

class _AccountDetailPageState extends State<AccountDetailPage> {
  late final TextEditingController nameController;
  late final TextEditingController currencyController;
  late final TextEditingController openingController;
  late final TextEditingController noteController;
  late Account _account;
  late AccountType type;
  late AccountKind accountKind;
  late bool isDefaultPayment;

  @override
  void initState() {
    super.initState();
    final account = widget.account;
    _account = account;
    nameController = TextEditingController(text: account.name);
    noteController = TextEditingController(text: account.note);
    currencyController = TextEditingController(text: account.currency);
    openingController =
        TextEditingController(text: account.openingBalance.toString());
    type = account.type;
    accountKind = account.accountKind;
    isDefaultPayment = account.isDefaultPayment;
  }

  @override
  void dispose() {
    nameController.dispose();
    currencyController.dispose();
    openingController.dispose();
    noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('账户配置')),
      body: ListenableBuilder(
        listenable: widget.store,
        builder: (context, _) {
          final entry = widget.store.metrics.accountBalances
              .where((item) => item.account.id == widget.account.id)
              .firstOrNull;
          // Archived accounts are absent from the active balance list. Fall
          // back to their frozen opening rather than labelling a known CNY
          // account as pending.
          final archived = widget.store.accounts
                  .where((item) => item.id == widget.account.id)
                  .firstOrNull ??
              widget.account;
          final isCny = archived.currency.toUpperCase() == 'CNY';
          final balance = entry?.balance ??
              (isCny ? archived.openingBalance : archived.openingCnyAmount);
          final pending = entry?.isPending ?? (!isCny && balance == null);
          return ListView(
            padding: const EdgeInsets.fromLTRB(22, 10, 22, 32),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('当前计算余额', style: paSectionLabel),
                      const SizedBox(height: 8),
                      FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(pending ? '待换算' : money(balance ?? 0),
                              style: paNumberLarge.copyWith(
                                  fontSize: 34,
                                  color: pending ? paWarn : paInk))),
                      const SizedBox(height: 6),
                      if (pending)
                        const Text(
                            '该账户缺少人民币汇率快照或存在待换算账目；请到「财富 → 管理汇率」保存对应币种汇率后自动换算。',
                            style: TextStyle(color: paWarn, fontSize: 10))
                      else
                        const Text('余额由初始余额和已确认账目计算，可通过校准修正。',
                            style: TextStyle(color: paInkFaint, fontSize: 10)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                  controller: nameController,
                  decoration: const InputDecoration(labelText: '账户名称')),
              const SizedBox(height: 12),
              TextField(
                  controller: noteController,
                  maxLength: 256,
                  keyboardType: TextInputType.text,
                  decoration: const InputDecoration(
                      labelText: '用途备注', hintText: '例如工资卡、旅行备用')),
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
                  title: const Text('默认支付账户'),
                  value: isDefaultPayment,
                  onChanged: (value) =>
                      setState(() => isDefaultPayment = value)),
              const SizedBox(height: 8),
              FilledButton(onPressed: _save, child: const Text('保存账户配置')),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                  onPressed: () => _calibrateBalance(context),
                  icon: const Icon(Icons.tune),
                  label: const Text('余额校准')),
              const SizedBox(height: 8),
              TextButton.icon(
                  onPressed: _account.archivedAt == null ? _archive : _restore,
                  icon: const Icon(Icons.archive_outlined),
                  label: Text(_account.archivedAt == null ? '归档账户' : '恢复账户'),
                  style: TextButton.styleFrom(foregroundColor: paWarn)),
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
    final updated = _account.copyWith(
        name: name,
        note: noteController.text.trim(),
        type: type,
        accountKind: accountKind,
        currency: currency,
        openingBalance: opening,
        isDefaultPayment: isDefaultPayment);
    await widget.store.updateAccount(updated);
    if (widget.store.message == '账户名称不能重复') {
      _showMessage(widget.store.message!);
      return;
    }
    _account = updated;
    if (mounted) Navigator.pop(context);
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _archive() async {
    await widget.store.archiveAccount(_account.id);
    if (mounted) Navigator.pop(context);
  }

  Future<void> _restore() async {
    await widget.store.restoreAccount(_account.id);
    if (mounted) Navigator.pop(context);
  }

  Future<void> _calibrateBalance(BuildContext context) async {
    final currentAccount = widget.store.accounts
        .where((item) => item.id == widget.account.id)
        .firstOrNull;
    if (currentAccount == null) return;
    final expected = widget.store.expectedBalanceFor(currentAccount);
    final pendingDraft = widget.store.calibrationDraftFor(currentAccount.id);
    final isForeign = currentAccount.currency.toUpperCase() != 'CNY';
    var input = '';
    final targetCny = await showDialog<double>(
        context: context,
        builder: (dialogContext) =>
            StatefulBuilder(builder: (dialogContext, setDialogState) {
              final parsed = double.tryParse(input.trim());
              final valid = parsed != null && parsed.isFinite;
              final target = valid ? parsed : null;
              final delta =
                  target != null && expected != null ? target - expected : null;
              return AlertDialog(
                  title: const Text('余额校准'),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (expected == null)
                        const Text('账户存在待换算账目，请先补充汇率后再校准。',
                            style: TextStyle(color: paWarn, fontSize: 12))
                      else
                        Text('校准前账面额 ${money(expected)}'),
                      if (pendingDraft != null) ...[
                        const SizedBox(height: 4),
                        Text(
                            '上次校准未提交：目标 ${money(pendingDraft.targetCny)} · ${pendingDraft.effectiveOn}',
                            style:
                                const TextStyle(color: paWarn, fontSize: 11)),
                      ],
                      const SizedBox(height: 12),
                      TextField(
                          autofocus: true,
                          enabled: expected != null,
                          onChanged: (value) =>
                              setDialogState(() => input = value),
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true, signed: true),
                          decoration: const InputDecoration(
                              labelText: '校准后账面余额', hintText: '请输入实际人民币账面余额')),
                      if (delta != null && target != null) ...[
                        const SizedBox(height: 12),
                        Text('差额 ${signedMoney(delta)}',
                            style: TextStyle(
                                color: delta == 0 ? paInkSub : paInk,
                                fontSize: 12,
                                fontWeight: FontWeight.w600)),
                        const SizedBox(height: 4),
                        Text('校准后 ${money(target)}',
                            style: const TextStyle(
                                color: paInk,
                                fontSize: 12,
                                fontWeight: FontWeight.w600)),
                      ],
                      const SizedBox(height: 12),
                      const Text('校准会生成一条独立的调整流水，只改账面余额，不计入收支和预算。',
                          style: TextStyle(color: paInkFaint, fontSize: 12)),
                      if (isForeign) ...[
                        const SizedBox(height: 4),
                        const Text('校准的是人民币账面额，不改变原币初始余额。',
                            style: TextStyle(color: paInkFaint, fontSize: 12)),
                      ],
                    ],
                  ),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(dialogContext),
                        child: const Text('取消')),
                    FilledButton(
                        onPressed: expected == null || !valid
                            ? null
                            : () => Navigator.pop(dialogContext, parsed),
                        child: const Text('提交校准'))
                  ]);
            }));
    if (targetCny == null || !targetCny.isFinite) {
      if (mounted && targetCny != null) _showMessage('请输入有效的人民币账面余额');
      return;
    }
    await widget.store.calibrateBalance(currentAccount, targetCny);
    if (mounted) _showMessage(widget.store.message ?? '校准未完成');
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
}
