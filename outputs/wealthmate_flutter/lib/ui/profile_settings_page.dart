import 'package:flutter/material.dart';

import '../features/auth/state/auth_store.dart';
import '../state/finance_store.dart';

class ProfileSettingsPage extends StatefulWidget {
  const ProfileSettingsPage({required this.store, this.auth, super.key});

  final FinanceStore store;
  final AuthStore? auth;

  @override
  State<ProfileSettingsPage> createState() => _ProfileSettingsPageState();
}

class _ProfileSettingsPageState extends State<ProfileSettingsPage> {
  late final TextEditingController displayNameController;
  late final TextEditingController usernameController;
  final currentPasswordController = TextEditingController();
  final newPasswordController = TextEditingController();
  final confirmPasswordController = TextEditingController();
  bool _deleting = false;

  @override
  void initState() {
    super.initState();
    final auth = widget.auth ?? widget.store.authStore;
    final profile = auth?.profile ?? widget.store.profile;
    displayNameController =
        TextEditingController(text: profile?.displayName ?? '');
    usernameController = TextEditingController(text: profile?.username ?? '');
    if (!widget.store.isDemoMode && auth != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        auth.loadProfile().then((loaded) {
          if (!loaded || !mounted || auth.profile == null) return;
          setState(() {
            displayNameController.text = auth.profile!.displayName;
            usernameController.text = auth.profile!.username;
          });
        });
      });
    }
  }

  @override
  void dispose() {
    displayNameController.dispose();
    usernameController.dispose();
    currentPasswordController.dispose();
    newPasswordController.dispose();
    confirmPasswordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('账户与登录')),
      body: ListenableBuilder(
        listenable: widget.store,
        builder: (context, _) => ListView(
            padding: const EdgeInsets.fromLTRB(22, 12, 22, 32),
            children: [
              const Text('修改登录资料',
                  style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              const Text('这些信息会同步到使用同一账号的设备。',
                  style: TextStyle(color: Color(0xFF87958F), fontSize: 11)),
              const SizedBox(height: 18),
              TextField(
                  controller: displayNameController,
                  enabled: !widget.store.isDemoMode,
                  decoration: const InputDecoration(labelText: '显示名称')),
              const SizedBox(height: 12),
              TextField(
                  controller: usernameController,
                  enabled: !widget.store.isDemoMode,
                  decoration: const InputDecoration(labelText: '登录用户名')),
              const SizedBox(height: 14),
              SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                      onPressed: widget.store.isDemoMode ? null : _saveProfile,
                      child: const Text('保存登录资料'))),
              const SizedBox(height: 30),
              const Divider(),
              const SizedBox(height: 18),
              const Text('修改密码',
                  style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              const Text('修改后其他手机需要重新登录。密码不会显示或保存到本机。',
                  style: TextStyle(color: Color(0xFF87958F), fontSize: 11)),
              const SizedBox(height: 18),
              TextField(
                  controller: currentPasswordController,
                  enabled: !widget.store.isDemoMode,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: '当前密码')),
              const SizedBox(height: 12),
              TextField(
                  controller: newPasswordController,
                  enabled: !widget.store.isDemoMode,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: '新密码（至少 8 位）')),
              const SizedBox(height: 12),
              TextField(
                  controller: confirmPasswordController,
                  enabled: !widget.store.isDemoMode,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: '确认新密码')),
              const SizedBox(height: 14),
              SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                      onPressed:
                          widget.store.isDemoMode ? null : _changePassword,
                      child: const Text('保存新密码'))),
              if (widget.store.message != null) ...[
                const SizedBox(height: 14),
                Text(widget.store.message!,
                    style: const TextStyle(
                        color: Color(0xFF4C4A9C), fontSize: 11)),
              ],
              if (!widget.store.isDemoMode) ...[
                const SizedBox(height: 30),
                const Divider(),
                const Text('删除后将永久移除当前账号及其财务数据，其他账号不受影响。'),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                    onPressed: _deleting ? null : _deleteAccount,
                    icon: const Icon(Icons.delete_forever,
                        color: Color(0xFFB65B55)),
                    label: Text(_deleting ? '正在删除…' : '永久删除账号')),
              ],
            ]),
      ),
    );
  }

  Future<void> _saveProfile() async {
    final displayName = displayNameController.text.trim();
    final username = usernameController.text.trim();
    if (displayName.isEmpty || username.length < 3) {
      _show('显示名称不能为空，用户名至少 3 位');
      return;
    }
    final auth = widget.auth ?? widget.store.authStore;
    final saved = await auth?.updateProfile(
            displayName: displayName, username: username) ??
        false;
    if (saved && mounted) _show('登录资料已保存');
  }

  Future<void> _changePassword() async {
    final current = currentPasswordController.text;
    final next = newPasswordController.text;
    if (current.isEmpty ||
        next.length < 8 ||
        next != confirmPasswordController.text) {
      _show('请填写当前密码，并确认新密码至少 8 位且两次一致');
      return;
    }
    final auth = widget.auth ?? widget.store.authStore;
    final saved = await auth?.changePassword(current, next) ?? false;
    if (saved && mounted) {
      currentPasswordController.clear();
      newPasswordController.clear();
      confirmPasswordController.clear();
      _show('密码已保存，请在其他设备重新登录');
    }
  }

  Future<void> _deleteAccount() async {
    final password = await showDialog<String>(
        context: context, builder: (_) => const _DeleteAccountDialog());
    if (password == null || !mounted) return;
    setState(() => _deleting = true);
    try {
      final deleted = await widget.store.deleteAccount(password);
      if (!mounted) return;
      if (deleted) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      } else {
        _show(widget.store.message ?? '删除未完成，请稍后重试');
      }
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  void _show(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

class _DeleteAccountDialog extends StatefulWidget {
  const _DeleteAccountDialog();

  @override
  State<_DeleteAccountDialog> createState() => _DeleteAccountDialogState();
}

class _DeleteAccountDialogState extends State<_DeleteAccountDialog> {
  final _password = TextEditingController();
  bool _confirmed = false;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('永久删除当前账号？'),
        content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('账号与云端、本机的当前账号数据将永久删除，无法撤销。'),
          const SizedBox(height: 14),
          TextField(
              controller: _password,
              obscureText: true,
              decoration: const InputDecoration(labelText: '删除验证密码')),
          CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _confirmed,
              onChanged: (value) => setState(() => _confirmed = value ?? false),
              title: const Text('我确认永久删除当前账号及其数据')),
          if (_error != null)
            Text(_error!, style: const TextStyle(color: Color(0xFFB65B55))),
        ])),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context), child: const Text('取消')),
          FilledButton(
              onPressed: () {
                if (_password.text.isEmpty || !_confirmed) {
                  setState(() => _error = '请输入当前密码并勾选删除确认');
                  return;
                }
                Navigator.pop(context, _password.text);
              },
              child: const Text('确认永久删除')),
        ],
      );
}
