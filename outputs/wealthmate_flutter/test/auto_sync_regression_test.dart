import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wealthmate_flutter/data/local_repository.dart';
import 'package:wealthmate_flutter/domain/models.dart';
import 'package:wealthmate_flutter/state/finance_store.dart';
import 'package:wealthmate_flutter/ui/app_shell.dart';

import 'core/two_device_sync_test.dart'
    show
        MemorySyncServer,
        SyncMemory,
        installLocalMutationCallback,
        syncDevice,
        syncSeed,
        syncTransaction;

typedef _Mutation = Future<void> Function(FinanceStore store);

class _BlockingQueueMemory extends SyncMemory {
  Completer<void>? _entered;
  Completer<void>? _release;

  void blockNextQueueWrite() {
    _entered = Completer<void>();
    _release = Completer<void>();
  }

  Future<void> get queueWriteEntered => _entered!.future;

  void releaseQueueWrite() => _release!.complete();

  @override
  Future<void> write(String key, String value) async {
    if (_entered != null &&
        !_entered!.isCompleted &&
        key.startsWith(LocalRepository.queueStorageKey)) {
      _entered!.complete();
      await _release!.future;
    }
    await super.write(key, value);
  }
}

FinanceState _transactionSeed(String id) => syncSeed.copyWith(transactions: [
      syncTransaction(id).copyWith(serverVersion: 3),
    ]);

AgentDraft _confirmedDraft() => const AgentDraft(
      amount: 18,
      type: TransactionType.expense,
      categoryId: 'category',
      accountId: 'account',
      date: '2026-09-16',
      note: 'quick confirmation',
      confidence: 1,
    );

Future<void> _pumpAuthenticatedShell(
    WidgetTester tester, FinanceStore store) async {
  await tester.pumpWidget(MaterialApp(home: AppShell(store: store)));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  final cases = <({
    String name,
    FinanceState initial,
    String entity,
    _Mutation mutate,
    bool queueMayDrain,
  })>[
    (
      name: 'transaction add',
      initial: syncSeed,
      entity: 'transactions',
      mutate: (store) => store.addTransaction(syncTransaction('auto-add')),
      queueMayDrain: false,
    ),
    (
      name: 'transaction update',
      initial: _transactionSeed('auto-update'),
      entity: 'transactions',
      mutate: (store) => store.updateTransaction(
          store.state.transactions.single.copyWith(note: 'updated')),
      queueMayDrain: false,
    ),
    (
      name: 'transaction delete',
      initial: _transactionSeed('auto-delete'),
      entity: 'transactions',
      mutate: (store) => store.deleteTransaction('auto-delete'),
      queueMayDrain: false,
    ),
    (
      name: 'account add',
      initial: syncSeed,
      entity: 'accounts',
      mutate: (store) =>
          store.addAccount(name: 'Auto account', type: AccountType.asset),
      queueMayDrain: false,
    ),
    (
      name: 'account update',
      initial: syncSeed,
      entity: 'accounts',
      mutate: (store) => store.updateAccount(
          store.state.accounts.single.copyWith(name: 'Updated account')),
      queueMayDrain: false,
    ),
    (
      name: 'category add',
      initial: syncSeed,
      entity: 'categories',
      mutate: (store) => store.addCategory(
          name: 'Auto category', type: TransactionType.expense),
      queueMayDrain: false,
    ),
    (
      name: 'category update',
      initial: syncSeed,
      entity: 'categories',
      mutate: (store) => store.updateCategory('category',
          name: 'Updated category', active: true),
      queueMayDrain: false,
    ),
    (
      name: 'category archive',
      initial: syncSeed,
      entity: 'categories',
      mutate: (store) => store.archiveCategory('category'),
      queueMayDrain: false,
    ),
    (
      name: 'budget upsert',
      initial: syncSeed,
      entity: 'budgets',
      mutate: (store) => store.upsertBudget(
          id: 'auto-budget',
          month: '2026-09',
          categoryId: 'category',
          limit: 500),
      queueMayDrain: false,
    ),
    (
      name: 'QuickEntry confirmation',
      initial: syncSeed,
      entity: 'transactions',
      mutate: (store) async {
        expect(await store.confirmDraft(_confirmedDraft()), isTrue);
      },
      queueMayDrain: true,
    ),
  ];

  for (final testCase in cases) {
    test('${testCase.name} publishes one post-persistence mutation callback',
        () async {
      final server = MemorySyncServer();
      final memory = SyncMemory();
      final store =
          await syncDevice(server, memory: memory, initial: testCase.initial);
      var callbackCount = 0;
      installLocalMutationCallback(store, () => callbackCount++);

      await testCase.mutate(store);

      final persisted = await store.repository.local.load();
      expect(persisted, isNotNull);
      final persistedQueue = await store.repository.local.loadQueue();
      if (testCase.queueMayDrain) {
        expect(
            server.pushedOperationBatches
                .expand((batch) => batch)
                .map((operation) => operation['entity']),
            contains(testCase.entity));
      } else {
        expect(persistedQueue.map((operation) => operation.entity),
            contains(testCase.entity));
      }
      expect(callbackCount, 1,
          reason: '${testCase.name} must request automatic sync exactly once.');
    });
  }

  test('callback is silent until aggregate and SyncQueue persistence completes',
      () async {
    final server = MemorySyncServer();
    final memory = _BlockingQueueMemory();
    final store = await syncDevice(server, memory: memory);
    var callbackCount = 0;
    installLocalMutationCallback(store, () => callbackCount++);
    memory.blockNextQueueWrite();

    final mutation =
        store.addTransaction(syncTransaction('persistence-boundary'));
    await memory.queueWriteEntered;
    expect(callbackCount, 0,
        reason: 'The callback must not race ahead of durable queue storage.');
    memory.releaseQueueWrite();
    await mutation;

    expect(callbackCount, 1);
    expect((await store.repository.local.loadQueue()).single.entityId,
        'persistence-boundary');
  });

  testWidgets('rapid local mutations debounce into one automatic sync request',
      (tester) async {
    final server = MemorySyncServer();
    final store = await syncDevice(server);
    await _pumpAuthenticatedShell(tester, store);
    final pushesBeforeMutations = server.pushCalls;

    await store.addTransaction(syncTransaction('coalesced-1'));
    await store.addTransaction(syncTransaction('coalesced-2'));
    await store.addTransaction(syncTransaction('coalesced-3'));
    await tester.pump(const Duration(milliseconds: 249));
    expect(server.pushCalls, pushesBeforeMutations,
        reason: 'Debounced mutations must not start early.');

    await tester.pump(const Duration(milliseconds: 1));
    await tester.pump(const Duration(milliseconds: 100));
    expect(server.pushCalls, pushesBeforeMutations + 1,
        reason: 'All rapid mutations must coalesce into one drain request.');
    final sentIds = server.pushedOperationBatches.last
        .map((operation) => operation['entity_id'])
        .toSet();
    expect(sentIds, {'coalesced-1', 'coalesced-2', 'coalesced-3'});
  });
}
