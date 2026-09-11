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

  void _requireSession(int generation, [String? requestToken]) {
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
    _requireSession(generation);
    if (token == null || token!.isEmpty) {
      if (restored == null || restored.isEmpty) return false;
      token = restored;
    }
    final verified = await tokenStore.readLastVerifiedUserId();
    _requireSession(generation);
    lastVerifiedUserId = token == restored ? verified : null;
    return true;
  }

  void beginSession() {
    _sessionGeneration++;
  }

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
          // Remove the old identity before making the replacement token
          // durable. A partial token write therefore cannot retain A's
          // verified partition marker.
          if (newSession) await tokenStore.clearLastVerifiedUserId();
          await tokenStore.write(value);
        } catch (_) {
          await _failClosedCredentials(generation);
          rethrow;
        }
      });
      _requireSession(generation);
      token = value;
    } catch (error) {
      await _persistCredentials(() => _failClosedCredentials(generation));
      if (error is ApiFailure) rethrow;
      throw const ApiFailure(ApiFailureKind.network, '登录状态保存失败，请重试');
    }
  }

  Future<void> logout() async {
    _sessionGeneration++;
    token = null;
    lastVerifiedUserId = null;
    await _persistCredentials(_clearPersistedCredentialsBestEffort);
  }

  Future<void> saveLastVerifiedUserId(String userId) async {
    final normalizedUserId = userId.trim();
    if (normalizedUserId.isEmpty) return;
    final generation = _sessionGeneration;
    final verifiedToken = token;
    try {
      await _persistCredentials(() async {
        _requireSession(generation, verifiedToken);
        try {
          await tokenStore.writeLastVerifiedUserId(normalizedUserId);
        } catch (_) {
          await _failClosedCredentials(generation, verifiedToken);
          rethrow;
        }
      });
      _requireSession(generation, verifiedToken);
      lastVerifiedUserId = normalizedUserId;
    } catch (error) {
      await _persistCredentials(
          () => _failClosedCredentials(generation, verifiedToken));
      if (error is ApiFailure) rethrow;
      throw const ApiFailure(ApiFailureKind.network, '登录状态保存失败，请重试');
    }
  }

  Future<Map<String, Object?>> login(String username, String password) async {
    final generation = ++_sessionGeneration;
    final result = await _requestMap('POST', '/auth/login',
        body: {'username': username, 'password': password}, includeAuth: false);
    _requireSession(generation);
    final accessToken =
        result['access_token'] as String? ?? result['token'] as String?;
    if (accessToken == null || accessToken.isEmpty) {
      throw const ApiFailure(ApiFailureKind.server, '登录响应中没有访问令牌');
    }
    await saveToken(accessToken);
    return result;
  }

  Future<UserProfile> fetchProfile() async {
    final generation = _sessionGeneration;
    final json = await _requestMap('GET', '/auth/me');
    _requireSession(generation);
    final profile = UserProfile.fromJson(json);
    if (profile.id.trim().isEmpty) {
      throw const ApiFailure(ApiFailureKind.server, '无法确认账户身份，请重新登录');
    }
    await saveLastVerifiedUserId(profile.id);
    _requireSession(generation);
    return profile;
  }

  Future<Map<String, Object?>> register(
      {required String username,
      required String password,
      String? displayName,
      required String inviteCode}) async {
    final generation = ++_sessionGeneration;
    final result =
        await _requestMap('POST', '/auth/register', includeAuth: false, body: {
      'username': username.trim(),
      'password': password,
      if (displayName != null && displayName.trim().isNotEmpty)
        'display_name': displayName.trim(),
      'invite_code': inviteCode.trim(),
    });
    _requireSession(generation);
    final accessToken = result['access_token'] as String?;
    if (accessToken == null || accessToken.isEmpty) {
      throw const ApiFailure(ApiFailureKind.server, '注册响应异常，请尝试登录');
    }
    await saveToken(accessToken);
    return result;
  }

  Future<void> deleteAccount(String currentPassword) async {
    final result = await _requestMap('DELETE', '/auth/me',
        body: {'current_password': currentPassword},
        allowStaleSuccess: true);
    if (result['deleted'] != true) {
      throw const ApiFailure(ApiFailureKind.server, '未能确认删除结果，请稍后重试');
    }
  }

  Future<UserProfile> updateProfile(
      {String? displayName,
      String? username,
      List<QuickMemory>? quickMemories}) async {
    final generation = _sessionGeneration;
    final json = await _requestMap('PATCH', '/auth/me', body: {
      if (displayName != null) 'display_name': displayName,
      if (username != null) 'username': username,
      if (quickMemories != null)
        'quick_memories': quickMemories.map((item) => item.toJson()).toList(),
    });
    final accessToken = json['access_token'] as String?;
    if (accessToken != null && accessToken.isNotEmpty) {
      await saveToken(accessToken, newSession: false);
    }
    _requireSession(generation);
    return UserProfile.fromJson(json);
  }

  Future<UserProfile> changePassword(
      String currentPassword, String newPassword) async {
    final generation = _sessionGeneration;
    final json = await _requestMap('POST', '/auth/password', body: {
      'current_password': currentPassword,
      'new_password': newPassword,
    });
    final accessToken = json['access_token'] as String?;
    if (accessToken != null && accessToken.isNotEmpty) {
      await saveToken(accessToken, newSession: false);
    }
    _requireSession(generation);
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
      {Map<String, Object?>? body,
      bool includeAuth = true,
      bool allowStaleSuccess = false}) async {
    final generation = _sessionGeneration;
    final requestToken = includeAuth ? token : null;
    final result = await transport.requestMap(
      method,
      path,
      body: body,
      includeAuth: includeAuth,
    );
    if (!allowStaleSuccess) _requireSession(generation, requestToken);
    return result;
  }

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
