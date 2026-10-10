import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../features/auth/state/auth_store.dart';

class RecoveryCodePage extends StatefulWidget {
  const RecoveryCodePage({required this.auth, super.key});
  final AuthStore auth;
  @override
  State<RecoveryCodePage> createState() => _RecoveryCodePageState();
}

class _RecoveryCodePageState extends State<RecoveryCodePage> {
  final password = TextEditingController();
  String? code, message;
  bool busy = false;
  @override
  void dispose() {
    code = null;
    password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: const Text('保存恢复码')),
      body: ListView(padding: const EdgeInsets.all(22), children: [
        const Text('恢复码可用于忘记密码时重置账号密码。请保存到安全位置；重新生成会使上一份失效。'),
        const SizedBox(height: 16),
        if (code == null) ...[
          TextField(
              controller: password,
              obscureText: true,
              decoration: const InputDecoration(labelText: '当前密码')),
          if (message != null) Text(message!),
          FilledButton(
              onPressed: busy
                  ? null
                  : () async {
                      setState(() => busy = true);
                      final next =
                          await widget.auth.generateRecoveryCode(password.text);
                      if (!mounted) return;
                      password.clear();
                      setState(() {
                        busy = false;
                        code = next;
                        message = widget.auth.message;
                      });
                    },
              child: Text(busy ? '生成中…' : '生成恢复码')),
        ] else ...[
          const Text('仅在本次页面显示，请现在保存。使用一次后需要重新生成。'),
          const SizedBox(height: 16),
          SelectableText(code!,
              style:
                  const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          TextButton.icon(
              onPressed: () => Clipboard.setData(ClipboardData(text: code!)),
              icon: const Icon(Icons.copy),
              label: const Text('复制恢复码')),
          FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('我已保存')),
        ]
      ]));
}
