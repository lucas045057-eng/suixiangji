import 'package:flutter/material.dart';

class CurrencyInput extends StatefulWidget {
  const CurrencyInput(
      {required this.value,
      required this.common,
      required this.onChanged,
      this.label = '原始币种',
      super.key});
  final String value;
  final List<String> common;
  final ValueChanged<String> onChanged;
  final String label;
  @override
  State<CurrencyInput> createState() => _CurrencyInputState();
}

class _CurrencyInputState extends State<CurrencyInput> {
  late final TextEditingController controller =
      TextEditingController(text: widget.value);
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        TextFormField(
            controller: controller,
            textCapitalization: TextCapitalization.characters,
            decoration: InputDecoration(
                labelText: widget.label, hintText: '例如 CNY、HKD、USD'),
            validator: (value) => RegExp(r'^[A-Z]{3}$')
                    .hasMatch((value ?? '').trim().toUpperCase())
                ? null
                : '请输入三个字母的币种代码',
            onChanged: (value) => widget.onChanged(value.trim().toUpperCase())),
        Wrap(spacing: 6, children: [
          for (final code in {...widget.common, widget.value})
            ActionChip(
                label: Text(code),
                onPressed: () => setState(() {
                      controller.text = code;
                      widget.onChanged(code);
                    }))
        ]),
      ]);
}
