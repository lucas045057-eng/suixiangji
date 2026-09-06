import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wealthmate_flutter/data/finance_repository.dart';
import 'package:wealthmate_flutter/data/local_repository.dart';
import 'package:wealthmate_flutter/data/sync_queue.dart';
import 'package:wealthmate_flutter/domain/models.dart';
import 'package:wealthmate_flutter/state/finance_store.dart';
import 'package:wealthmate_flutter/ui/theme.dart';
import 'package:wealthmate_flutter/ui/transaction_detail_page.dart';

class Dc03Memory implements KeyValueStore {
  final Map<String, String> values = {};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;
}

const dc03Transaction = FinanceTransaction(
  id: 'tx-edit-existing',
  date: '2026-09-05',
  type: TransactionType.expense,
  amount: 22.02,
  currency: 'CNY',
  categoryId: 'android-b-expense-category',
  accountId: 'android-b-account',
  note: 'DC02-WINDOWS-TO-ANDROID',
  clientOpId: 'tx-edit-existing',
  serverVersion: 9,
);

FinanceStore dc03Store() {
  return FinanceStore(
    repository: FinanceRepository(
      local: LocalRepository(Dc03Memory()),
      queue: SyncQueue(),
    ),
    initialState: const FinanceState(
      currentMonth: '2026-09',
      accounts: [
        Account(
          id: 'android-b-account',
          name: 'Android B测试账户',
          type: AccountType.asset,
        ),
      ],
      categories: [
        Category(
          id: 'android-b-expense-category',
          name: 'Android B测试支出',
        ),
      ],
      transactions: [dc03Transaction],
    ),
  );
}

Future<void> submitDc03Edit(WidgetTester tester, FinanceStore store) async {
  await tester.pumpWidget(MaterialApp(
    theme: wealthMateTheme(),
    home: TransactionDetailPage(
      store: store,
      transaction: store.state.transactions.single,
    ),
  ));
  await tester.tap(find.byTooltip('编辑'));
  await tester.pumpAndSettle();

  expect(find.text('编辑账目'), findsOneWidget);
  final fields = find.byType(TextFormField);
  expect(fields, findsNWidgets(4));
  await tester.enterText(fields.at(0), '23.03');
  await tester.enterText(fields.at(3), 'DC03-ANDROID-EDIT-WINDOWS-TX');
  final saveButton = find.text('保存修改');
  await tester.ensureVisible(saveButton);
  await tester.tap(saveButton);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
      'RED-01 editing an existing transaction updates the same local entity',
      (tester) async {
    final store = dc03Store();

    await submitDc03Edit(tester, store);

    expect(store.state.transactions, hasLength(1));
    final updated = store.state.transactions.single;
    expect(updated.id, 'tx-edit-existing');
    expect(updated.amount, 23.03);
    expect(updated.note, 'DC03-ANDROID-EDIT-WINDOWS-TX');
  });

  testWidgets('RED-02 edit submission enqueues one transaction upsert',
      (tester) async {
    final store = dc03Store();

    await submitDc03Edit(tester, store);

    final operations = store.repository.queue.pending();
    expect(operations, hasLength(1));
    final operation = operations.single;
    expect(operation.entity, 'transactions');
    expect(operation.entityId, 'tx-edit-existing');
    expect(operation.type, SyncOperationType.upsert);
    expect(operation.clientOpId, isNot('tx-edit-existing'));
    expect(operation.clientOpId, startsWith('edit-'));
    expect(operation.payload['amount'], 23.03);
    expect(operation.payload['note'], 'DC03-ANDROID-EDIT-WINDOWS-TX');
  });

  testWidgets('RED-03 edit submission does not create a second transaction',
      (tester) async {
    final store = dc03Store();

    await submitDc03Edit(tester, store);

    expect(store.state.transactions.map((item) => item.id),
        ['tx-edit-existing']);
  });

  testWidgets('RED-04 edit submission queues the latest complete snapshot',
      (tester) async {
    final store = dc03Store();

    await submitDc03Edit(tester, store);

    final payload = store.repository.queue.pending().single.payload;
    expect(payload, containsPair('id', 'tx-edit-existing'));
    expect(payload, containsPair('amount', 23.03));
    expect(payload, containsPair('currency', 'CNY'));
    expect(payload,
        containsPair('category_id', 'android-b-expense-category'));
    expect(payload, containsPair('account_id', 'android-b-account'));
    expect(payload, containsPair('note', 'DC03-ANDROID-EDIT-WINDOWS-TX'));
    expect(payload['client_op_id'], isNot('tx-edit-existing'));
    expect(payload['client_op_id'], startsWith('edit-'));
  });

  testWidgets('RED-UI edit returns to a detail page with the latest values',
      (tester) async {
    final store = dc03Store();

    await submitDc03Edit(tester, store);

    expect(find.text('23.03 CNY'), findsOneWidget);
    expect(find.text('DC03-ANDROID-EDIT-WINDOWS-TX'), findsOneWidget);
  });
}
