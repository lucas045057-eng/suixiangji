import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wealthmate_flutter/data/finance_repository.dart';
import 'package:wealthmate_flutter/data/local_repository.dart';
import 'package:wealthmate_flutter/data/sync_queue.dart';
import 'package:wealthmate_flutter/domain/models.dart';
import 'package:wealthmate_flutter/state/finance_store.dart';
import 'package:wealthmate_flutter/ui/theme.dart';
import 'package:wealthmate_flutter/ui/widgets/transaction_form.dart';

class _ImeMemory implements KeyValueStore {
  final Map<String, String> values = {};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;
}

FinanceStore _imeStore() {
  return FinanceStore(
    repository: FinanceRepository(
      local: LocalRepository(_ImeMemory()),
      queue: SyncQueue(),
    ),
    initialState: const FinanceState(
      currentMonth: '2026-11',
      defaultAccountId: 'alipay',
      accounts: [
        Account(id: 'alipay', name: '支付宝', type: AccountType.asset),
      ],
      categories: [Category(id: 'food', name: '餐饮')],
    ),
  );
}

Map<String, dynamic> _clientArgsAfterFocus(
    WidgetTester tester, Finder field) {
  final args = tester.testTextInput.setClientArgs;
  expect(args, isNotNull, reason: 'focusing a text field must open a client');
  return args!;
}

void main() {
  testWidgets('the smart composer keeps the keyboard language the user chose',
      (tester) async {
    final store = _imeStore();
    await tester.pumpWidget(MaterialApp(
      theme: wealthMateTheme(),
      home: Scaffold(body: TransactionForm(store: store, smartMode: true)),
    ));

    final field = find.byType(TextFormField);
    await tester.tap(field);
    await tester.pump();

    final args = _clientArgsAfterFocus(tester, field);
    // Multiline stays: the composer is a four-line box.
    expect((args['inputType'] as Map)['name'], 'TextInputType.multiline');
    expect(args['inputAction'], 'TextInputAction.newline');
    // Suggestions must stay enabled or non-English IMEs become unreachable
    // (flutter/flutter#139143).
    expect(args['enableSuggestions'], isTrue);
    // The hotfix: no language override, and the platform default autocorrect
    // flag (the field used to opt out of TYPE_TEXT_FLAG_AUTO_CORRECT).
    expect(args['hintLocales'], isNull);
    expect(args['autocorrect'], isTrue);
  });

  testWidgets('the manual note field sends the same non-overriding config',
      (tester) async {
    final store = _imeStore();
    await tester.pumpWidget(MaterialApp(
      theme: wealthMateTheme(),
      home: Scaffold(body: TransactionForm(store: store)),
    ));

    final fields = find.byType(TextFormField);
    expect(fields, findsNWidgets(4));
    await tester.ensureVisible(fields.at(3));
    await tester.tap(fields.at(3));
    await tester.pump();

    final args = _clientArgsAfterFocus(tester, fields.at(3));
    expect((args['inputType'] as Map)['name'], 'TextInputType.multiline');
    expect(args['enableSuggestions'], isTrue);
    expect(args['hintLocales'], isNull);
    expect(args['autocorrect'], isTrue);
  });

  testWidgets('raw nine-key pinyin is not submitted before a candidate is chosen',
      (tester) async {
    final store = _imeStore();
    await tester.pumpWidget(MaterialApp(
      theme: wealthMateTheme(),
      home: Scaffold(body: TransactionForm(store: store, smartMode: true)),
    ));

    final field = find.byType(TextFormField);
    await tester.tap(field);
    await tester.pump();

    // What an Android nine-key IME reports while 9-7-6 is still composing.
    tester.testTextInput.updateEditingValue(const TextEditingValue(
      text: 'wsm',
      selection: TextSelection.collapsed(offset: 3),
      composing: TextRange(start: 0, end: 3),
    ));
    await tester.pump();

    final editable = tester.widget<EditableText>(
        find.descendant(of: field, matching: find.byType(EditableText)));
    expect(editable.controller.text, 'wsm');
    expect(editable.controller.value.composing.isValid, isTrue);

    // Invoke the button directly so the tap cannot move focus and let the
    // framework clear the composing region first.
    tester
        .widget<FilledButton>(
            find.widgetWithText(FilledButton, '生成待确认草稿'))
        .onPressed!();
    await tester.pump();

    expect(find.textContaining('请先选择候选字'), findsOneWidget);
    expect(store.draft, isNull);
    expect(store.state.transactions, isEmpty);

    // Choosing 外卖吗 collapses the composing region.
    tester.testTextInput.updateEditingValue(const TextEditingValue(
      text: '外卖吗 32 元',
      selection: TextSelection.collapsed(offset: 8),
    ));
    await tester.pump();
    expect(find.textContaining('请先选择候选字'), findsNothing);

    tester
        .widget<FilledButton>(
            find.widgetWithText(FilledButton, '生成待确认草稿'))
        .onPressed!();
    await tester.pumpAndSettle();

    expect(store.state.transactions, isEmpty);
    expect(find.text('已整理成待确认草稿'), findsOneWidget);
  });
}
