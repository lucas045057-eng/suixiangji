import 'dart:async';

import 'package:http/http.dart' as http;

import '../core/network/api_transport.dart';
import '../domain/models.dart';
import 'sync_queue.dart';
import 'token_store.dart';

export '../core/network/api_transport.dart' show ApiFailureKind, ApiFailure;

class ApiClient {
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
  }

  final String? baseUrl;
  String? token;
  String? lastVerifiedUserId;
  final http.Client client;
  final TokenStore tokenStore;
  FutureOr<void> Function()? onAuthExpired;
  late final ApiTransport transport;
  int _sessionGeneration = 0;

  Future<void> _handleAuthExpired() async {
    await logout();
    await onAuthExpired?.call();
  }

  Future<bool> restoreToken() async {
    if (token == null || token!.isEmpty) {
      final restored = await tokenStore.read();
      if (restored == null || restored.isEmpty) return false;
      token = restored;
    }
    lastVerifiedUserId = await tokenStore.readLastVerifiedUserId();
    return true;
  }

  void beginSession() {
    _sessionGeneration++;
  }

  Future<void> saveToken(String value) async {
    await _saveToken(value);
  }

  Future<void> _saveToken(String value, {int? expectedGeneration}) async {
    if (value.isEmpty) return;
    if (expectedGeneration != null &&
        expectedGeneration != _sessionGeneration) return;
    token = value;
    await tokenStore.write(value);
  }

  Future<void> logout() async {
    _sessionGeneration++;
    token = null;
    lastVerifiedUserId = null;
    await tokenStore.clear();
    await tokenStore.clearLastVerifiedUserId();
  }

  Future<void> saveLastVerifiedUserId(String userId,
      {int? expectedGeneration}) async {
    final normalizedUserId = userId.trim();
    if (normalizedUserId.isEmpty) return;
    if (expectedGeneration != null &&
        expectedGeneration != _sessionGeneration) return;
    lastVerifiedUserId = normalizedUserId;
    await tokenStore.writeLastVerifiedUserId(normalizedUserId);
  }

  Future<Map<String, Object?>> login(String username, String password) async {
    beginSession();
    final requestGeneration = _sessionGeneration;
    final result = await _requestMap('POST', '/auth/login',
        body: {'username': username, 'password': password}, includeAuth: false);
    final accessToken =
        result['access_token'] as String? ?? result['token'] as String?;
    if (accessToken == null || accessToken.isEmpty) {
      throw const ApiFailure(ApiFailureKind.server, '登录响应中没有访问令牌');
    }
    await _saveToken(accessToken, expectedGeneration: requestGeneration);
    return result;
  }

  Future<UserProfile> fetchProfile() async {
    final requestGeneration = _sessionGeneration;
    final json = await _requestMap('GET', '/auth/me');
    final profile = UserProfile.fromJson(json);
    await saveLastVerifiedUserId(
      profile.id,
      expectedGeneration: requestGeneration,
    );
    return profile;
  }

  Future<UserProfile> updateProfile(
      {String? displayName,
      String? username,
      List<QuickMemory>? quickMemories}) async {
    final requestGeneration = _sessionGeneration;
    final json = await _requestMap('PATCH', '/auth/me', body: {
      if (displayName != null) 'display_name': displayName,
      if (username != null) 'username': username,
      if (quickMemories != null)
        'quick_memories': quickMemories.map((item) => item.toJson()).toList(),
    });
    final accessToken = json['access_token'] as String?;
    if (accessToken != null && accessToken.isNotEmpty)
      await _saveToken(accessToken, expectedGeneration: requestGeneration);
    return UserProfile.fromJson(json);
  }

  Future<UserProfile> changePassword(
      String currentPassword, String newPassword) async {
    final requestGeneration = _sessionGeneration;
    final json = await _requestMap('POST', '/auth/password', body: {
      'current_password': currentPassword,
      'new_password': newPassword,
    });
    final accessToken = json['access_token'] as String?;
    if (accessToken != null && accessToken.isNotEmpty)
      await _saveToken(accessToken, expectedGeneration: requestGeneration);
    return UserProfile.fromJson(json);
  }

  Future<List<Account>> fetchAccounts() async {
    final json = await _requestMap('GET', '/accounts');
    return _items(json).map((item) => Account.fromJson(item)).toList();
  }

  Future<List<Category>> fetchCategories() async {
    final json = await _requestMap('GET', '/categories');
    return _items(json).map((item) => Category.fromJson(item)).toList();
  }

  Future<Category> createCategory(
      {required String name, required TransactionType type}) async {
    final json = await _requestMap('POST', '/categories',
        body: {'name': name, 'kind': transactionTypeToJson(type)});
    return Category.fromJson(json);
  }

  Future<Category> updateCategory(String categoryId,
      {required String name, required bool active}) async {
    final json = await _requestMap('PATCH', '/categories/$categoryId',
        body: {'name': name, 'active': active});
    return Category.fromJson(json);
  }

  Future<Account> updateAccount(Account account) async {
    final json = await _requestMap('PATCH', '/accounts/${account.id}',
        body: account.toJson());
    return Account.fromJson(json);
  }

  Future<List<FinanceTransaction>> fetchTransactions() async {
    final json = await _requestMap('GET', '/transactions');
    return _items(json)
        .map((item) => FinanceTransaction.fromJson(item))
        .toList();
  }

  Future<Map<String, Object?>> fetchStats(String monthKey) =>
      _requestMap('GET', '/stats?month=$monthKey');

  Future<Map<String, Object?>> fetchWealth() => _requestMap('GET', '/wealth');

  Future<Map<String, Object?>> fetchMonthlyReport(String monthKey,
          {bool force = false}) =>
      _requestMap('GET', '/reports/monthly/$monthKey?force=$force');

  Future<Map<String, Object?>> fetchExchangeRate(String base,
          {String quote = 'CNY'}) =>
      _requestMap('GET', '/exchange/rates?base=$base&quote=$quote');

  Future<Map<String, Object?>> saveExchangeRate(Map<String, Object?> rate) =>
      _requestMap('POST', '/exchange/rates', body: rate);

  Future<Map<String, Object?>> exportBackup() =>
      _requestMap('GET', '/backup/export');

  Future<Map<String, Object?>> restoreBackup(Map<String, Object?> backup) =>
      _requestMap('POST', '/backup/restore', body: backup);

  Future<List<Budget>> fetchBudgets({String? month}) async {
    final json = await _requestMap(
        'GET', month == null ? '/budgets' : '/budgets?month=$month');
    return _items(json).map((item) => Budget.fromJson(item)).toList();
  }

  Future<Budget> createBudget(Budget budget) async {
    final json = await _requestMap('POST', '/budgets', body: budget.toJson());
    return Budget.fromJson(json);
  }

  Future<Budget> updateBudget(
      String budgetId, Map<String, Object?> changes) async {
    final json =
        await _requestMap('PATCH', '/budgets/$budgetId', body: changes);
    return Budget.fromJson(json);
  }

  Future<void> deleteBudget(String budgetId) async {
    await _requestMap('DELETE', '/budgets/$budgetId');
  }

  Future<AgentDraft> postAgentDraft(String text) async {
    final json =
        await _requestMap('POST', '/agent/draft', body: {'text': text});
    return AgentDraft(
      amount: (json['amount'] as num?)?.toDouble() ?? 0,
      type: transactionTypeFromJson(json['type']),
      categoryId: json['category_id'] as String?,
      accountId: json['account_id'] as String?,
      date: json['date'] as String? ?? '',
      note: json['note'] as String? ?? text,
      currency: json['currency'] as String? ?? 'CNY',
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0,
      missingFacts: (json['missing_facts'] as List<Object?>?)?.cast<String>() ??
          const <String>[],
    );
  }

  Future<Map<String, Object?>> push(List<SyncOperation> operations) {
    return _requestMap('POST', '/sync/push',
        body: {'operations': operations.map((item) => item.toJson()).toList()});
  }

  Future<PullResult> pullChanges(int sinceVersion) async {
    final json =
        await _requestMap('GET', '/sync/pull?since_version=$sinceVersion');
    final transactionItems = _items(json);
    final accountItems =
        ((json['accounts'] as List<Object?>?) ?? const <Object?>[])
            .map((item) => (item! as Map).cast<String, Object?>())
            .toList();
    final categoryItems =
        ((json['categories'] as List<Object?>?) ?? const <Object?>[])
            .map((item) => (item! as Map).cast<String, Object?>())
            .toList();
    final budgetItems =
        ((json['budgets'] as List<Object?>?) ?? const <Object?>[])
            .map((item) => (item! as Map).cast<String, Object?>())
            .toList();
    return PullResult(
      transactions: transactionItems
          .map((item) => FinanceTransaction.fromJson(item))
          .toList(),
      accounts: accountItems.map((item) => Account.fromJson(item)).toList(),
      categories: categoryItems.map((item) => Category.fromJson(item)).toList(),
      budgets: budgetItems.map((item) => Budget.fromJson(item)).toList(),
      serverVersion: (json['server_version'] as num?)?.toInt() ?? sinceVersion,
    );
  }

  Future<List<FinanceTransaction>> pull(int sinceVersion) async =>
      (await pullChanges(sinceVersion)).transactions;

  Future<Map<String, Object?>> _requestMap(String method, String path,
          {Map<String, Object?>? body, bool includeAuth = true}) =>
      transport.requestMap(
        method,
        path,
        body: body,
        includeAuth: includeAuth,
      );

  List<Map<String, Object?>> _items(Map<String, Object?> json) {
    final values =
        (json['items'] ?? json['data'] ?? const <Object?>[]) as List<Object?>;
    return values
        .map((item) => (item! as Map).cast<String, Object?>())
        .toList();
  }
}

class PullResult {
  const PullResult(
      {required this.transactions,
      required this.accounts,
      this.categories = const [],
      this.budgets = const [],
      required this.serverVersion});

  final List<FinanceTransaction> transactions;
  final List<Account> accounts;
  final List<Category> categories;
  final List<Budget> budgets;
  final int serverVersion;
}
