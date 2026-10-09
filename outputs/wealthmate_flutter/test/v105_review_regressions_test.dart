import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wealthmate_flutter/core/database/local_state_session.dart';
import 'package:wealthmate_flutter/core/sync/sync_coordinator.dart';
import 'package:wealthmate_flutter/data/api_client.dart';
import 'package:wealthmate_flutter/data/finance_repository.dart';
import 'package:wealthmate_flutter/data/local_repository.dart';
import 'package:wealthmate_flutter/data/sync_queue.dart';
import 'package:wealthmate_flutter/domain/models.dart';
import 'package:wealthmate_flutter/features/budget/data/budget_repository.dart';
import 'package:wealthmate_flutter/state/finance_store.dart';
import 'package:wealthmate_flutter/ui/stats_page.dart';
import 'v105_assets_closure_test.dart' show Memory;

const total = Budget(
    id: 'server-total',
    month: '2026-10',
    categoryId: '__total__',
    limit: 100,
    serverVersion: 1);
const alias = Budget(
    id: 'offline-total', month: '2026-10', categoryId: '__total__', limit: 200);

class CollisionApi extends ApiClient {
  CollisionApi() : super(baseUrl: 'http://review.test');
  @override
  Future<Map<String, Object?>> push(List<SyncOperation> operations) async => {
        'accepted': [],
        'server_version': 9,
        'conflicts': [
          {
            'client_op_id': operations.single.clientOpId,
            'entity_id': alias.id,
            'canonical_entity_id': total.id
          }
        ]
      };
  @override
  Future<PullResult> pullChanges(int sinceVersion) async {
    expect(sinceVersion, 0); // canonical row can precede the client's cursor
    return const PullResult(
        transactions: [],
        accounts: [],
        categories: [],
        budgets: [total],
        serverVersion: 9);
  }
}

void main() {
  test(
      'legacy offline budget alias recovers original identity and clears persisted queue',
      () async {
    final session =
        LocalStateSession(local: LocalRepository(Memory()), queue: SyncQueue());
    final state = await BudgetRepository(session: session).saveBudget(alias,
        baseState: const FinanceState(syncState: SyncState(serverVersion: 9)));
    final coordinator = SyncCoordinator(
        session: session, api: CollisionApi(), isLocalOwnerBound: () => true);
    final next = await coordinator.sync(state);
    expect(next.budgets.map((b) => b.id), [total.id]);
    expect(next.budgets.single.limit, 100);
    expect(next.conflicts, isEmpty);
    expect(next.syncState.error, isNull);
    expect(await session.pendingOperations(), isEmpty);
    expect((await session.load())!.budgets.single.id, total.id);
  });

  test(
      'editing budget into an existing month/category leaves state and queue unchanged',
      () async {
    final session =
        LocalStateSession(local: LocalRepository(Memory()), queue: SyncQueue());
    final repository = BudgetRepository(session: session);
    final before = await repository.saveBudget(total);
    await expectLater(
        repository.saveBudget(Budget(
            id: 'another',
            month: total.month,
            categoryId: total.categoryId,
            limit: 200)),
        throwsStateError);
    expect((await session.load())!.budgets.single.id, before.budgets.single.id);
    expect((await session.pendingOperations()).length, 1);
  });

  testWidgets(
      'day/week pending warning and highest category follow their own scope and dimension',
      (tester) async {
    final store = FinanceStore(
        repository: FinanceRepository(
            local: LocalRepository(Memory()), queue: SyncQueue()),
        initialState: const FinanceState(currentMonth: '2026-09', categories: [
          Category(id: 'food', name: '餐饮')
        ], accounts: [
          Account(
              id: 'cash',
              name: '现金',
              type: AccountType.asset,
              openingBalance: 100)
        ], transactions: [
          FinanceTransaction(
              id: 'known',
              date: '2026-10-09',
              type: TransactionType.expense,
              amount: 16,
              categoryId: 'food',
              accountId: 'cash'),
          FinanceTransaction(
              id: 'pending',
              date: '2026-10-09',
              type: TransactionType.expense,
              amount: 2,
              currency: 'HKD'),
          FinanceTransaction(
              id: 'transfer',
              date: '2026-10-09',
              type: TransactionType.transfer,
              amount: 2,
              currency: 'HKD'),
        ]));
    addTearDown(store.dispose);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: StatsPage(
                insights: store.insights,
                ledger: store.ledger,
                now: DateTime(2026, 10, 9)))));
    expect(find.textContaining('缺少可靠汇率'), findsNothing);
    await tester.tap(find.text('本日'));
    await tester.pumpAndSettle();
    expect(find.textContaining('缺少可靠汇率'), findsOneWidget);
    expect(find.textContaining('有 1 笔外币账目'), findsOneWidget);
    await tester.tap(find.text('按账户'));
    await tester.pumpAndSettle();
    final card =
        find.ancestor(of: find.text('最高分类'), matching: find.byType(Card));
    expect(
        find.descendant(of: card, matching: find.text('餐饮')), findsOneWidget);
    await tester.tap(find.text('本周'));
    await tester.pumpAndSettle();
    expect(find.textContaining('缺少可靠汇率'), findsOneWidget);
  });
}
