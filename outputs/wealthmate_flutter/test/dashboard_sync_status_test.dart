import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wealthmate_flutter/data/sync_queue.dart';
import 'package:wealthmate_flutter/domain/models.dart';
import 'package:wealthmate_flutter/state/finance_store.dart';
import 'package:wealthmate_flutter/ui/dashboard_page.dart';

import 'core/two_device_sync_test.dart'
    show
        MemorySyncServer,
        SyncBarrier,
        SyncMemory,
        syncDevice,
        syncSeed,
        syncTransaction;

Widget dashboard(FinanceStore store) => MaterialApp(
        home: Scaffold(
            body: DashboardPage(
      ledger: store.ledger,
      isDemoMode: store.isDemoMode,
      onSync: store.sync,
      openComposer: (_, {smart = false}) {},
      openBudgets: () {},
    )));

void main() {
  final cases = <(SyncState, List<String>, int, String)>[
    (const SyncState(isSyncing: true, error: 'failed'), ['sync:x'], 2, '同步中…'),
    (const SyncState(error: 'failed'), ['sync:x'], 2, '同步失败'),
    (
      const SyncState(lastSyncedAt: '2026-09-15T10:30:00'),
      ['sync:x'],
      2,
      '有冲突待处理'
    ),
    (const SyncState(lastSyncedAt: '2026-09-15T10:30:00'), [], 2, '有 2 条待同步数据'),
    (const SyncState(lastSyncedAt: '2026-09-15T10:30:00'), [], 0, '已同步'),
    (const SyncState(), [], 0, '离线演示/待配置'),
  ];
  for (final row in cases) {
    testWidgets('dashboard status precedence: ${row.$4}', (tester) async {
      final store = await syncDevice(MemorySyncServer(),
          initial: syncSeed.copyWith(syncState: row.$1, conflicts: row.$2));
      for (var i = 0; i < row.$3; i++) {
        store.repository.queue.enqueue(SyncOperation(
            clientOpId: 'op-$i',
            entity: 'transactions',
            entityId: 'tx-$i',
            type: SyncOperationType.upsert,
            payload: {}));
      }
      await tester.pumpWidget(dashboard(store));
      expect(find.textContaining(row.$4), findsOneWidget);
      if (row.$4 == '已同步') expect(find.textContaining('10:30'), findsOneWidget);
    });
  }

  testWidgets(
      'retry button shows syncing through acceptance and pull completion',
      (tester) async {
    final server = MemorySyncServer();
    final store = await syncDevice(server);
    await store.addTransaction(syncTransaction('a'));
    server.failPush = true;
    await store.sync();
    await tester.pumpWidget(dashboard(store));
    expect(find.text('同步失败'), findsOneWidget);
    final push = SyncBarrier();
    final pull = SyncBarrier();
    server.pushBarrier = push;
    server.pullBarrier = pull;
    await tester.tap(find.byTooltip('同步'));
    await tester.pump();
    await push.entered.future;
    expect(store.state.syncState.isSyncing, isTrue);
    expect(find.text('同步中…'), findsOneWidget);
    expect(store.state.syncState.lastSyncedAt, isNull);
    push.release.complete();
    await tester.pump();
    await pull.entered.future;
    expect(store.state.syncState.isSyncing, isTrue);
    expect(store.state.syncState.lastSyncedAt, isNull);
    expect((await store.repository.load())!.syncState.lastSyncedAt, isNull);
    expect(find.textContaining('已同步'), findsNothing);
    pull.release.complete();
    await tester.pumpAndSettle();
    expect(store.state.syncState.isSyncing, isFalse);
    expect(store.state.syncState.lastSyncedAt, isNotNull);
    expect(find.textContaining('已同步'), findsOneWidget);
    expect(store.repository.queue.pending(), isEmpty);
    expect(server.pushCalls, 2);
  });

  test('store clears syncing after pull failure and retains previous success',
      () async {
    final server = MemorySyncServer();
    final store = await syncDevice(server);
    await store.sync();
    final prior = store.state.syncState.lastSyncedAt;
    server.failPull = true;
    await store.sync();
    expect(store.state.syncState.isSyncing, isFalse);
    expect(store.state.syncState.error, isNotNull);
    expect(store.state.syncState.lastSyncedAt, prior);
  });

  test('editing during sync shares the active drain Future with every caller',
      () async {
    final server = MemorySyncServer();
    final store = await syncDevice(server);
    await store.addTransaction(syncTransaction('a'));
    final barrier = SyncBarrier();
    server.pushBarrier = barrier;
    final syncing = store.sync();
    await barrier.entered.future;
    final duplicate = store.sync();
    var duplicateCompleted = false;
    duplicate.whenComplete(() => duplicateCompleted = true);
    try {
      expect(store.state.syncState.isSyncing, isTrue);
      await store.updateTransaction(
          store.state.transactions.single.copyWith(note: 'edited'));
      expect(store.state.syncState.isSyncing, isTrue);
      expect(store.ledger.state.syncState.isSyncing, isTrue);
      await Future<void>.delayed(Duration.zero);
      expect(identical(syncing, duplicate), isTrue,
          reason: 'Every active caller must receive the same drain Future.');
      expect(duplicateCompleted, isFalse,
          reason: 'The shared Future must not complete before the drain.');
      expect(server.pushCalls, 1);
    } finally {
      barrier.release.complete();
      await syncing;
      await duplicate;
    }
    expect(store.state.syncState.isSyncing, isFalse);
  });

  testWidgets('successful status and time survive restart without activity',
      (tester) async {
    final server = MemorySyncServer();
    final memory = SyncMemory();
    final store = await syncDevice(server, memory: memory);
    await store.sync();
    final time = store.state.syncState.lastSyncedAt;
    expect(time, isNotNull);
    final restarted = await syncDevice(server, memory: memory);
    expect(restarted.state.syncState.lastSyncedAt, time);
    expect(restarted.state.syncState.isSyncing, isFalse);
    await tester.pumpWidget(dashboard(restarted));
    expect(find.textContaining('已同步'), findsOneWidget);
  });
}
