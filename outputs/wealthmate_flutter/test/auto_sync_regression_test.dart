import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wealthmate_flutter/data/local_repository.dart';
import 'package:wealthmate_flutter/data/sync_queue.dart';
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

class _BlockingPersistenceMemory extends SyncMemory {
  Completer<void>? _queueEntered;
  Completer<void>? _queueRelease;
  Completer<void>? _stateEntered;
  Completer<void>? _stateRelease;

  void blockNextQueueWrite() {
    _queueEntered = Completer<void>();
    _queueRelease = Completer<void>();
  }

  Future<void> get queueWriteEntered => _queueEntered!.future;

  void releaseQueueWrite() => _queueRelease!.complete();

  void blockNextStateWrite() {
    _stateEntered = Completer<void>();
    _stateRelease = Completer<void>();
  }

  Future<void> get stateWriteEntered => _stateEntered!.future;

  void releaseStateWrite() => _stateRelease!.complete();

  @override
  Future<void> write(String key, String value) async {
    if (_stateEntered != null &&
        !_stateEntered!.isCompleted &&
        key.startsWith(LocalRepository.storageKey)) {
      _stateEntered!.complete();
      await _stateRelease!.future;
    }
    if (_queueEntered != null &&
        !_queueEntered!.isCompleted &&
        key.startsWith(LocalRepository.queueStorageKey)) {
      _queueEntered!.complete();
      await _queueRelease!.future;
    }
    await super.write(key, value);
  }
}

class _FailingPersistenceMemory extends SyncMemory {
  bool failStateWrite = false;
  bool failQueueWrite = false;

