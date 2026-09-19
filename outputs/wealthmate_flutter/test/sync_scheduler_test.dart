import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'core/two_device_sync_test.dart'
    show MemorySyncServer, SyncBarrier, syncDevice, syncTransaction;

typedef SyncPipeline = Future<bool> Function();
typedef SyncEligibility = bool Function();
typedef SyncSchedulerBuilder = SyncScheduler Function({
  required SyncPipeline runPipeline,
  required SyncEligibility canRun,
  Duration debounce,
});

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

/// Compiler-only probe: the behavioral tests below deliberately use the real
/// FinanceStore pipeline, while this implementation keeps every member of the
/// scheduler contract type-checked instead of leaving the declaration unused.
class _SyncSchedulerContractProbe implements SyncScheduler {
  _SyncSchedulerContractProbe({
    required this.runPipeline,
    required this.canRun,
    this.debounce = const Duration(milliseconds: 250),
  });

  final SyncPipeline runPipeline;
  final SyncEligibility canRun;
  final Duration debounce;

  @override
  Future<void> request({String reason = 'unknown', bool immediate = false}) =>
      throw UnimplementedError('contract probe is never used as a scheduler');

  @override
  bool get isActive => false;

  @override
  void dispose() {}
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
  test('scheduler seam is compile-time checked without masking real behavior',
      () async {
    final SyncSchedulerBuilder builder = _SyncSchedulerContractProbe.new;
    final SyncScheduler scheduler = builder(
      runPipeline: () async => true,
      canRun: () => true,
    );

    expect(scheduler, isA<SyncScheduler>());
    final probe = scheduler as _SyncSchedulerContractProbe;
    expect(probe.canRun(), isTrue);
    expect(await probe.runPipeline(), isTrue);
    expect(probe.debounce, const Duration(milliseconds: 250));
    scheduler.dispose();
  });

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
    final callers = <Future<void>>[draining];
    var drainCompleted = false;
    draining.whenComplete(() => drainCompleted = true);

    try {
      await firstPush.entered.future;
      final secondCaller = store.sync();
      callers.add(secondCaller);
      expect(identical(draining, secondCaller), isTrue,
          reason: 'Every caller must join the active serialized drain.');
      await store.updateTransaction(store.state.transactions.single
          .copyWith(note: 'superseded during round one'));
      await store.updateTransaction(store.state.transactions.single
          .copyWith(note: 'latest during round one'));
      firstPush.release.complete();

      expect(await _completesWithin(secondPush.entered.future), isTrue,
          reason: 'A successful dirty first round must start round two.');
      final thirdCaller = store.sync();
      callers.add(thirdCaller);
      expect(identical(draining, thirdCaller), isTrue,
          reason: 'The shared Future must survive every dirty round.');
      await store.updateTransaction(store.state.transactions.single
          .copyWith(note: 'written during round two'));
      secondPush.release.complete();
      expect(await _completesWithin(thirdPush.entered.future), isTrue,
          reason: 'The drain must not stop after one follow-up round.');

      thirdPush.release.complete();
      expect(
          await _completesWithin(draining, const Duration(seconds: 1)), isTrue,
          reason: 'The shared Future must complete after the final pull.');
      await Future.wait(callers);

      expect(server.pushCalls, 3);
      expect(server.pullCalls, 3,
          reason: 'The third push must be followed by its final pull.');
      expect(
          _payload(
              server.pushedOperationBatches[1], 'continuous-drain')['note'],
          'latest during round one');
      expect(
          _payload(
              server.pushedOperationBatches[2], 'continuous-drain')['note'],
          'written during round two');
      expect(
          server.syncRequestTrace,
          [
            '/sync/push',
            '/sync/pull',
            '/sync/push',
            '/sync/pull',
            '/sync/push',
            '/sync/pull',
          ],
          reason: 'Each logical push+pull round must remain serialized.');
      expect(drainCompleted, isTrue,
          reason: 'The shared Future must complete after all three rounds.');
      expect(server.maxActiveSyncRequests, 1,
          reason: 'Push/pull pipelines must remain strictly serialized.');
    } finally {
      if (!firstPush.release.isCompleted) firstPush.release.complete();
      if (!secondPush.release.isCompleted) secondPush.release.complete();
      if (!thirdPush.release.isCompleted) thirdPush.release.complete();
      await Future.wait(callers);
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
    await Future<void>.delayed(const Duration(milliseconds: 600));
    expect(server.pushCalls, 1,
        reason: 'A failed drain must not schedule an internal retry.');

    await store.sync();
    expect(server.pushCalls, 2);
    expect(store.repository.queue.pending(), isEmpty);
  });
}
