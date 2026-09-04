import 'package:flutter/material.dart';

import '../state/finance_store.dart';

class ProfileSettingsPage extends StatefulWidget {
  const ProfileSettingsPage({required this.store, super.key});

  final FinanceStore store;

  @override
  State<ProfileSettingsPage> createState() => _ProfileSettingsPageState();
}

class _ProfileSettingsPageState extends State<ProfileSettingsPage> {
  late final TextEditingController displayNameController;
  late final TextEditingController usernameController;
  final currentPasswordController = TextEditingController();
  final newPasswordController = TextEditingController();
  final confirmPasswordController = TextEditingController();

  @override
  void initState() {
    super.initState();
    final profile = widget.store.profile;
    displayNameController =
        TextEditingController(text: profile?.displayName ?? '');
    usernameController = TextEditingController(text: profile?.username ?? '');
    if (!widget.store.isDemoMode) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        widget.store.loadProfile().then((_) {
          if (!mounted || widget.store.profile == null) return;
          setState(() {
            displayNameController.text = widget.store.profile!.displayName;
            usernameController.text = widget.store.profile!.username;
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
    final saved = await widget.store
        .updateProfile(displayName: displayName, username: username);
    if (saved && mounted) _show('登录资料已保存');
  }

  Future<void> _changePassword() async {
    final current = currentPasswordController.text;
    final next = newPasswordController.text;
    if (current.isEmpty || next.length < 8 || next != confirmPasswordController.text) {
      _show('请填写当前密码，并确认新密码至少 8 位且两次一致');
      return;
    }
    final saved = await widget.store.changePassword(current, next);
    if (saved && mounted) {
      currentPasswordController.clear();
      newPasswordController.clear();
      confirmPasswordController.clear();
      _show('密码已保存，请在其他设备重新登录');
    }
  }

  void _show(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}
