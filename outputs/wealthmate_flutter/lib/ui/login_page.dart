import 'package:flutter/material.dart';

import '../features/auth/state/auth_store.dart';
import 'register_page.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({
    required this.auth,
    required this.onLoggedIn,
    this.pendingCleanupMessage,
    this.onRetryCleanup,
    super.key,
  });

  final AuthStore auth;
  final VoidCallback onLoggedIn;
  final String? pendingCleanupMessage;
  final Future<bool> Function()? onRetryCleanup;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final usernameController = TextEditingController();
  final passwordController = TextEditingController();
  String? message;
  bool loading = false;
  bool retryingCleanup = false;
  String? pendingCleanupMessage;

  @override
  void initState() {
    super.initState();
    pendingCleanupMessage = widget.pendingCleanupMessage;
  }

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
                      if (pendingCleanupMessage != null) ...[
                        const SizedBox(height: 14),
                        Text(pendingCleanupMessage!,
                            style: const TextStyle(
                                color: Color(0xFFB65B55), fontSize: 11)),
                        if (widget.onRetryCleanup != null) ...[
                          const SizedBox(height: 8),
                          OutlinedButton(
                              onPressed:
                                  retryingCleanup ? null : _retryCleanup,
                              child: Text(retryingCleanup ? '清理中…' : '重试本机清理')),
                        ],
                      ],
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
                      TextButton(
                          onPressed: loading
                              ? null
                              : () => Navigator.of(context).push(
                                  MaterialPageRoute<void>(
                                      builder: (_) => RegisterPage(
                                          auth: widget.auth,
                                          onLoggedIn: () {
                                            Navigator.of(context).pop();
                                            widget.onLoggedIn();
                                          }))),
                          child: const Text('注册账号')),
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
      if (await widget.auth
          .login(usernameController.text.trim(), passwordController.text)) {
        if (mounted) widget.onLoggedIn();
      } else if (mounted) {
        setState(() => message = widget.auth.message);
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _retryCleanup() async {
    final retry = widget.onRetryCleanup;
    if (retry == null) return;
    setState(() => retryingCleanup = true);
    final cleaned = await retry();
    if (!mounted) return;
    setState(() {
      retryingCleanup = false;
      if (cleaned) pendingCleanupMessage = null;
    });
  }
}
