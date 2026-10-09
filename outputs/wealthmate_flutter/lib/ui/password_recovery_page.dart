import 'package:flutter/material.dart';
import '../features/auth/state/auth_store.dart';

class PasswordRecoveryPage extends StatefulWidget {
  const PasswordRecoveryPage({required this.auth, super.key});
  final AuthStore auth;
  @override
  State<PasswordRecoveryPage> createState() => _PasswordRecoveryPageState();
}

class _PasswordRecoveryPageState extends State<PasswordRecoveryPage> {
  final form = GlobalKey<FormState>();
  final username = TextEditingController(),
      code = TextEditingController(),
      password = TextEditingController(),
      confirmation = TextEditingController();
  bool busy = false;
  String? message;
  @override
  void dispose() {
    username.dispose();
    code.dispose();
    password.dispose();
    confirmation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: const Text('找回密码')),
      body: Form(
          key: form,
          child: ListView(padding: const EdgeInsets.all(22), children: [
            const Text('使用你预先保存的恢复码。重置成功后，恢复码和其他设备的旧登录都会失效。'),
            const SizedBox(height: 16),
            TextFormField(
                controller: username,
                decoration: const InputDecoration(labelText: '用户名'),
                validator: (v) => (v ?? '').trim().isEmpty ? '请输入用户名' : null),
            TextFormField(
                controller: code,
                autocorrect: false,
                enableSuggestions: false,
                decoration: const InputDecoration(labelText: '已保存的恢复码'),
                validator: (v) => (v ?? '').trim().isEmpty ? '请输入恢复码' : null),
            TextFormField(
                controller: password,
                obscureText: true,
                decoration: const InputDecoration(labelText: '新密码'),
                validator: (v) => v == null || v.length < 8 || v.length > 256
                    ? '密码须为8–256位'
                    : null),
            TextFormField(
                controller: confirmation,
                obscureText: true,
                decoration: const InputDecoration(labelText: '确认新密码'),
                validator: (v) => v != password.text ? '两次密码不一致' : null),
            const SizedBox(height: 16),
            if (message != null)
              Text(message!, style: const TextStyle(color: Color(0xFFB65B55))),
            FilledButton(
                onPressed: busy ? null : _reset,
                child: Text(busy ? '重置中…' : '重置密码')),
            const SizedBox(height: 12),
            const Text('没有预先保存恢复码时，无法通过此入口恢复。登录后可在“账户与登录”中生成并安全保存。'),
          ])));
  Future<void> _reset() async {
    if (!form.currentState!.validate()) return;
    setState(() => busy = true);
    final success = await widget.auth
        .recoverPassword(username.text, code.text, password.text);
    if (!mounted) return;
    if (success) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('密码已重置，请使用新密码登录')));
      Navigator.pop(context);
    } else {
      setState(() {
        busy = false;
        message = widget.auth.message;
      });
    }
  }
}
