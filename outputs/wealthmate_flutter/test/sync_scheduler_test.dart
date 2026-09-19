import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'core/two_device_sync_test.dart'
    show MemorySyncServer, SyncBarrier, syncDevice, syncTransaction;

typedef SyncPipeline = Future<bool> Function();
typedef SyncEligibility = bool Function();

/// Compile-time contract for the production scheduler introduced by V1.0.4.
///
/// The RED tests below exercise the current real FinanceStore pipeline. This
/// declaration deliberately contains no test implementation that could make a
/// missing production scheduler look green.
abstract class SyncScheduler {
  SyncScheduler({
    required SyncPipeline runPipeline,
    required SyncEligibility canRun,
    Duration debounce = const Duration(milliseconds: 250),
  });

  Future<void> request({String reason = 'unknown', bool immediate = false});
  bool get isActive;
  void dispose();
}

Future<bool> _completesWithin(Future<void> future,
    [Duration limit = const Duration(milliseconds: 150)]) async {
  var completed = false;
  await Future.any<void>([
    future.then((_) => completed = true),
    Future<void>.delayed(limit),
  ]);
  return completed;
}

Map<String, Object?> _payload(
        List<Map<String, Object?>> batch, String entityId) =>
    (batch.singleWhere(
                (operation) => operation['entity_id'] == entityId)['payload']
            as Map)
        .cast<String, Object?>();

void main() {
  test('active sync callers receive one shared Future until the drain ends',
      () async {
    final server = MemorySyncServer();
    final store = await syncDevice(server);
    await store.addTransaction(syncTransaction('shared-future'));
    final barrier = SyncBarrier();
    server.pushBarrier = barrier;

    final first = store.sync();
    await barrier.entered.future;
    final second = store.sync();
    var firstCompleted = false;
    var secondCompleted = false;
    first.whenComplete(() => firstCompleted = true);
    second.whenComplete(() => secondCompleted = true);

    try {
      await Future<void>.delayed(Duration.zero);
      expect(identical(first, second), isTrue,
          reason: 'An early-return Future strands callers outside the drain.');
      expect(firstCompleted, isFalse);
      expect(secondCompleted, isFalse);
    } finally {
      barrier.release.complete();
      await first;
      await second;
    }
  });

  test('successful dirty rounds keep draining latest snapshots without overlap',
      () async {
    final server = MemorySyncServer();
    final store = await syncDevice(server);
    await store.addTransaction(syncTransaction('continuous-drain'));
    final firstPush = SyncBarrier();
    final secondPush = SyncBarrier();
    final thirdPush = SyncBarrier();
    server.pushBarriers.addAll([firstPush, secondPush, thirdPush]);

    final draining = store.sync();
    var drainCompleted = false;
    draining.whenComplete(() => drainCompleted = true);
    await firstPush.entered.future;
    await store.updateTransaction(store.state.transactions.single
        .copyWith(note: 'superseded during round one'));
    await store.updateTransaction(store.state.transactions.single
        .copyWith(note: 'latest during round one'));
    firstPush.release.complete();

    try {
      expect(await _completesWithin(secondPush.entered.future), isTrue,
          reason: 'A successful dirty first round must start round two.');
      await store.updateTransaction(store.state.transactions.single
          .copyWith(note: 'written during round two'));
      secondPush.release.complete();
      expect(await _completesWithin(thirdPush.entered.future), isTrue,
          reason: 'The drain must not stop after one follow-up round.');

      expect(server.pushCalls, 3);
      expect(
          _payload(
              server.pushedOperationBatches[1], 'continuous-drain')['note'],
          'latest during round one');
      expect(
          _payload(
              server.pushedOperationBatches[2], 'continuous-drain')['note'],
          'written during round two');
      expect(drainCompleted, isFalse,
          reason: 'The shared Future must remain pending through the drain.');
      expect(server.maxActiveSyncRequests, 1,
          reason: 'Push/pull pipelines must remain strictly serialized.');
    } finally {
      if (!secondPush.release.isCompleted) secondPush.release.complete();
      if (!thirdPush.release.isCompleted) thirdPush.release.complete();
      await draining;
    }
  });

  test('a failed round stops with durable state until an explicit retry',
      () async {
    final server = MemorySyncServer();
    final store = await syncDevice(server);
    await store.sync();
    final priorSuccess = store.state.syncState.lastSyncedAt;
    await store.addTransaction(syncTransaction('failure-stop'));
    server.failPush = true;

    final first = store.sync();
    final second = store.sync();
    var firstCompleted = false;
    var secondCompleted = false;
    first.whenComplete(() => firstCompleted = true);
    second.whenComplete(() => secondCompleted = true);
    await first;
    await second;

    expect(identical(first, second), isTrue,
        reason: 'Failed active callers still share the same drain Future.');
    expect(firstCompleted, isTrue);
    expect(secondCompleted, isTrue);
    expect(store.repository.queue.pending(), hasLength(1));
    expect(store.state.syncState.serverVersion, 2);
    expect(store.state.syncState.lastSyncedAt, priorSuccess);
    expect(store.state.syncState.error, isNotNull);
    await Future<void>.delayed(const Duration(milliseconds: 350));
    expect(server.pushCalls, 1,
        reason: 'A failed drain must not schedule an internal retry.');

    await store.sync();
    expect(server.pushCalls, 2);
    expect(store.repository.queue.pending(), isEmpty);
  });
}
