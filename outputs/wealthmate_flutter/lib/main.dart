import 'dart:async';

import 'package:flutter/material.dart';

import 'core/database/local_state_session.dart';
import 'data/api_client.dart';
import 'data/drift_database.dart';
import 'data/finance_repository.dart';
import 'data/local_repository.dart';
import 'data/sync_queue.dart';
import 'features/auth/data/auth_remote_data_source.dart';
import 'features/auth/data/auth_repository.dart';
import 'features/auth/state/auth_store.dart';
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
  if (api != null) await api.restoreToken();
  final local = LocalRepository(DriftKeyValueStore(database));
  final queue = SyncQueue();
  final session = LocalStateSession(local: local, queue: queue);
  final auth = api == null
      ? null
      : AuthStore(
          repository: AuthRepository(
            remote: AuthRemoteDataSource(api: api),
          ),
        );
  final repository = FinanceRepository(
    local: local,
    queue: queue,
    session: session,
    api: api,
  );
  final store = FinanceStore(repository: repository, authStore: auth);
  await store.load();
  runApp(WealthMateApp(store: store, api: api, auth: auth));
}

class WealthMateApp extends StatefulWidget {
  const WealthMateApp({required this.store, this.api, this.auth, super.key});

  final FinanceStore store;
  final ApiClient? api;
  final AuthStore? auth;

  @override
  State<WealthMateApp> createState() => _WealthMateAppState();
}

class _WealthMateAppState extends State<WealthMateApp> {
  late bool authenticated;

  @override
  void initState() {
    super.initState();
    authenticated = widget.api == null ||
        (widget.api!.token != null && widget.api!.lastVerifiedUserId != null);
    widget.auth?.onAuthExpired = _handleAuthExpired;
  }

  @override
  void dispose() {
    widget.auth?.onAuthExpired = null;
    super.dispose();
  }

  void _handleAuthExpired() {
    widget.store.clearAuthenticatedSession();
    if (mounted) setState(() => authenticated = false);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: '随想记',
      theme: wealthMateTheme(),
      home: widget.api == null || authenticated
          ? AppShell(
              store: widget.store,
              auth: widget.auth,
              onLoggedOut: _handleAuthExpired,
            )
          : LoginPage(
              auth: widget.auth!,
              pendingCleanupMessage: widget.store.pendingDeletionCleanupMessage,
              onRetryCleanup: widget.store.retryPendingDeletionCleanup,
              onLoggedIn: _handleLoggedIn),
    );
  }

  void _handleLoggedIn() {
    final profile = widget.auth?.profile;
    if (profile == null) return;
    unawaited(widget.store.loadAuthenticatedProfile(profile).then((_) {
      if (!mounted || widget.auth?.profile?.id != profile.id) return;
      setState(() => authenticated = true);
    }));
  }
}
