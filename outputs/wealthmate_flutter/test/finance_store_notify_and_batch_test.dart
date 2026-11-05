import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wealthmate_flutter/core/database/local_state_session.dart';
import 'package:wealthmate_flutter/data/finance_repository.dart';
import 'package:wealthmate_flutter/data/local_repository.dart';
import 'package:wealthmate_flutter/data/sync_queue.dart';
import 'package:wealthmate_flutter/domain/models.dart';
import 'package:wealthmate_flutter/features/ledger/data/ledger_repository.dart';
import 'package:wealthmate_flutter/features/ledger/state/ledger_store.dart';
import 'package:wealthmate_flutter/features/quick_entry/data/quick_entry_repository.dart';
import 'package:wealthmate_flutter/features/quick_entry/domain/quick_entry_batch.dart';
import 'package:wealthmate_flutter/state/finance_store.dart';
import 'package:wealthmate_flutter/ui/ledger_page.dart';
import 'package:wealthmate_flutter/ui/theme.dart';

class _Atomic implements AtomicKeyValueStore {
  final Map<String, String> values = <String, String>{};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;

  @override
  Future<void> writeBatch(Map<String, String> batch) async {
    values.addAll(batch);
  }
}

const _alipay = Account(
  id: 'alipay',
  name: '支付宝',
  type: AccountType.asset,
  isDefaultPayment: true,
);
const _food = Category(id: 'food', name: '餐饮');

FinanceState _state({List<FinanceTransaction> rows = const []}) => FinanceState(
      currentMonth: '2026-11',
      defaultAccountId: 'alipay',
      accounts: const [_alipay],
      categories: const [_food],
      transactions: rows,
    );

Widget _app(Widget child) =>
    MaterialApp(theme: wealthMateTheme(), home: Scaffold(body: child));

FinanceStore _store(_Atomic memory, {FinanceState? state}) => FinanceStore(
      repository: FinanceRepository(
        local: LocalRepository(memory),
        queue: SyncQueue(),
      ),
      initialState: state ?? _state(),
    );

void main() {
  testWidgets('quick-entry confirm notifies ledger, assets and budget',
      (tester) async {
    final memory = _Atomic();
    final store = _store(memory);
    var ledgerNotified = 0;
    var assetsNotified = 0;
    var budgetNotified = 0;
    store.ledger.addListener(() => ledgerNotified += 1);
    store.assets.addListener(() => assetsNotified += 1);
    store.budget.addListener(() => budgetNotified += 1);

    final parsed = await store.quickEntry
        .createBatch('今天中午外卖 32 元，支付宝', now: DateTime(2026, 11, 5, 12));
    expect(parsed, isTrue);
    final confirmed = await store.quickEntry
        .confirmBatch(now: DateTime(2026, 11, 5, 12, 30));
    expect(confirmed, isTrue);
    expect(store.ledger.state.transactions, hasLength(1));

    expect(ledgerNotified, greaterThan(0));
    expect(assetsNotified, greaterThan(0));
    expect(budgetNotified, greaterThan(0));

    final note = store.ledger.state.transactions.single.note;
    final ledger = LedgerStore(
      repository: LedgerRepository(
        session: LocalStateSession(
          local: LocalRepository(memory),
          queue: SyncQueue(),
        ),
      ),
      initialState: store.ledger.state,
    );
    await tester.pumpWidget(_app(LedgerPage(ledger: ledger)));
    await tester.pumpAndSettle();
    expect(find.text(note), findsOneWidget);
  });

  test('loadAuthenticatedProfile notifies the ledger after adopting rows',
      () async {
    final memory = _Atomic();
    await LocalRepository(memory).forUser('u1').save(_state(rows: [
      FinanceTransaction(
        id: 'tx-profile',
        date: '2026-11-04',
        type: TransactionType.expense,
        amount: 19.8,
        categoryId: 'food',
        accountId: 'alipay',
        note: '中午',
      ),
    ]));

    final store = _store(memory, state: const FinanceState());
    var ledgerNotified = 0;
    store.ledger.addListener(() => ledgerNotified += 1);

    await store.loadAuthenticatedProfile(
      const UserProfile(id: 'u1', username: 'u1', displayName: '用户一'),
    );

    expect(store.ledger.state.transactions, hasLength(1));
    expect(ledgerNotified, greaterThan(0));
  });

  test('a manual ledger write still notifies and persists', () async {
    final memory = _Atomic();
    final store = _store(memory);
    var ledgerNotified = 0;
    store.ledger.addListener(() => ledgerNotified += 1);

    await store.ledger.addTransaction(FinanceTransaction(
      id: 'tx-manual',
      date: '2026-11-05',
      type: TransactionType.expense,
      amount: 12,
      categoryId: 'food',
      accountId: 'alipay',
      note: '手动一笔',
    ));

    expect(ledgerNotified, greaterThan(0));
    expect(store.ledger.state.transactions, hasLength(1));
    final reloaded = await LocalRepository(memory).load();
    expect(reloaded!.transactions.single.note, '手动一笔');
  });

  testWidgets('a three-card batch lands as three visible ledger rows',
      (tester) async {
    final memory = _Atomic();
    final session = LocalStateSession(
      local: LocalRepository(memory),
      queue: SyncQueue(),
    );
    final repository = QuickEntryRepository(session: session);
    final state = _state();

    final next = await repository.commitBatch(
      [
        for (final (index, note) in ['中午', '早餐', '晚餐'].indexed)
          QuickEntryCandidate(
            id: 'c$index',
            selected: true,
            draft: AgentDraft(
              amount: 10 + index.toDouble(),
              type: TransactionType.expense,
              categoryId: 'food',
              accountId: 'alipay',
              date: '2026-11-04',
              note: note,
              currency: 'CNY',
              confidence: .98,
            ),
          ),
      ],
      initialState: state,
      now: DateTime(2026, 11, 4, 12),
    );

    expect(next.transactions, hasLength(3));
    final ledger = LedgerStore(
      repository: LedgerRepository(session: session),
      initialState: next,
    );
    await tester.pumpWidget(_app(LedgerPage(ledger: ledger)));
    await tester.pumpAndSettle();
    expect(find.text('中午'), findsOneWidget);
    expect(find.text('早餐'), findsOneWidget);
    expect(find.text('晚餐'), findsOneWidget);
  });
}
