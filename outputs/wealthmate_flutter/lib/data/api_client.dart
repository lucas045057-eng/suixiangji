import 'dart:async';

import 'package:http/http.dart' as http;

import '../core/network/api_session.dart';
import '../core/network/api_transport.dart';
import '../core/sync/sync_remote_data_source.dart';
import '../domain/models.dart';
import '../features/assets/data/assets_remote_data_source.dart';
import '../features/auth/data/auth_remote_data_source.dart';
import '../features/backup/data/backup_remote_data_source.dart';
import '../features/budget/data/budget_remote_data_source.dart';
import '../features/insights/data/insights_remote_data_source.dart';
import '../features/ledger/data/ledger_remote_data_source.dart';
import '../features/quick_entry/data/quick_entry_remote_data_source.dart';
import 'sync_queue.dart';
import 'token_store.dart';

export '../core/network/api_transport.dart' show ApiFailureKind, ApiFailure;
export '../core/sync/sync_remote_data_source.dart' show PullResult;

/// Compatibility façade for the legacy aggregate API entry point.
///
/// Feature HTTP contracts live in their respective RemoteDataSource classes;
/// this class retains the old public methods while owning session credentials
/// and constructing the shared transport.
class ApiClient implements ApiSession {
  ApiClient({
    required this.baseUrl,
    this.token,
    http.Client? client,
    TokenStore? tokenStore,
    this.onAuthExpired,
  })  : client = client ?? http.Client(),
        tokenStore = tokenStore ?? SecureTokenStore() {
    transport = ApiTransport(
      baseUrl: baseUrl,
      client: this.client,
      tokenProvider: () => token,
      onAuthExpired: _handleAuthExpired,
    );
    authDataSource = AuthRemoteDataSource(api: this);
    assetsDataSource = AssetsRemoteDataSource(api: this);
    backupDataSource = BackupRemoteDataSource(api: this);
    budgetDataSource = BudgetRemoteDataSource(api: this);
    insightsDataSource = InsightsRemoteDataSource(api: this);
    ledgerDataSource = LedgerRemoteDataSource(api: this);
    quickEntryDataSource = QuickEntryRemoteDataSource(api: this);
    syncDataSource = SyncRemoteDataSource(api: this);
  }

  final String? baseUrl;
  @override
  String? token;
  String? lastVerifiedUserId;
  final http.Client client;
  final TokenStore tokenStore;
  @override
  FutureOr<void> Function()? onAuthExpired;
  @override
  late final ApiTransport transport;

  late final AuthRemoteDataSource authDataSource;
  late final AssetsRemoteDataSource assetsDataSource;
  late final BackupRemoteDataSource backupDataSource;
  late final BudgetRemoteDataSource budgetDataSource;
  late final InsightsRemoteDataSource insightsDataSource;
  late final LedgerRemoteDataSource ledgerDataSource;
  late final QuickEntryRemoteDataSource quickEntryDataSource;
  late final SyncRemoteDataSource syncDataSource;

  int _sessionGeneration = 0;
  @override
  int get sessionGeneration => _sessionGeneration;
  Future<void> _credentialWrites = Future<void>.value();

  Future<void> _persistCredentials(Future<void> Function() action) {
    final next = _credentialWrites.then((_) => action());
    _credentialWrites = next.then<void>((_) {}, onError: (Object _) {});
    return next;
  }

  Future<void> _clearPersistedCredentialsBestEffort() async {
    try {
      await tokenStore.clear();
    } catch (_) {}
    try {
      await tokenStore.clearLastVerifiedUserId();
    } catch (_) {}
  }

  Future<void> _failClosedCredentials(int generation,
      [String? expectedToken]) async {
    if (generation != _sessionGeneration ||
        (expectedToken != null && expectedToken != token)) {
      return;
    }
    token = null;
    lastVerifiedUserId = null;
    await _clearPersistedCredentialsBestEffort();
  }

  @override
  void requireSession(int generation, [String? requestToken]) {
    if (generation != _sessionGeneration ||
        (requestToken != null && requestToken != token)) {
      throw const ApiFailure(ApiFailureKind.cancelled, '登录状态已变更，请重试');
    }
  }

  Future<void> _handleAuthExpired() async {
    await logout();
    await onAuthExpired?.call();
  }

  Future<bool> restoreToken() async {
    final generation = _sessionGeneration;
    await _credentialWrites;
    final restored = await tokenStore.read();
    requireSession(generation);
    if (token == null || token!.isEmpty) {
      if (restored == null || restored.isEmpty) return false;
      token = restored;
    }
    final verified = await tokenStore.readLastVerifiedUserId();
    requireSession(generation);
    lastVerifiedUserId = token == restored ? verified : null;
    return true;
  }

  @override
  int beginSession() {
    _sessionGeneration++;
    return _sessionGeneration;
  }

