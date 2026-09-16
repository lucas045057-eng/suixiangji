import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wealthmate_flutter/core/database/local_state_session.dart';
import 'package:wealthmate_flutter/data/local_repository.dart';
import 'package:wealthmate_flutter/data/sync_queue.dart';
import 'package:wealthmate_flutter/domain/models.dart';
import 'package:wealthmate_flutter/features/ledger/data/ledger_repository.dart';
import 'package:wealthmate_flutter/features/ledger/state/ledger_store.dart';
import 'package:wealthmate_flutter/ui/widgets/draft_editor.dart';
import 'package:wealthmate_flutter/ui/widgets/transaction_form.dart';

class _Memory implements KeyValueStore {
  final Map<String, String> values = <String, String>{};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }
}

LedgerStore _store({List<Category>? categories}) {
  final session = LocalStateSession(
    local: LocalRepository(_Memory()),
    queue: SyncQueue(),
  );
  return LedgerStore(
    repository: LedgerRepository(session: session),
    initialState: FinanceState(
      currentMonth: '2026-09',
      defaultAccountId: 'wallet',
      accounts: const [
        Account(id: 'wallet', name: '钱包', type: AccountType.asset),
      ],
      categories: categories ??
          const [
            Category(id: 'food', name: '餐饮'),
            Category(id: 'salary', name: '工资', type: TransactionType.income),
          ],
    ),
  );
}

Future<void> _pumpForm(WidgetTester tester, LedgerStore store,
    {FinanceTransaction? initial}) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(body: TransactionForm(ledger: store, initial: initial)),
  ));
}

void main() {
  testWidgets('TransactionForm resets category when the type changes',
      (tester) async {
    final store = _store();
    await _pumpForm(tester, store);

    await tester.enterText(find.widgetWithText(TextFormField, '金额'), '88');
    await tester.tap(find.text('收入'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('确认入账'));
    await tester.tap(find.text('确认入账'));
    await tester.pumpAndSettle();

    expect(store.transactions.single.type, TransactionType.income);
    expect(store.transactions.single.categoryId, 'salary');
  });

  testWidgets(
      'TransactionForm keeps an archived matching category while editing',
      (tester) async {
    final store = _store(categories: const [
      Category(id: 'old-food', name: '旧餐饮', active: false),
      Category(id: 'salary', name: '工资', type: TransactionType.income),
    ]);
    const existing = FinanceTransaction(
      id: 'tx-edit',
      date: '2026-09-10',
      type: TransactionType.expense,
      amount: 12,
      categoryId: 'old-food',
      accountId: 'wallet',
    );

    await _pumpForm(tester, store, initial: existing);

    expect(find.text('旧餐饮'), findsOneWidget);
    expect(find.text('工资'), findsNothing);
  });

  testWidgets('DraftEditor resets category when the type changes',
      (tester) async {
    const draft = AgentDraft(
      amount: 32,
      type: TransactionType.expense,
      categoryId: 'food',
      accountId: 'wallet',
      date: '2026-09-10',
      note: '午餐',
      confidence: .9,
    );
    const state = FinanceState(
      accounts: [Account(id: 'wallet', name: '钱包', type: AccountType.asset)],
      categories: [
        Category(id: 'food', name: '餐饮'),
        Category(id: 'salary', name: '工资', type: TransactionType.income),
      ],
    );
    AgentDraft? saved;

    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (context) {
        return FilledButton(
          onPressed: () async {
            saved = await showDraftEditor(context, draft: draft, state: state);
          },
          child: const Text('open'),
        );
      }),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('收入'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存修改'));
    await tester.pumpAndSettle();

    expect(saved?.type, TransactionType.income);
    expect(saved?.categoryId, 'salary');
  });
}
