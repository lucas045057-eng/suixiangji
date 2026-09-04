import 'package:flutter/material.dart';

import '../domain/models.dart';
import '../state/finance_store.dart';

class CategoryManagementPage extends StatelessWidget {
  const CategoryManagementPage({required this.store, super.key});

  final FinanceStore store;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('管理分类'),
        actions: [
          IconButton(
              onPressed: () => _add(context),
              icon: const Icon(Icons.add),
              tooltip: '新增分类')
        ],
      ),
      body: ListenableBuilder(
        listenable: store,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.fromLTRB(22, 10, 22, 30),
          children: [
            const Text('分类只会归档，不会删除历史账目。',
                style: TextStyle(color: Color(0xFF87958F), fontSize: 11)),
            const SizedBox(height: 14),
            Card(
              child: Column(
                children: [
                  for (final category in store.state.categories)
                    ListTile(
                      leading: CircleAvatar(
                        backgroundColor: category.active
                            ? const Color(0xFFE6F6EF)
                            : const Color(0xFFF0F2F0),
                        child: Icon(
                            category.type == TransactionType.income
                                ? Icons.south_west_rounded
                                : Icons.north_east_rounded,
                            size: 16,
                            color: category.active
                                ? const Color(0xFF2F9F7D)
                                : const Color(0xFF87958F)),
                      ),
                      title: Text(category.name,
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                      subtitle: Text(
                          category.active
                              ? (category.type == TransactionType.income
                                  ? '收入分类'
                                  : '支出分类')
                              : '已归档',
                          style: const TextStyle(fontSize: 11)),
                      trailing: IconButton(
                          onPressed: () => _edit(context, category),
                          icon: Icon(category.active
                              ? Icons.edit_outlined
                              : Icons.restore_outlined)),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _add(BuildContext context) async {
    final controller = TextEditingController();
    var type = TransactionType.expense;
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('新增分类'),
        content: StatefulBuilder(
          builder: (context, setState) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                  controller: controller,
                  autofocus: true,
                  decoration: const InputDecoration(labelText: '分类名称')),
              const SizedBox(height: 12),
              DropdownButtonFormField<TransactionType>(
                initialValue: type,
                decoration: const InputDecoration(labelText: '分类用途'),
                items: const [
                  DropdownMenuItem(
                      value: TransactionType.expense, child: Text('支出')),
                  DropdownMenuItem(
                      value: TransactionType.income, child: Text('收入'))
                ],
                onChanged: (value) => setState(() => type = value ?? type),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(
                  dialogContext, controller.text.trim().isNotEmpty),
              child: const Text('保存')),
        ],
      ),
    );
    if (saved == true)
      await store.addCategory(name: controller.text.trim(), type: type);
    controller.dispose();
  }

  Future<void> _edit(BuildContext context, Category category) async {
    final controller = TextEditingController(text: category.name);
    final active = category.active;
    final action = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(active ? '编辑 ${category.name}' : '恢复 ${category.name}'),
        content: TextField(
            controller: controller,
            decoration: const InputDecoration(labelText: '分类名称')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, 'cancel'),
              child: const Text('取消')),
          if (active)
            TextButton(
                onPressed: () => Navigator.pop(dialogContext, 'archive'),
                child: const Text('归档')),
          FilledButton(
              onPressed: () => Navigator.pop(dialogContext, 'save'),
              child: Text(active ? '保存' : '恢复')),
        ],
      ),
    );
    if (action == 'archive') {
      await store.archiveCategory(category.id);
    } else if (action == 'save') {
      await store.updateCategory(category.id,
          name: controller.text.trim().isEmpty
              ? category.name
              : controller.text.trim(),
          active: true);
    }
    controller.dispose();
  }
}