  @override
  Future<void> saveToken(String value, {bool newSession = true}) async {
    if (value.isEmpty) return;
    if (newSession) {
      _sessionGeneration++;
      lastVerifiedUserId = null;
    }
    final generation = _sessionGeneration;
    try {
      await _persistCredentials(() async {
        try {
          if (newSession) await tokenStore.clearLastVerifiedUserId();
          await tokenStore.write(value);
        } catch (_) {
          await _failClosedCredentials(generation);
          rethrow;
        }
      });
      requireSession(generation);
      token = value;
    } catch (error) {
      await _persistCredentials(() => _failClosedCredentials(generation));
      if (error is ApiFailure) rethrow;
      throw const ApiFailure(ApiFailureKind.network, '登录状态保存失败，请重试');
    }
  }

  @override
  Future<void> logout() async {
    _sessionGeneration++;
    token = null;
    lastVerifiedUserId = null;
    await _persistCredentials(_clearPersistedCredentialsBestEffort);
  }

  @override
  Future<void> saveLastVerifiedUserId(String userId) async {
    final normalizedUserId = userId.trim();
    if (normalizedUserId.isEmpty) return;
    final generation = _sessionGeneration;
    final verifiedToken = token;
    try {
      await _persistCredentials(() async {
        requireSession(generation, verifiedToken);
        try {
          await tokenStore.writeLastVerifiedUserId(normalizedUserId);
        } catch (_) {
          await _failClosedCredentials(generation, verifiedToken);
          rethrow;
        }
      });
      requireSession(generation, verifiedToken);
      lastVerifiedUserId = normalizedUserId;
    } catch (error) {
      await _persistCredentials(
          () => _failClosedCredentials(generation, verifiedToken));
      if (error is ApiFailure) rethrow;
      throw const ApiFailure(ApiFailureKind.network, '登录状态保存失败，请重试');
    }
  }

  // Legacy compatibility delegates. Feature implementations are owned by
  // the RemoteDataSource classes constructed above.
  Future<Map<String, Object?>> login(String username, String password) =>
      authDataSource.login(username, password);

  Future<UserProfile> fetchProfile() => authDataSource.fetchProfile();

  Future<Map<String, Object?>> register({
    required String username,
    required String password,
    String? displayName,
    required String inviteCode,
  }) =>
      authDataSource.register(
        username: username,
        password: password,
        displayName: displayName,
        inviteCode: inviteCode,
      );

  Future<void> deleteAccount(String currentPassword) =>
      authDataSource.deleteAccount(currentPassword);

  Future<UserProfile> updateProfile({
    String? displayName,
    String? username,
    List<QuickMemory>? quickMemories,
  }) =>
      authDataSource.updateProfile(
        displayName: displayName,
        username: username,
        quickMemories: quickMemories,
      );

  Future<UserProfile> changePassword(
          String currentPassword, String newPassword) =>
      authDataSource.changePassword(currentPassword, newPassword);

  Future<List<Account>> fetchAccounts() => assetsDataSource.fetchAccounts();

  Future<List<Category>> fetchCategories() =>
      ledgerDataSource.fetchCategories();

  Future<Category> createCategory(
          {required String name, required TransactionType type}) =>
      ledgerDataSource.createCategory(name: name, type: type);

  Future<Category> updateCategory(String categoryId,
          {required String name, required bool active}) =>
      ledgerDataSource.updateCategory(
        categoryId,
        name: name,
        active: active,
      );

  Future<Account> updateAccount(Account account) =>
      assetsDataSource.updateAccount(account);

  Future<List<FinanceTransaction>> fetchTransactions() =>
      ledgerDataSource.fetchTransactions();

  Future<Map<String, Object?>> fetchStats(String monthKey) =>
      insightsDataSource.fetchStats(monthKey);

  Future<Map<String, Object?>> fetchWealth() =>
      assetsDataSource.fetchWealth();

  Future<Map<String, Object?>> fetchMonthlyReport(String monthKey,
          {bool force = false}) =>
      insightsDataSource.fetchMonthlyReport(monthKey, force: force);

  Future<Map<String, Object?>> fetchExchangeRate(String base,
          {String quote = 'CNY'}) =>
      assetsDataSource.fetchExchangeRate(base, quote: quote);

  Future<Map<String, Object?>> saveExchangeRate(Map<String, Object?> rate) =>
      assetsDataSource.saveExchangeRate(rate);

  Future<Map<String, Object?>> exportBackup() =>
      backupDataSource.exportBackup();

  Future<Map<String, Object?>> restoreBackup(Map<String, Object?> backup) =>
      backupDataSource.restoreBackup(backup);

  Future<List<Budget>> fetchBudgets({String? month}) =>
      budgetDataSource.fetchBudgets(month: month);

  Future<Budget> createBudget(Budget budget) =>
      budgetDataSource.createBudget(budget);

  Future<Budget> updateBudget(
          String budgetId, Map<String, Object?> changes) =>
      budgetDataSource.updateBudget(budgetId, changes);

  Future<void> deleteBudget(String budgetId) =>
      budgetDataSource.deleteBudget(budgetId);

  Future<AgentDraft> postAgentDraft(String text) =>
      quickEntryDataSource.createDraft(text);

  Future<Map<String, Object?>> push(List<SyncOperation> operations) =>
      syncDataSource.push(operations);

  Future<PullResult> pullChanges(int sinceVersion) =>
      syncDataSource.pullChanges(sinceVersion);

  Future<List<FinanceTransaction>> pull(int sinceVersion) async =>
      (await pullChanges(sinceVersion)).transactions;
}
