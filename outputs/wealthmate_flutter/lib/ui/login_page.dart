import 'package:flutter/material.dart';

import '../data/api_client.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({required this.api, required this.onLoggedIn, super.key});

  final ApiClient api;
  final VoidCallback onLoggedIn;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final usernameController = TextEditingController();
  final passwordController = TextEditingController();
  String? message;
  bool loading = false;

  @override
  void dispose() {
    usernameController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Card(
            margin: const EdgeInsets.all(24),
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Form(
                child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('随想记',
                          style: TextStyle(
                              fontSize: 25, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 6),
                      const Text('登录你的本地财富空间',
                          style: TextStyle(
                              color: Color(0xFF87958F), fontSize: 11)),
                      const SizedBox(height: 22),
                      TextField(
                          controller: usernameController,
                          decoration: const InputDecoration(labelText: '用户名')),
                      const SizedBox(height: 12),
                      TextField(
                          controller: passwordController,
                          obscureText: true,
                          decoration: const InputDecoration(labelText: '密码')),
                      if (message != null) ...[
                        const SizedBox(height: 12),
                        Text(message!,
                            style: const TextStyle(
                                color: Color(0xFFB65B55), fontSize: 11)),
                      ],
                      const SizedBox(height: 20),
                      SizedBox(
                          width: double.infinity,
                          child: FilledButton(
                              onPressed: loading ? null : _login,
                              child: Text(loading ? '登录中…' : '登录'))),
                    ]),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _login() async {
    setState(() {
      loading = true;
      message = null;
    });
    try {
      final result = await widget.api
          .login(usernameController.text.trim(), passwordController.text);
      final accessToken =
          result['access_token'] as String? ?? result['token'] as String?;
      if (accessToken == null || accessToken.isEmpty) {
        throw const ApiFailure(ApiFailureKind.server, '登录响应中没有访问令牌');
      }
      widget.api.token = accessToken;
      if (mounted) widget.onLoggedIn();
    } on ApiFailure catch (failure) {
      if (mounted) setState(() => message = failure.message);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }
}
