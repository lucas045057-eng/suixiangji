import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../domain/models.dart';
import '../state/finance_store.dart';
import 'account_detail_page.dart';
import 'category_management_page.dart';
import 'profile_settings_page.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({required this.store, super.key});

  final FinanceStore store;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
        listenable: store,
        builder: (context, _) => SafeArea(
                child: ListView(
                    padding: const EdgeInsets.fromLTRB(22, 24, 22, 100),
                    children: [
                  const Text('我的',
                      style:
                          TextStyle(fontSize: 27, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 5),
                  const Text('数据在你手里，连接状态说清楚',
                      style: TextStyle(color: Color(0xFF87958F), fontSize: 11)),
                  const SizedBox(height: 18),
                  Card(
                      child: ListTile(
                          leading: CircleAvatar(
                              backgroundColor: const Color(0xFFF3B187),
                              child: Text(
                                  (store.profile?.displayName ?? '林默')
                                      .characters
                                      .first,
                                  style: const TextStyle(
                                      color: Color(0xFF56301E),
                                      fontWeight: FontWeight.w800))),
                          title: Text(store.profile?.displayName ?? '林默',
                              style:
                                  const TextStyle(fontWeight: FontWeight.w800)),
                          subtitle: Text(store.isDemoMode
                              ? '本地演示 · 尚未配置同步服务'
                              : '同步服务已配置'),
                          onTap: () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                  builder: (_) =>
                                      ProfileSettingsPage(store: store))))),
                  const SizedBox(height: 12),
                  Card(
                      child: Column(children: [
                    ListTile(
                        leading: const Icon(Icons.manage_accounts_outlined),
                        title: const Text('账户与登录'),
                        subtitle: const Text('修改昵称、用户名和登录密码'),
                        onTap: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                                builder: (_) =>
                                    ProfileSettingsPage(store: store)))),
                  ])),
                  const SizedBox(height: 12),
                  Card(
                      child: Column(children: [
                    ListTile(
                        leading: const Icon(Icons.sync_rounded),
                        title: const Text('同步状态'),
                        subtitle: Text(store.state.syncState.error ??
                            (store.state.syncState.lastSyncedAt == null
                                ? '未同步 · 离线演示/待配置'
                                : '最近同步 ${store.state.syncState.lastSyncedAt}')),
                        trailing: IconButton(
                            onPressed: store.sync,
                            icon: const Icon(Icons.refresh))),
                    const Divider(height: 1),
                    ListTile(
                      leading:
                          const Icon(Icons.account_balance_wallet_outlined),
                      title: const Text('默认支付账户'),
                      subtitle: const Text('自然语言未写账户时使用'),
                      trailing: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                              value: store.state.defaultAccountId,
                              items: store.state.accounts
                                  .where((item) => item.type.name == 'asset')
                                  .map((item) => DropdownMenuItem(
                                      value: item.id, child: Text(item.name)))
                                  .toList(),
                              onChanged: (value) {
                                if (value != null)
                                  store.setDefaultAccount(value);
                              })),
                    ),
                    const Divider(height: 1),
                    const ListTile(
                        leading: Icon(Icons.lock_outline),
                        title: Text('隐私边界'),
                        subtitle: Text('备注不写入 Agent 日志；未配置外部服务时不会发送数据。')),
                  ])),
                  const SizedBox(height: 12),
                  Card(
                      child: Column(children: [
                    const ListTile(
                        leading: Icon(Icons.account_balance_outlined),
                        title: Text('账户名称与账户配置'),
                        subtitle: Text('点击账户即可修改名称、币种、余额和用途')),
                    ...store.state.accounts
                        .where((item) => item.deletedAt == null)
                        .map((account) => Column(children: [
                              const Divider(height: 1),
                              ListTile(
                                  leading: const Icon(
                                      Icons.account_balance_wallet_outlined),
                                  title: Text(account.name),
                                  subtitle: Text(
                                      '${account.currency} · ${account.type == AccountType.asset ? '资产' : '负债'}'),
                                  trailing: const Icon(Icons.chevron_right),
                                  onTap: () => Navigator.of(context).push(
                                      MaterialPageRoute<void>(
                                          builder: (_) => AccountDetailPage(
                                              store: store,
                                              account: account))))
                            ])),
                  ])),
                  const SizedBox(height: 12),
                  Card(
                      child: Column(children: [
                    ListTile(
                        leading: const Icon(Icons.label_outline),
                        title: const Text('管理分类'),
                        subtitle: const Text('新增、改名、归档和恢复自定义分类'),
                        onTap: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                                builder: (_) =>
                                    CategoryManagementPage(store: store)))),
                    const Divider(height: 1),
                    ListTile(
                        leading: const Icon(Icons.summarize_outlined),
                        title: const Text('生成月度报告'),
                        subtitle: Text(store.state.reports.isEmpty
                            ? '还没有本月报告'
                            : store.state.reports.last.title),
                        onTap: store.generateMonthlyReport),
                    const Divider(height: 1),
                    ListTile(
                        leading: const Icon(Icons.download_outlined),
                        title: const Text('复制 JSON 数据'),
                        subtitle: const Text('主动复制当前本地数据，便于备份'),
                        onTap: () async {
                          await Clipboard.setData(
                              ClipboardData(text: store.exportJson()));
                          if (context.mounted)
                            ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('JSON 已复制到剪贴板')));
                        }),
                    const Divider(height: 1),
                    ListTile(
                        leading: const Icon(Icons.restore_rounded),
                        title: const Text('恢复演示数据'),
                        subtitle: const Text('会覆盖当前本地演示数据'),
                        onTap: () => _confirmRestore(context)),
                  ])),
                  const SizedBox(height: 18),
                  const Text(
                      'API 基址与 JWT 通过构建参数注入：WEALTHMATE_API_BASE_URL / WEALTHMATE_API_TOKEN。当前缺少配置时，客户端只运行离线演示，不会伪造同步成功。',
                      style: TextStyle(
                          color: Color(0xFF87958F), fontSize: 10, height: 1.5)),
                ])));
  }

  Future<void> _confirmRestore(BuildContext context) async {
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
                title: const Text('恢复演示数据？'),
                content: const Text('这会覆盖当前本地数据，未同步的修改也会被移除。'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('取消')),
                  FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('恢复'))
                ]));
    if (confirmed == true) await store.restoreDemoData();
  }
}
