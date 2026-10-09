import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:wealthmate_flutter/core/database/local_state_session.dart';
import 'package:wealthmate_flutter/core/sync/sync_coordinator.dart';
import 'package:wealthmate_flutter/data/local_repository.dart';
import 'package:wealthmate_flutter/data/api_client.dart';
import 'package:wealthmate_flutter/data/sync_queue.dart';
import 'package:wealthmate_flutter/domain/models.dart';
import 'package:wealthmate_flutter/features/budget/data/budget_repository.dart';
import 'v105_budget_concurrent_edit_test.dart' show ReviewServer, DelayedStore;

class ReceiptServer extends ReviewServer {
  final pushStarted = Completer<void>();
  final pushRelease = Completer<void>();
  bool firstPush = true;
  @override
  Future<Map<String, Object?>> push(List<SyncOperation> operations) async {
    if (firstPush) {
      firstPush = false;
      pushStarted.complete();
      await pushRelease.future;
    }
    return super.push(operations);
  }
}

class FreshBudgetServer extends ApiClient {
  FreshBudgetServer() : super(baseUrl: 'http://review.test');
  Budget? budget;
  bool offline = true;
  @override
  Future<Map<String, Object?>> push(List<SyncOperation> operations) async {
    if (offline) throw const ApiFailure(ApiFailureKind.network, '合成断网');
    final op = operations.single;
    budget = Budget.fromJson({...op.payload, 'server_version': 1});
    return {
      'accepted': [
        {
          'client_op_id': op.clientOpId,
          'entity_id': op.entityId,
          'server_version': 1
        }
      ],
      'conflicts': [],
      'server_version': 1
    };
  }

  @override
  Future<PullResult> pullChanges(int sinceVersion) async => PullResult(
      transactions: [],
      accounts: [],
      categories: [],
      budgets: budget == null ? [] : [budget!],
      serverVersion: budget == null ? 0 : 1);
}

void main() {
  for (final reopen in [false, true]) {
    test('failed receipt persistence retries latest budget with reopen=$reopen',
        () async {
      final store = DelayedStore();
      final session =
          LocalStateSession(local: LocalRepository(store), queue: SyncQueue());
      final repository = BudgetRepository(session: session);
      final state = await repository.saveBudget(const Budget(
          id: 'alias', month: '2026-10', categoryId: '__total__', limit: 200));
      final api = ReceiptServer();
      api.gate.complete();
      final sync = SyncCoordinator(
          session: session, api: api, isLocalOwnerBound: () => true);
      final syncing = sync.sync(state);
      await api.pushStarted.future;
      await repository.saveBudget(const Budget(
          id: 'alias', month: '2026-10', categoryId: '__total__', limit: 300));
      store.fail = true;
      final failure = expectLater(syncing, throwsStateError);
      api.pushRelease.complete();
      await failure;
      expect((await session.load())!.budgets.single.limit, 300);
      final retrySession = reopen
          ? LocalStateSession(local: LocalRepository(store), queue: SyncQueue())
          : session;
      final retrySync = reopen
          ? SyncCoordinator(
              session: retrySession, api: api, isLocalOwnerBound: () => true)
          : sync;
      var retry = await retrySync.sync((await retrySession.load())!);
      if ((await retrySession.pendingOperations()).isNotEmpty)
        retry = await retrySync.sync(retry);
      expect(api.budget.limit, 300);
      expect(retry.budgets.single.limit, 300);
      expect(await retrySession.pendingOperations(), isEmpty);
    });
  }
  test('first upload network failure retains uncreated budget and retries it',
      () async {
    final session = LocalStateSession(
        local: LocalRepository(DelayedStore()), queue: SyncQueue());
    final initial = await BudgetRepository(session: session).saveBudget(
        const Budget(
            id: 'fresh',
            month: '2026-10',
            categoryId: '__total__',
            limit: 200));
    final api = FreshBudgetServer();
    final sync = SyncCoordinator(
        session: session, api: api, isLocalOwnerBound: () => true);
    final offline = await sync.sync(initial);
    expect(offline.budgets.single.limit, 200);
    expect(offline.syncState.error, isNotNull);
    expect(
        (await session.pendingOperations()).single.conflictClientOpId, isNull);
    expect(api.budget, isNull);
    api.offline = false;
    final online = await sync.sync(offline);
    expect(api.budget!.limit, 200);
    expect(online.budgets.single.limit, 200);
    expect(await session.pendingOperations(), isEmpty);
  });
}
