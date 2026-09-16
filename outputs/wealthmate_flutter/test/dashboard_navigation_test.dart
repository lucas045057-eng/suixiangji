import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wealthmate_flutter/data/finance_repository.dart';
import 'package:wealthmate_flutter/data/local_repository.dart';
import 'package:wealthmate_flutter/data/sync_queue.dart';
import 'package:wealthmate_flutter/domain/demo_state.dart';
import 'package:wealthmate_flutter/state/finance_store.dart';
import 'package:wealthmate_flutter/ui/app_shell.dart';
import 'package:wealthmate_flutter/ui/ledger_page.dart';
import 'package:wealthmate_flutter/ui/theme.dart';

class _Memory implements KeyValueStore {
  @override
  Future<String?> read(String key) async => null;

  @override
  Future<void> write(String key, String value) async {}
}

FinanceStore _store() => FinanceStore(
      repository: FinanceRepository(
        local: LocalRepository(_Memory()),
        queue: SyncQueue(),
      ),
      initialState: DemoData.create(DateTime(2026, 9, 1)),
    );

class _PushObserver extends NavigatorObserver {
  int pushes = 0;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushes++;
    super.didPush(route, previousRoute);
  }
}

void main() {
  testWidgets('mobile 查看全部 selects the existing ledger tab', (tester) async {
    final observer = _PushObserver();
    await tester.pumpWidget(MaterialApp(
      theme: wealthMateTheme(),
      navigatorObservers: [observer],
      home: AppShell(store: _store()),
    ));

    await tester.ensureVisible(find.text('查看全部'));
    await tester.tap(find.text('查看全部'));
    await tester.pumpAndSettle();

    expect(find.byType(LedgerPage), findsOneWidget);
    expect(find.text('每一笔都值得被看见'), findsOneWidget);
    expect(observer.pushes, 1);
  });

  testWidgets('desktop 查看全部 selects the existing ledger tab', (tester) async {
    final observer = _PushObserver();
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(MaterialApp(
      theme: wealthMateTheme(),
      navigatorObservers: [observer],
      home: AppShell(store: _store()),
    ));

    await tester.ensureVisible(find.text('查看全部'));
    await tester.tap(find.text('查看全部'));
    await tester.pumpAndSettle();

    expect(find.byType(LedgerPage), findsOneWidget);
    expect(find.text('每一笔都值得被看见'), findsOneWidget);
    expect(observer.pushes, 1);
  });
}
