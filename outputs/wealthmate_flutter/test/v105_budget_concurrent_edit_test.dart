import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:wealthmate_flutter/core/database/local_state_session.dart';
import 'package:wealthmate_flutter/core/sync/sync_coordinator.dart';
import 'package:wealthmate_flutter/data/api_client.dart';
import 'package:wealthmate_flutter/data/local_repository.dart';
import 'package:wealthmate_flutter/data/sync_queue.dart';
import 'package:wealthmate_flutter/domain/models.dart';
import 'package:wealthmate_flutter/features/budget/data/budget_repository.dart';
import 'v105_assets_closure_test.dart' show Memory;

class ReviewServer extends ApiClient {
  ReviewServer() : super(baseUrl: 'http://review.test');
  final started = Completer<void>();
  final gate = Completer<void>();
  var pulls = 0;
  Budget budget = const Budget(
      id: 'canonical',
      month: '2026-10',
      categoryId: '__total__',
      limit: 100,
      serverVersion: 1);
  @override
  Future<Map<String, Object?>> push(List<SyncOperation> operations) async {
    final op = operations.single;
    if (op.entityId != budget.id) {
      return {
        'accepted': [],
        'server_version': 1,
        'conflicts': [
          {
            'client_op_id': op.clientOpId,
            'entity_id': op.entityId,
            'canonical_entity_id': budget.id
          }
        ]
      };
    }
    budget = Budget.fromJson({...op.payload, 'server_version': 2});
    return {
      'accepted': [
        {
          'client_op_id': op.clientOpId,
          'entity_id': op.entityId,
          'server_version': 2
        }
      ],
      'server_version': 2,
      'conflicts': []
    };
  }

  @override
  Future<PullResult> pullChanges(int sinceVersion) async {
    if (pulls++ == 0) {
      started.complete();
      await gate.future;
    }
    return PullResult(
        transactions: [],
        accounts: [],
        categories: [],
        budgets: [budget],
        serverVersion: budget.serverVersion!);
  }
}

class DelayedStore extends Memory implements AtomicKeyValueStore {
  bool block = false;
  bool fail = false;
  final writing = Completer<void>();
  final release = Completer<void>();
  @override
  Future<void> writeBatch(Map<String, String> values) async {
    if (fail) {
      fail = false;
      throw StateError('synthetic atomic write failure');
    }
    if (block) {
      block = false;
      writing.complete();
      await release.future;
    }
    for (final entry in values.entries) {
      await write(entry.key, entry.value);
    }
  }
}

void main() {
  for (final reopen in [false, true]) {
    test('failed conflict remap retries latest edit with reopen=$reopen',
        () async {
      final store = DelayedStore();
      final session =
          LocalStateSession(local: LocalRepository(store), queue: SyncQueue());
      final repository = BudgetRepository(session: session);
      final state = await repository.saveBudget(const Budget(
          id: 'alias', month: '2026-10', categoryId: '__total__', limit: 200));
      final api = ReviewServer();
      final sync = SyncCoordinator(
          session: session, api: api, isLocalOwnerBound: () => true);
      final recovering = sync.sync(state);
      await api.started.future;
      await repository.saveBudget(const Budget(
          id: 'alias', month: '2026-10', categoryId: '__total__', limit: 300));
      store.fail = true;
      final expectation = expectLater(recovering, throwsStateError);
      api.gate.complete();
      await expectation;
      expect((await session.pendingOperations()).single.entityId, 'alias');
      expect((await session.local.loadQueue()).single.entityId, 'alias');
      expect((await session.load())!.budgets.single.limit, 300);
      final retrySession = reopen
          ? LocalStateSession(local: LocalRepository(store), queue: SyncQueue())
          : session;
      final retrySync = reopen
          ? SyncCoordinator(
              session: retrySession, api: api, isLocalOwnerBound: () => true)
          : sync;
      var retry = await retrySync.sync((await retrySession.load())!);
      if ((await retrySession.pendingOperations()).isNotEmpty) {
        retry = await retrySync.sync(retry);
      }
      expect(api.budget.limit, 300);
      expect(retry.budgets.single.limit, 300);
      expect(await retrySession.pendingOperations(), isEmpty);
    });
  }
  test('edit committing while recovery queues behind it must also survive',
      () async {
    final store = DelayedStore();
    final session =
        LocalStateSession(local: LocalRepository(store), queue: SyncQueue());
    final repository = BudgetRepository(session: session);
    var state = await repository.saveBudget(const Budget(
        id: 'alias', month: '2026-10', categoryId: '__total__', limit: 200));
    final api = ReviewServer();
    final sync = SyncCoordinator(
        session: session, api: api, isLocalOwnerBound: () => true);
    final recovering = sync.sync(state);
    await api.started.future;
    store.block = true;
    final editing = repository.saveBudget(const Budget(
        id: 'alias', month: '2026-10', categoryId: '__total__', limit: 300));
    await store.writing.future;
    api.gate.complete();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    store.release.complete();
    await editing;
    state = await recovering;
    state = await sync.sync(state);
    expect(api.budget.limit, 300);
  });
  test(
      'newer local alias edit must reach canonical server budget after recovery',
      () async {
    final session =
        LocalStateSession(local: LocalRepository(Memory()), queue: SyncQueue());
    final repository = BudgetRepository(session: session);
    var state = await repository.saveBudget(const Budget(
        id: 'alias', month: '2026-10', categoryId: '__total__', limit: 200));
    final api = ReviewServer();
    final sync = SyncCoordinator(
        session: session, api: api, isLocalOwnerBound: () => true);
    final recovering = sync.sync(state);
    await api.started.future;
    await repository.saveBudget(const Budget(
        id: 'alias', month: '2026-10', categoryId: '__total__', limit: 300));
    api.gate.complete();
    state = await recovering;
    state = await sync.sync(state);
    expect(api.budget.limit, 300);
  });
}
