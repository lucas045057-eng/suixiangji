import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wealthmate_flutter/data/finance_repository.dart';
import 'package:wealthmate_flutter/data/local_repository.dart';
import 'package:wealthmate_flutter/data/sync_queue.dart';
import 'package:wealthmate_flutter/features/app_update/data/app_update_remote_data_source.dart';
import 'package:wealthmate_flutter/features/app_update/domain/app_version.dart';
import 'package:wealthmate_flutter/features/app_update/state/app_update_store.dart';
import 'package:wealthmate_flutter/main.dart';
import 'package:wealthmate_flutter/state/finance_store.dart';
import 'package:wealthmate_flutter/ui/app_update_dialog.dart';

import 'core/two_device_sync_test.dart' show SyncMemory;
import 'features/app_update/app_update_store_test.dart' show UnusedApiSession;

class VersionSource extends AppUpdateRemoteDataSource {
  VersionSource({this.failFirst = false}) : super(api: UnusedApiSession());
  final bool failFirst;
  int calls = 0;
  @override
  Future<AppVersion> fetch() async {
    calls++;
    if (failFirst && calls == 1) throw Exception('offline');
    return AppVersion.fromJson({
      'latest_version': '1.0.5',
      'latest_build': 9,
      'minimum_supported_version': '1.0.0',
      'minimum_supported_build': 3,
      'force_update': false,
      'download_url': 'https://download.invalid/build9.apk',
      'release_notes': '更新提示及下载修复',
    });
  }
}

Future<AppUpdateStore> mountApp(
    WidgetTester tester, VersionSource remote) async {
  final store = FinanceStore(
      repository: FinanceRepository(
          local: LocalRepository(SyncMemory()), queue: SyncQueue()));
  final updates =
      AppUpdateStore(remote: remote, currentVersion: '1.0.4', currentBuild: 7);
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    updates.dispose();
    store.dispose();
  });
  await tester.pumpWidget(WealthMateApp(store: store, updates: updates));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  return updates;
}

void main() {
  testWidgets('cold startup shows an optional update beneath MaterialApp',
      (tester) async {
    await mountApp(tester, VersionSource());
    expect(tester.takeException(), isNull);
    expect(find.byType(AppUpdateDialog), findsOneWidget);
    expect(find.text('发现新版本'), findsOneWidget);
    await tester.tap(find.text('稍后'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(AppUpdateDialog), findsNothing);
  });

  testWidgets(
      'resume retries an offline startup check without duplicate dialogs',
      (tester) async {
    final remote = VersionSource(failFirst: true);
    await mountApp(tester, remote);
    expect(find.byType(AppUpdateDialog), findsNothing);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);
    expect(find.byType(AppUpdateDialog), findsOneWidget);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(remote.calls, 2);
    expect(find.byType(AppUpdateDialog), findsOneWidget);
  });
}
