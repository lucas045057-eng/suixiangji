import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wealthmate_flutter/state/finance_store.dart';
import 'package:wealthmate_flutter/ui/app_shell.dart';

import 'core/two_device_sync_test.dart'
    show MemorySyncServer, SyncBarrier, syncDevice;

class _RecordingFinanceStore extends FinanceStore {
  _RecordingFinanceStore({
    required super.repository,
    required super.initialState,
  });

  final syncFutures = <Future<void>>[];

  @override
  Future<void> sync() {
    final future = super.sync();
    syncFutures.add(future);
    return future;
  }
}

Future<void> _pumpUntil(WidgetTester tester, bool Function() condition) async {
  for (var attempt = 0; attempt < 20 && !condition(); attempt++) {
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
    await tester.pump();
  }
  expect(condition(), isTrue,
      reason: 'The expected asynchronous boundary was not reached.');
}

Future<FinanceStore> _mountAuthenticated(
    WidgetTester tester, MemorySyncServer server) async {
  final store = await syncDevice(server);
  await tester.pumpWidget(
      MaterialApp(home: AppShell(store: store, auth: store.authStore)));
  await _pumpUntil(tester, () => server.pullCalls == 1);
  return store;
}

void main() {
  testWidgets('authenticated startup/login requests an initial sync',
      (tester) async {
    final server = MemorySyncServer();

    final store = await _mountAuthenticated(tester, server);

    expect(store.isDemoMode, isFalse);
    expect(server.pullCalls, 1);
    expect(server.maxActiveSyncRequests, 1);
  });

  testWidgets('resumed requests sync for an authenticated foreground app',
      (tester) async {
    final server = MemorySyncServer();
    await _mountAuthenticated(tester, server);
    final pullsBeforeResume = server.pullCalls;

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await _pumpUntil(tester, () => server.pullCalls > pullsBeforeResume);

    expect(server.pullCalls, pullsBeforeResume + 1);
  });

  testWidgets('30-second foreground timer requests sync on its first tick',
      (tester) async {
    final server = MemorySyncServer();
    await _mountAuthenticated(tester, server);
    final pullsBeforeTimer = server.pullCalls;

    await tester.pump(const Duration(seconds: 29, milliseconds: 999));
    expect(server.pullCalls, pullsBeforeTimer);
    await tester.pump(const Duration(milliseconds: 1));
    await _pumpUntil(tester, () => server.pullCalls > pullsBeforeTimer);

    expect(server.pullCalls, pullsBeforeTimer + 1);
  });

  for (final state in const [
    AppLifecycleState.paused,
    AppLifecycleState.inactive,
    AppLifecycleState.detached,
  ]) {
    testWidgets('30-second timer is cancelled while ${state.name}',
        (tester) async {
      final server = MemorySyncServer();
      await _mountAuthenticated(tester, server);
      final pullsBeforeBackground = server.pullCalls;

      tester.binding.handleAppLifecycleStateChanged(state);
      await tester.pump();
      await tester.pump(const Duration(seconds: 31));

      expect(server.pullCalls, pullsBeforeBackground,
          reason: 'Background lifecycle states must not retain the timer.');
    });
  }

  testWidgets('lifecycle request while active reuses the current drain Future',
      (tester) async {
    final server = MemorySyncServer();
    final base = await syncDevice(server);
    final store = _RecordingFinanceStore(
      repository: base.repository,
      initialState: base.state,
    );
    final pull = SyncBarrier();
    server.pullBarrier = pull;
    await tester.pumpWidget(MaterialApp(home: AppShell(store: store)));
    await _pumpUntil(tester, () => pull.entered.isCompleted);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();

    try {
      expect(store.syncFutures, hasLength(2),
          reason: 'Resume must make a request even while a drain is active.');
      expect(identical(store.syncFutures.first, store.syncFutures.last), isTrue,
          reason: 'Lifecycle callers must join the active drain Future.');
      expect(server.maxActiveSyncRequests, 1);
    } finally {
      pull.release.complete();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1));
    }
  });
}
