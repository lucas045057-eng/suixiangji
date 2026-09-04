import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wealthmate_flutter/data/finance_repository.dart';
import 'package:wealthmate_flutter/data/local_repository.dart';
import 'package:wealthmate_flutter/data/sync_queue.dart';
import 'package:wealthmate_flutter/domain/demo_state.dart';
import 'package:wealthmate_flutter/state/finance_store.dart';
import 'package:wealthmate_flutter/ui/app_shell.dart';
import 'package:wealthmate_flutter/ui/theme.dart';

class OverviewMemory implements KeyValueStore {
  @override
  Future<String?> read(String key) async => null;

  @override
  Future<void> write(String key, String value) async {}
}

FinanceStore overviewStore() => FinanceStore(
      repository: FinanceRepository(
          local: LocalRepository(OverviewMemory()), queue: SyncQueue()),
      initialState: DemoData.create(DateTime(2026, 9, 1)),
    );

void main() {
  testWidgets('overview navigation exposes five product areas', (tester) async {
    await tester.pumpWidget(MaterialApp(
        theme: wealthMateTheme(), home: AppShell(store: overviewStore())));

    expect(find.text('首页'), findsOneWidget);
    expect(find.text('账本'), findsOneWidget);
    expect(find.text('统计'), findsOneWidget);
    expect(find.text('财富'), findsOneWidget);
    expect(find.text('我的'), findsOneWidget);
  });

  testWidgets('settings identifies missing API configuration and demo recovery',
      (tester) async {
    final store = overviewStore();
    await tester.pumpWidget(
        MaterialApp(theme: wealthMateTheme(), home: AppShell(store: store)));
    await tester.tap(find.text('我的'));
    await tester.pumpAndSettle();

    expect(find.textContaining('离线演示/待配置'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('恢复演示数据'), 400,
        scrollable: find.byType(Scrollable).first);
    expect(find.text('恢复演示数据'), findsOneWidget);
  });

  testWidgets('home exposes only 快捷记 and 记一笔 without a floating action button',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        theme: wealthMateTheme(), home: AppShell(store: overviewStore())));

    expect(find.text('快捷记'), findsOneWidget);
    expect(find.text('记一笔'), findsOneWidget);
    expect(find.byType(FloatingActionButton), findsNothing);
  });

  testWidgets('settings exposes account naming and editable login profile',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        theme: wealthMateTheme(), home: AppShell(store: overviewStore())));

    await tester.tap(find.text('我的'));
    await tester.pumpAndSettle();

    expect(find.text('账户名称与账户配置'), findsOneWidget);
    expect(find.text('账户与登录'), findsOneWidget);

    await tester.tap(find.text('账户与登录'));
    await tester.pumpAndSettle();

    expect(find.text('修改登录资料'), findsOneWidget);
    expect(find.text('登录用户名'), findsOneWidget);
    expect(find.text('修改密码'), findsOneWidget);
  });
}
