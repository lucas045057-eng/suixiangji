import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wealthmate_flutter/core/database/local_state_session.dart';
import 'package:wealthmate_flutter/data/local_repository.dart';
import 'package:wealthmate_flutter/data/sync_queue.dart';
import 'package:wealthmate_flutter/domain/date_text.dart';
import 'package:wealthmate_flutter/domain/models.dart';
import 'package:wealthmate_flutter/domain/transaction_query.dart';
import 'package:wealthmate_flutter/features/ledger/data/ledger_repository.dart';
import 'package:wealthmate_flutter/features/ledger/state/ledger_store.dart';
import 'package:wealthmate_flutter/ui/ledger_page.dart';
import 'package:wealthmate_flutter/ui/theme.dart';
import 'package:wealthmate_flutter/ui/transaction_detail_page.dart';

class _Atomic implements AtomicKeyValueStore {
  final Map<String, String> values = <String, String>{};
  int writes = 0;

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    writes += 1;
    values[key] = value;
  }

  @override
  Future<void> writeBatch(Map<String, String> batch) async {
    writes += 1;
    values.addAll(batch);
  }
}

const _wechat = Account(
  id: 'wechat',
  name: '微信',
  type: AccountType.asset,
  isDefaultPayment: true,
);
const _lunch = Category(id: 'lunch', name: '午餐');
const _transport = Category(id: 'transport', name: '交通');

FinanceTransaction _row({
  String id = 'tx-legacy',
  String date = '2026年11月4日',
  String note = '中午',
  String? categoryId = 'lunch',
  String? accountId = 'wechat',
}) =>
    FinanceTransaction(
      id: id,
      date: date,
      type: TransactionType.expense,
      amount: 19.8,
      currency: 'CNY',
      cnyAmount: 19.8,
      exchangeRate: 1,
      categoryId: categoryId,
      accountId: accountId,
      note: note,
      clientOpId: id,
    );

FinanceState _state(List<FinanceTransaction> rows) => FinanceState(
      currentMonth: '2026-11',
      accounts: const [_wechat],
      categories: const [_lunch, _transport],
      transactions: rows,
    );

Widget _app(Widget child) =>
    MaterialApp(theme: wealthMateTheme(), home: Scaffold(body: child));

Future<LedgerStore> _ledger(_Atomic memory, FinanceState state) async {
  final session = LocalStateSession(
    local: LocalRepository(memory),
    queue: SyncQueue(),
  );
  return LedgerStore(
    repository: LedgerRepository(session: session),
    initialState: state,
  );
}

