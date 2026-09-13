import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wealthmate_flutter/data/api_client.dart';
import 'package:wealthmate_flutter/data/finance_repository.dart';
import 'package:wealthmate_flutter/data/local_repository.dart';
import 'package:wealthmate_flutter/data/sync_queue.dart';
import 'package:wealthmate_flutter/domain/demo_state.dart';
import 'package:wealthmate_flutter/features/app_update/data/app_update_remote_data_source.dart';
import 'package:wealthmate_flutter/features/app_update/domain/app_version.dart';
import 'package:wealthmate_flutter/features/app_update/state/app_update_store.dart';
import 'package:wealthmate_flutter/state/finance_store.dart';
import 'package:wealthmate_flutter/ui/app_shell.dart';
import 'package:wealthmate_flutter/ui/app_update_dialog.dart';
import 'package:wealthmate_flutter/ui/theme.dart';

class EmptyMemory implements KeyValueStore {
  @override
  Future<String?> read(String key) async => null;

  @override
  Future<void> write(String key, String value) async {}
}

FinanceStore demoStore() => FinanceStore(
      repository: FinanceRepository(
        local: LocalRepository(EmptyMemory()),
        queue: SyncQueue(),
      ),
      initialState: DemoData.create(DateTime(2026, 9, 1)),
    );

AppUpdateStore updateStore() => AppUpdateStore(
      remote: AppUpdateRemoteDataSource(
        api: ApiClient(baseUrl: 'https://api.example.invalid'),
      ),
      currentVersion: '1.0.0',
      currentBuild: 3,
    );

AppVersion availableVersion() => AppVersion.fromJson({
      'latest_version': '1.0.1',
      'latest_build': 4,
      'minimum_supported_version': '1.0.0',
      'minimum_supported_build': 3,
      'force_update': false,
      'download_url': 'https://download.invalid/app.apk',
      'release_notes': '修复同步问题',
    });

void main() {
  testWidgets('settings shows current build and manual update check',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: wealthMateTheme(),
      home: AppShell(store: demoStore(), updates: updateStore()),
    ));

    await tester.tap(find.text('我的'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('当前版本 1.0.0 (3)'),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(find.text('当前版本 1.0.0 (3)'), findsOneWidget);
    expect(find.text('检查更新'), findsOneWidget);
  });

  testWidgets('ordinary update dialog offers later and immediate actions',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: AppUpdateDialog(
        version: availableVersion(),
        forceUpdate: false,
        onLaunch: (Uri _) async => true,
      ),
    ));

    expect(find.text('稍后'), findsOneWidget);
    expect(find.text('立即更新'), findsOneWidget);
  });

  testWidgets('forced update dialog has no later action', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: AppUpdateDialog(
        version: availableVersion(),
        forceUpdate: true,
        onLaunch: (Uri _) async => true,
      ),
    ));

    expect(find.text('稍后'), findsNothing);
    expect(find.text('立即更新'), findsOneWidget);
  });

  testWidgets('update check failure leaves the app shell usable',
      (tester) async {
    final updates = updateStore();
    await updates.check();
    await tester.pumpWidget(MaterialApp(
      theme: wealthMateTheme(),
      home: AppShell(store: demoStore(), updates: updates),
    ));

    expect(find.text('快捷记'), findsOneWidget);
    expect(updates.status, AppUpdateStatus.failed);
  });
}
