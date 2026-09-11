import 'package:flutter/material.dart';

import '../features/auth/state/auth_store.dart';

class RegisterPage extends StatefulWidget {
  const RegisterPage({required this.auth, required this.onLoggedIn, super.key});

  final AuthStore auth;
  final VoidCallback onLoggedIn;

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final _form = GlobalKey<FormState>();
  final _username = TextEditingController();
  final _nickname = TextEditingController();
  final _password = TextEditingController();
  final _confirmation = TextEditingController();
  final _invite = TextEditingController();
  bool _loading = false;
  String? _message;

  @override
  void dispose() {
    for (final controller in [
      _username,
      _nickname,
      _password,
      _confirmation,
      _invite,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: !_loading,
        child: Scaffold(
          appBar: AppBar(title: const Text('注册账号')),
          body: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Form(
                  key: _form,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        '欢迎加入随想记',
                        style: TextStyle(
                            fontSize: 24, fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 8),
                      const Text('Beta 测试需要邀请码。请使用自己的账号保存财务数据。'),
                      const SizedBox(height: 20),
                      TextFormField(
                        controller: _username,
                        enabled: !_loading,
                        decoration: const InputDecoration(labelText: '用户名'),
                        validator: (value) =>
                            RegExp(r'^[a-zA-Z0-9_-]{3,32}$')
                                    .hasMatch(value?.trim() ?? '')
                                ? null
                                : '请填写 3–32 位字母、数字、下划线或连字符',
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _nickname,
                        enabled: !_loading,
                        decoration: const InputDecoration(
                            labelText: '昵称', hintText: '可选，最多 128 字符'),
                        validator: (value) =>
                            (value?.trim().runes.length ?? 0) > 128
                                ? '昵称最多 128 字符'
                                : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _password,
                        enabled: !_loading,
                        obscureText: true,
                        decoration: const InputDecoration(labelText: '密码'),
                        validator: (value) =>
                            (value?.runes.length ?? 0) < 8 ||
                                    (value?.runes.length ?? 0) > 256
                                ? '密码需为 8–256 字符'
                                : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _confirmation,
                        enabled: !_loading,
                        obscureText: true,
                        decoration:
                            const InputDecoration(labelText: '确认密码'),
                        validator: (value) =>
                            value != _password.text ? '两次密码不一致' : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _invite,
                        enabled: !_loading,
                        decoration: const InputDecoration(labelText: '邀请码'),
                        validator: (value) => (value?.trim().isEmpty ?? true)
                            ? '请输入邀请码'
                            : null,
                      ),
                      if (_message != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Text(
                            _message!,
                            style: const TextStyle(color: Color(0xFFB65B55)),
                          ),
                        ),
                      const SizedBox(height: 20),
                      FilledButton(
                        onPressed: _loading ? null : _register,
                        child: Text(_loading ? '正在创建账号…' : '注册并登录'),
                      ),
                      TextButton(
                        onPressed:
                            _loading ? null : () => Navigator.of(context).pop(),
                        child: const Text('已有账号？返回登录'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );

  Future<void> _register() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _message = null;
    });
    try {
      if (await widget.auth.register(
        username: _username.text,
        password: _password.text,
        displayName: _nickname.text,
        inviteCode: _invite.text,
      )) {
        if (mounted) widget.onLoggedIn();
      } else if (mounted) {
        setState(() => _message = widget.auth.message);
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }
}