void main() {
  test('loose date parser covers legacy human formats', () {
    for (final text in [
      '2026-11-04',
      '2026-11-4',
      '2026/11/04',
      '2026/11/4',
      '2026.11.04',
      '2026.11.4',
      '2026年11月4日',
      '2026年11月04日',
      '2026-11-04T00:00:00',
      '20261104',
    ]) {
      expect(parseLooseDate(text), DateTime(2026, 11, 4), reason: text);
      expect(normalizeDateText(text), '2026-11-04', reason: text);
    }
    expect(parseLooseDate('2026-02-30'), isNull);
    expect(parseLooseDate('not a date'), isNull);
    expect(parseLooseDate(''), isNull);
  });

  test('loading repairs legacy dates once and persists the ISO form',
      () async {
    final memory = _Atomic();
    await LocalRepository(memory).save(_state([_row()]));
    expect(memory.values[LocalRepository.storageKey], contains('2026年11月4日'));

    final first = await LocalRepository(memory).load();
    expect(first, isNotNull);
    expect(first!.transactions.single.date, '2026-11-04');
    expect(memory.values[LocalRepository.storageKey], contains('2026-11-04'));
    expect(memory.values[LocalRepository.storageKey], isNot(contains('2026年11月4日')));
    final writesAfterFirst = memory.writes;

    final second = await LocalRepository(memory).load();
    expect(second!.transactions.single.date, '2026-11-04');
    expect(memory.writes, writesAfterFirst, reason: 'repair is idempotent');
  });

  testWidgets('a legacy-dated row is visible in the ledger after a cold load',
      (tester) async {
    final memory = _Atomic();
    await LocalRepository(memory).save(_state([_row()]));

    final loaded = (await LocalRepository(memory).load())!;
    final ledger = await _ledger(memory, loaded);
    await tester.pumpWidget(_app(LedgerPage(ledger: ledger)));
    await tester.pumpAndSettle();

    expect(find.text('中午'), findsOneWidget);
    expect(find.text('没有符合条件的账目'), findsNothing);
  });

  testWidgets('the three legacy-dated rows all become visible after a cold load',
      (tester) async {
    final memory = _Atomic();
    await LocalRepository(memory).save(_state([
      _row(id: 'tx-1', note: '中午'),
      _row(id: 'tx-2', note: '早餐'),
      _row(id: 'tx-3', note: '晚餐'),
    ]));

    final loaded = (await LocalRepository(memory).load())!;
    expect(loaded.transactions.map((row) => row.date),
        everyElement('2026-11-04'));

    final ledger = await _ledger(memory, loaded);
    await tester.pumpWidget(_app(LedgerPage(ledger: ledger)));
    await tester.pumpAndSettle();

    expect(find.text('中午'), findsOneWidget);
    expect(find.text('早餐'), findsOneWidget);
    expect(find.text('晚餐'), findsOneWidget);
    expect(find.text('没有符合条件的账目'), findsNothing);
  });

  testWidgets('the query itself tolerates a legacy date before repair',
      (tester) async {
    final state = _state([_row()]);
    expect(state.transactions.single.date, '2026年11月4日');
    expect(businessDate(state.transactions.single), DateTime(2026, 11, 4));
    expect(TransactionQuery().select(state), hasLength(1));

    final memory = _Atomic();
    final ledger = await _ledger(memory, state);
    await tester.pumpWidget(_app(LedgerPage(ledger: ledger)));
    await tester.pumpAndSettle();
    expect(find.text('中午'), findsOneWidget);
  });

  testWidgets('the detail page still shows the original human date',
      (tester) async {
    final memory = _Atomic();
    final ledger = await _ledger(memory, _state([_row()]));
    await tester.pumpWidget(_app(TransactionDetailPage(
      ledger: ledger,
      transaction: ledger.state.transactions.single,
    )));
    await tester.pumpAndSettle();
    expect(find.text('2026年11月4日（时间未记录）'), findsOneWidget);
    expect(find.text('微信'), findsOneWidget);
  });

  testWidgets('the detail page keeps the same human date after the repair',
      (tester) async {
    final memory = _Atomic();
    await LocalRepository(memory).save(_state([_row()]));
    final loaded = (await LocalRepository(memory).load())!;
    expect(loaded.transactions.single.date, '2026-11-04');

    final ledger = await _ledger(memory, loaded);
    await tester.pumpWidget(_app(TransactionDetailPage(
      ledger: ledger,
      transaction: ledger.state.transactions.single,
    )));
    await tester.pumpAndSettle();
    expect(find.text('2026年11月4日（时间未记录）'), findsOneWidget);
  });

  testWidgets('the 全部 chip clears inherited drilldown filters',
      (tester) async {
    final memory = _Atomic();
    final state = _state([_row()]);
    final ledger = await _ledger(memory, state);

    await tester.pumpWidget(_app(LedgerPage(
      ledger: ledger,
      initialQuery: TransactionQuery(
        start: DateTime(2026, 11, 5),
        end: DateTime(2026, 11, 5),
        type: TransactionType.expense,
        categoryIds: const {'transport'},
        accountId: 'wechat',
      ),
    )));
    await tester.pumpAndSettle();
    expect(find.text('没有符合条件的账目'), findsOneWidget);
    expect(find.text('2026-11-05 至 2026-11-05 · 0 笔'), findsOneWidget);

    await tester.tap(find.text('全部'));
    await tester.pumpAndSettle();
    expect(find.text('中午'), findsOneWidget);
    expect(find.text('没有符合条件的账目'), findsNothing);
    expect(find.textContaining('2026-11-05 至'), findsNothing);
  });

  testWidgets('an unknown inherited category id does not crash the dropdown',
      (tester) async {
    final memory = _Atomic();
    final ledger = await _ledger(memory, _state([_row()]));

    await tester.pumpWidget(_app(LedgerPage(
      ledger: ledger,
      initialQuery: const TransactionQuery(categoryIds: {'other'}),
    )));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('没有符合条件的账目'), findsOneWidget);

    await tester.tap(find.text('全部'));
    await tester.pumpAndSettle();
    expect(find.text('中午'), findsOneWidget);
  });
}
