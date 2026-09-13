import 'dart:async';

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'core/config/app_config.dart';
import 'core/database/local_state_session.dart';
import 'data/api_client.dart';
import 'data/drift_database.dart';
import 'data/finance_repository.dart';
import 'data/local_repository.dart';
import 'data/sync_queue.dart';
import 'features/auth/data/auth_remote_data_source.dart';
import 'features/auth/data/auth_repository.dart';
import 'features/auth/state/auth_store.dart';
import 'features/app_update/data/app_update_remote_data_source.dart';
import 'features/app_update/state/app_update_store.dart';
import 'state/finance_store.dart';
import 'ui/app_shell.dart';
import 'ui/app_update_dialog.dart';
import 'ui/login_page.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final database = await AppDatabase.open();
  final appConfig = AppConfig.fromEnvironment();
  final baseUrl = appConfig.apiBaseUrl;
  final token = const String.fromEnvironment('WEALTHMATE_API_TOKEN');
  final api = baseUrl == null || appConfig.configurationError != null
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
  var appVersion = kProductVersion;
  var appBuild = kProductBuild;
  try {
    final packageInfo = await PackageInfo.fromPlatform();
    if (packageInfo.version.trim().isNotEmpty) {
      appVersion = packageInfo.version.trim();
    }
    appBuild = int.tryParse(packageInfo.buildNumber) ?? kProductBuild;
  } catch (_) {}
  final updates = api == null
      ? null
      : AppUpdateStore(
          remote: AppUpdateRemoteDataSource(api: api),
          currentVersion: appVersion,
          currentBuild: appBuild,
        );
  runApp(WealthMateApp(
    store: store,
    api: api,
    auth: auth,
    updates: updates,
    appVersion: appVersion,
    appBuild: appBuild,
    configurationError: appConfig.configurationError,
  ));
}

class WealthMateApp extends StatefulWidget {
  const WealthMateApp({
    required this.store,
    this.api,
    this.auth,
    this.updates,
    this.appVersion = kProductVersion,
    this.appBuild = kProductBuild,
    this.configurationError,
    super.key,
  });

  final FinanceStore store;
  final ApiClient? api;
  final AuthStore? auth;
  final AppUpdateStore? updates;
  final String appVersion;
  final int appBuild;
  final String? configurationError;

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
    final updates = widget.updates;
    if (updates != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(_checkForStartupUpdate(updates));
      });
    }
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

  Future<void> _checkForStartupUpdate(AppUpdateStore updates) async {
    await updates.check();
    if (!mounted || !updates.updateAvailable) return;
    final version = updates.remoteVersion;
    if (version == null) return;
    await showAppUpdateDialog(
      context,
      version: version,
      forceUpdate: updates.forceUpdate,
    );
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
              updates: widget.updates,
              appVersion: widget.appVersion,
              appBuild: widget.appBuild,
              configurationError: widget.configurationError,
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