  @override
  Future<void> write(String key, String value) async {
    if (failStateWrite && key.startsWith(LocalRepository.storageKey)) {
      failStateWrite = false;
      throw StateError('injected aggregate persistence failure');
    }
    if (failQueueWrite && key.startsWith(LocalRepository.queueStorageKey)) {
      failQueueWrite = false;
      throw StateError('injected queue persistence failure');
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
    void Function(FinanceState state) assertDurableState,
  })>[
    (
      name: 'transaction add',
      initial: syncSeed,
      entity: 'transactions',
      mutate: (store) => store.addTransaction(syncTransaction('auto-add')),
      assertDurableState: (state) => expect(
          state.transactions.any((transaction) => transaction.id == 'auto-add'),
          isTrue),
    ),
    (
      name: 'transaction update',
      initial: _transactionSeed('auto-update'),
      entity: 'transactions',
      mutate: (store) => store.updateTransaction(
          store.state.transactions.single.copyWith(note: 'updated')),
      assertDurableState: (state) => expect(
          state.transactions.any((transaction) =>
              transaction.id == 'auto-update' && transaction.note == 'updated'),
          isTrue),
    ),
    (
      name: 'transaction delete',
      initial: _transactionSeed('auto-delete'),
      entity: 'transactions',
      mutate: (store) => store.deleteTransaction('auto-delete'),
      assertDurableState: (state) => expect(
          state.transactions
              .any((transaction) => transaction.id == 'auto-delete'),
          isFalse),
    ),
    (
      name: 'account add',
      initial: syncSeed,
      entity: 'accounts',
      mutate: (store) =>
          store.addAccount(name: 'Auto account', type: AccountType.asset),
      assertDurableState: (state) => expect(
          state.accounts.any((account) => account.name == 'Auto account'),
          isTrue),
    ),
    (
      name: 'account update',
      initial: syncSeed,
      entity: 'accounts',
      mutate: (store) => store.updateAccount(
          store.state.accounts.single.copyWith(name: 'Updated account')),
      assertDurableState: (state) => expect(
          state.accounts.any((account) => account.name == 'Updated account'),
          isTrue),
    ),
    (
      name: 'category add',
      initial: syncSeed,
      entity: 'categories',
      mutate: (store) => store.addCategory(
          name: 'Auto category', type: TransactionType.expense),
      assertDurableState: (state) => expect(
          state.categories.any((category) => category.name == 'Auto category'),
          isTrue),
    ),
    (
      name: 'category update',
      initial: syncSeed,
      entity: 'categories',
      mutate: (store) => store.updateCategory('category',
          name: 'Updated category', active: true),
      assertDurableState: (state) => expect(
          state.categories.any((category) =>
              category.id == 'category' && category.name == 'Updated category'),
          isTrue),
    ),
    (
      name: 'category archive',
      initial: syncSeed,
      entity: 'categories',
      mutate: (store) => store.archiveCategory('category'),
      assertDurableState: (state) => expect(
          state.categories
              .any((category) => category.id == 'category' && !category.active),
          isTrue),
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
      assertDurableState: (state) => expect(
          state.budgets.any((budget) => budget.id == 'auto-budget'), isTrue),
    ),
    (
      name: 'QuickEntry confirmation',
      initial: syncSeed,
      entity: 'transactions',
      mutate: (store) async {
        expect(await store.confirmDraft(_confirmedDraft()), isTrue);
      },
      assertDurableState: (state) => expect(
          state.transactions
              .any((transaction) => transaction.note == 'quick confirmation'),
          isTrue),
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
      Future<FinanceState?>? stateAtCallback;
      Future<List<SyncOperation>>? queueAtCallback;
      installLocalMutationCallback(store, (_) {
        callbackCount++;
        stateAtCallback = store.repository.local.load();
        queueAtCallback = store.repository.local.loadQueue();
      });

      await testCase.mutate(store);

      expect(stateAtCallback, isNotNull,
          reason:
              '${testCase.name} must capture durable state in its callback.');
      expect(queueAtCallback, isNotNull,
          reason:
              '${testCase.name} must capture durable queue in its callback.');
      final persistedAtCallback = await stateAtCallback!;
      final durableQueueAtCallback = await queueAtCallback!;
      expect(persistedAtCallback, isNotNull);
      testCase.assertDurableState(persistedAtCallback!);
      expect(durableQueueAtCallback.map((operation) => operation.entity),
          contains(testCase.entity),
          reason:
              '${testCase.name} callback must observe its durable queue entry.');
      expect(callbackCount, 1,
          reason: '${testCase.name} must request automatic sync exactly once.');
    });
  }

  test('callback waits for updated aggregate and queue persistence', () async {
    final server = MemorySyncServer();
    final memory = _BlockingPersistenceMemory();
    final store = await syncDevice(server, memory: memory);
    var callbackCount = 0;
    installLocalMutationCallback(store, (_) => callbackCount++);
    memory.blockNextQueueWrite();

    final mutation =
        store.addTransaction(syncTransaction('persistence-boundary'));
    await memory.queueWriteEntered;
    final persistedDuringQueueBlock = await store.repository.local.load();
    expect(persistedDuringQueueBlock!.transactions.single.note, 'original',
        reason: 'The aggregate must be persisted before the queue boundary.');
    expect(persistedDuringQueueBlock.transactions.single.id,
        'persistence-boundary');
    expect(callbackCount, 0,
        reason: 'The callback must not race ahead of durable queue storage.');
    memory.releaseQueueWrite();
    await mutation;

    expect(callbackCount, 1);
    expect((await store.repository.local.load())!.transactions.single.id,
        'persistence-boundary');
    expect((await store.repository.local.loadQueue()).single.entityId,
        'persistence-boundary');

    final stateMemory = _BlockingPersistenceMemory();
    final stateStore =
        await syncDevice(MemorySyncServer(), memory: stateMemory);
    var stateCallbackCount = 0;
    installLocalMutationCallback(stateStore, (_) => stateCallbackCount++);
    stateMemory.blockNextStateWrite();

    final stateMutation =
        stateStore.addTransaction(syncTransaction('state-boundary'));
    await stateMemory.stateWriteEntered;
    expect(stateCallbackCount, 0,
        reason:
            'The callback must not race ahead of durable aggregate storage.');
    stateMemory.releaseStateWrite();
    await stateMutation;
    expect(stateCallbackCount, 1);
  });

  test('failed aggregate or queue persistence never publishes a mutation',
      () async {
    final stateMemory = _FailingPersistenceMemory();
    final stateStore =
        await syncDevice(MemorySyncServer(), memory: stateMemory);
    var stateCallbackCount = 0;
    installLocalMutationCallback(stateStore, (_) => stateCallbackCount++);
    stateMemory.failStateWrite = true;

    await expectLater(
        stateStore.addTransaction(syncTransaction('state-failure')),
        throwsA(isA<StateError>()));
    expect(stateCallbackCount, 0);
    expect((await stateStore.repository.local.load())!.transactions, isEmpty);
    expect(await stateStore.repository.local.loadQueue(), isEmpty);

    final queueMemory = _FailingPersistenceMemory();
    final queueServer = MemorySyncServer();
    final queueStore = await syncDevice(queueServer, memory: queueMemory);
    var queueCallbackCount = 0;
    installLocalMutationCallback(queueStore, (_) => queueCallbackCount++);
    queueMemory.failQueueWrite = true;

    await expectLater(
        queueStore.addTransaction(syncTransaction('queue-failure')),
        throwsA(isA<StateError>()));
    expect(queueCallbackCount, 0);
    expect((await queueStore.repository.local.load())!.transactions.single.id,
        'queue-failure',
        reason: 'The state write may precede a failed queue write.');
    expect(await queueStore.repository.local.loadQueue(), isEmpty);
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
    await tester.pump(const Duration(milliseconds: 500));
    expect(server.pushCalls, pushesBeforeMutations + 1,
        reason: 'A second debounce interval must not create a duplicate push.');
  });
}
