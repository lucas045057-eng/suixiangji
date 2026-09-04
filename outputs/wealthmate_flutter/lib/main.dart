import 'package:flutter/material.dart';

import 'data/api_client.dart';
import 'data/drift_database.dart';
import 'data/finance_repository.dart';
import 'data/local_repository.dart';
import 'data/sync_queue.dart';
import 'state/finance_store.dart';
import 'ui/app_shell.dart';
import 'ui/login_page.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final database = await AppDatabase.open();
  final baseUrl = const String.fromEnvironment('WEALTHMATE_API_BASE_URL');
  final token = const String.fromEnvironment('WEALTHMATE_API_TOKEN');
  final api = baseUrl.isEmpty
      ? null
      : ApiClient(baseUrl: baseUrl, token: token.isEmpty ? null : token);
  final repository = FinanceRepository(
    local: LocalRepository(DriftKeyValueStore(database)),
    queue: SyncQueue(),
    api: api,
  );
  final store = FinanceStore(repository: repository);
  await store.load();
  runApp(WealthMateApp(store: store, api: api));
}

class WealthMateApp extends StatelessWidget {
  const WealthMateApp({required this.store, this.api, super.key});

  final FinanceStore store;
  final ApiClient? api;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: '随想记',
      theme: wealthMateTheme(),
      home: api == null || api!.token != null
          ? AppShell(store: store)
          : LoginPage(
              api: api!,
              onLoggedIn: () => runApp(WealthMateApp(store: store, api: api))),
    );
  }
}
