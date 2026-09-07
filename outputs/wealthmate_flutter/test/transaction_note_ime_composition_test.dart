import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wealthmate_flutter/data/finance_repository.dart';
import 'package:wealthmate_flutter/data/local_repository.dart';
import 'package:wealthmate_flutter/data/sync_queue.dart';
import 'package:wealthmate_flutter/domain/models.dart';
import 'package:wealthmate_flutter/state/finance_store.dart';
import 'package:wealthmate_flutter/ui/theme.dart';
import 'package:wealthmate_flutter/ui/transaction_detail_page.dart';
import 'package:wealthmate_flutter/ui/widgets/transaction_form.dart';

class NoteImeMemory implements KeyValueStore {
  final Map<String, String> values = {};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;
}

const noteImeTransaction = FinanceTransaction(
  id: 'tx-ime-edit',
  date: '2026-09-07',
  type: TransactionType.expense,
  amount: 91.91,
  currency: 'CNY',
  categoryId: 'food',
  accountId: 'wallet',
  note: 'FINAL-RC-CREATE',
  clientOpId: 'create-op',
  serverVersion: 25,
);

FinanceStore noteImeStore() {
  return FinanceStore(
    repository: FinanceRepository(
      local: LocalRepository(NoteImeMemory()),
      queue: SyncQueue(),
    ),
    initialState: const FinanceState(
      currentMonth: '2026-09',
      accounts: [
        Account(id: 'wallet', name: '测试账户', type: AccountType.asset),
      ],
      categories: [
        Category(id: 'food', name: '餐饮'),
      ],
      transactions: [noteImeTransaction],
    ),
  );
}

void main() {
  testWidgets('editing transaction commits composing note before save',
      (tester) async {
    final store = noteImeStore();

    await tester.pumpWidget(MaterialApp(
      theme: wealthMateTheme(),
      home: TransactionDetailPage(
        store: store,
        transaction: store.state.transactions.single,
      ),
    ));
    await tester.tap(find.byTooltip('编辑'));
    await tester.pumpAndSettle();

    final fields = find.byType(TextFormField);
    expect(fields, findsNWidgets(4));
    await tester.tap(fields.at(3));
    final editable = tester.widget<EditableText>(
        find.descendant(of: fields.at(3), matching: find.byType(EditableText)));
    const composingNote = 'FINAL-RC-WINDOWS-EDIT';
    tester.testTextInput.updateEditingValue(const TextEditingValue(
      text: composingNote,
      selection: TextSelection.collapsed(offset: 21),
      composing: TextRange(start: 0, end: 21),
    ));
    await tester.pump();

    expect(editable.controller.text, composingNote);
    void restoreComposingNoteAfterFocusLoss() {
      if (editable.focusNode.hasFocus) return;
      editable.controller.clear();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        editable.controller.value = const TextEditingValue(
          text: composingNote,
          selection: TextSelection.collapsed(offset: 21),
        );
      });
    }

    editable.focusNode.addListener(restoreComposingNoteAfterFocusLoss);
    addTearDown(() =>
        editable.focusNode.removeListener(restoreComposingNoteAfterFocusLoss));

    final saveButton = find.text('保存修改');
    await tester.ensureVisible(saveButton);
    final gesture = await tester.startGesture(
      tester.getCenter(saveButton),
      kind: PointerDeviceKind.mouse,
    );
    await gesture.up();
    await tester.pumpAndSettle();

    expect(store.state.transactions.single.note, 'FINAL-RC-WINDOWS-EDIT');
  });

  testWidgets('committed note text remains unchanged when saving an edit',
      (tester) async {
    final store = noteImeStore();

    await tester.pumpWidget(MaterialApp(
      theme: wealthMateTheme(),
      home: TransactionDetailPage(
        store: store,
        transaction: store.state.transactions.single,
      ),
    ));
    await tester.tap(find.byTooltip('编辑'));
    await tester.pumpAndSettle();

    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(3), 'FINAL-NORMAL-NOTE');
    final saveButton = find.text('保存修改');
    await tester.ensureVisible(saveButton);
    await tester.tap(saveButton);
    await tester.pumpAndSettle();

    expect(store.state.transactions.single.note, 'FINAL-NORMAL-NOTE');
  });

  testWidgets('creating a transaction with an explicit note preserves it',
      (tester) async {
    final store = noteImeStore();

    await tester.pumpWidget(MaterialApp(
      theme: wealthMateTheme(),
      home: Scaffold(body: TransactionForm(store: store)),
    ));
    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), '3.21');
    await tester.enterText(fields.at(3), 'CREATE-EXPLICIT-NOTE');
    final createButton = find.text('确认入账');
    await tester.ensureVisible(createButton);
    await tester.tap(createButton);
    await tester.pumpAndSettle();

    expect(store.state.transactions, hasLength(2));
    expect(store.state.transactions.last.note, 'CREATE-EXPLICIT-NOTE');
  });

  testWidgets('a truly empty edit note keeps the existing category fallback',
      (tester) async {
    final store = noteImeStore();

    await tester.pumpWidget(MaterialApp(
      theme: wealthMateTheme(),
      home: TransactionDetailPage(
        store: store,
        transaction: store.state.transactions.single,
      ),
    ));
    await tester.tap(find.byTooltip('编辑'));
    await tester.pumpAndSettle();

    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(3), '');
    final saveButton = find.text('保存修改');
    await tester.ensureVisible(saveButton);
    await tester.tap(saveButton);
    await tester.pumpAndSettle();

    expect(store.state.transactions.single.note, '餐饮');
  });
}
