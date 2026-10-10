import 'package:flutter/material.dart';

import '../domain/models.dart';
import '../features/assets/state/asset_store.dart';
import 'account_detail_page.dart';

/// One searchable account directory serves both active and archived accounts.
class AccountManagementPage extends StatefulWidget {
  const AccountManagementPage({required this.store, super.key});
  final AssetStore store;
  @override
  State<AccountManagementPage> createState() => _AccountManagementPageState();
}

class _AccountManagementPageState extends State<AccountManagementPage> {
  String query = '';
  bool archived = false;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('全部账户')),
        body: ListenableBuilder(
            listenable: widget.store,
            builder: (context, _) {
              final matching = widget.store.accounts
                  .where((a) =>
                      a.deletedAt == null &&
                      (a.archivedAt != null) == archived &&
                      '${a.name} ${a.note} ${a.currency}'
                          .toLowerCase()
                          .contains(query.toLowerCase()))
                  .toList()
                ..sort((a, b) => a.name.compareTo(b.name));
              return Column(children: [
                Padding(
                    padding: const EdgeInsets.all(16),
                    child: TextField(
                        decoration: const InputDecoration(
                            prefixIcon: Icon(Icons.search),
                            hintText: '搜索名称、用途或币种'),
                        onChanged: (value) => setState(() => query = value))),
                SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(value: false, label: Text('使用中')),
                      ButtonSegment(value: true, label: Text('已归档')),
                    ],
                    selected: {
                      archived
                    },
                    onSelectionChanged: (values) =>
                        setState(() => archived = values.first)),
                const SizedBox(height: 12),
                Expanded(
                    child: matching.isEmpty
                        ? const Center(child: Text('没有符合条件的账户'))
                        : ListView(children: [
                            for (final type in AccountType.values)
                              if (matching.any((a) => a.type == type)) ...[
                                Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                        20, 12, 20, 4),
                                    child: Text(
                                        type == AccountType.asset
                                            ? '资产账户'
                                            : '负债账户',
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleSmall)),
                                for (final account
                                    in matching.where((a) => a.type == type))
                                  ListTile(
                                    title: Text(account.name),
                                    subtitle: Text([
                                      account.currency,
                                      if (account.note.isNotEmpty) account.note
                                    ].join(' · ')),
                                    trailing: archived
                                        ? TextButton(
                                            onPressed: () async {
                                              await widget.store
                                                  .restoreAccount(account.id);
                                              if (context.mounted &&
                                                  widget.store.message ==
                                                      '账户名称不能重复') {
                                                ScaffoldMessenger.of(context)
                                                    .showSnackBar(SnackBar(
                                                        content: Text(widget
                                                            .store.message!)));
                                              }
                                            },
                                            child: const Text('恢复'))
                                        : const Icon(Icons.chevron_right),
                                    onTap: () => Navigator.of(context).push(
                                        MaterialPageRoute<void>(
                                            builder: (_) => AccountDetailPage(
                                                store: widget.store,
                                                account: account))),
                                  ),
                              ],
                          ])),
              ]);
            }),
      );
}
