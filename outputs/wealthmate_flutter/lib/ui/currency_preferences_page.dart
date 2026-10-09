import 'package:flutter/material.dart';
import '../features/ledger/state/ledger_store.dart';

class CurrencyPreferencesPage extends StatefulWidget {
  const CurrencyPreferencesPage({required this.ledger, super.key});
  final LedgerStore ledger;
  @override
  State<CurrencyPreferencesPage> createState() =>
      _CurrencyPreferencesPageState();
}

class _CurrencyPreferencesPageState extends State<CurrencyPreferencesPage> {
  late final preferred =
      TextEditingController(text: widget.ledger.state.preferredCurrency);
  late final common = TextEditingController(
      text: widget.ledger.state.commonCurrencies.join(', '));
  String? message;
  @override
  void dispose() {
    preferred.dispose();
    common.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: const Text('记账币种')),
      body: ListView(padding: const EdgeInsets.all(22), children: [
        const Text('用于本机新账单和快捷记草稿。已有账单保留原始币种。'),
        TextField(
            controller: preferred,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(labelText: '默认币种')),
        TextField(
            controller: common,
            decoration: const InputDecoration(
                labelText: '常用币种', hintText: 'CNY, HKD, USD')),
        if (message != null) Text(message!),
        FilledButton(
            onPressed: () async {
              try {
                await widget.ledger.setCurrencyPreferences(
                    preferred.text.trim(),
                    common.text
                        .split(RegExp(r'[,，\s]+'))
                        .where((s) => s.isNotEmpty)
                        .toList());
                if (context.mounted) Navigator.pop(context);
              } catch (error) {
                setState(() => message = '$error');
              }
            },
            child: const Text('保存')),
      ]));
}
