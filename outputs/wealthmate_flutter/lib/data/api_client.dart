import 'dart:convert';

import 'package:http/http.dart' as http;

import '../domain/models.dart';
import 'sync_queue.dart';

enum ApiFailureKind {
  configuration,
  unauthorized,
  conflict,
  validation,
  network,
  server
}

class ApiFailure implements Exception {
  const ApiFailure(this.kind, this.message);

  final ApiFailureKind kind;
  final String message;

  @override
  String toString() => message;
}

class ApiClient {
  ApiClient({required this.baseUrl, this.token, http.Client? client})
      : client = client ?? http.Client();

  final String? baseUrl;
  String? token;
  final http.Client client;

  Future<Map<String, Object?>> login(String username, String password) async {
    return _requestMap('POST', '/auth/login',
        body: {'username': username, 'password': password}, includeAuth: false);
  }

  Future<UserProfile> fetchProfile() async {
    final json = await _requestMap('GET', '/auth/me');
    return UserProfile.fromJson(json);
  }

  Future<UserProfile> updateProfile(
      {String? displayName,
      String? username,
      List<QuickMemory>? quickMemories}) async {
    final json = await _requestMap('PATCH', '/auth/me', body: {
      if (displayName != null) 'display_name': displayName,
      if (username != null) 'username': username,
      if (quickMemories != null)
        'quick_memories':
            quickMemories.map((item) => item.toJson()).toList(),
    });
    final accessToken = json['access_token'] as String?;
    if (accessToken != null && accessToken.isNotEmpty) token = accessToken;
    return UserProfile.fromJson(json);
  }

  Future<UserProfile> changePassword(
      String currentPassword, String newPassword) async {
    final json = await _requestMap('POST', '/auth/password', body: {
      'current_password': currentPassword,
      'new_password': newPassword,
    });
    final accessToken = json['access_token'] as String?;
    if (accessToken != null && accessToken.isNotEmpty) token = accessToken;
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
      {Map<String, Object?>? body, bool includeAuth = true}) async {
    final root = baseUrl?.trim();
    if (root == null || root.isEmpty)
      throw const ApiFailure(ApiFailureKind.configuration, '同步服务尚未配置');
    final uri = Uri.parse(root.endsWith('/')
        ? '${root.substring(0, root.length - 1)}$path'
        : '$root$path');
    final headers = <String, String>{'content-type': 'application/json'};
    if (includeAuth && token != null && token!.isNotEmpty)
      headers['authorization'] = 'Bearer $token';
    try {
      final response = switch (method) {
        'POST' => await client.post(uri,
            headers: headers, body: jsonEncode(body ?? const {})),
        'PATCH' => await client.patch(uri,
            headers: headers, body: jsonEncode(body ?? const {})),
        'DELETE' => await client.delete(uri, headers: headers),
        _ => await client.get(uri, headers: headers),
      };
      if (response.statusCode < 200 || response.statusCode >= 300)
        throw _failureForStatus(response.statusCode);
      final decoded = jsonDecode(response.body);
      return (decoded as Map).cast<String, Object?>();
    } on ApiFailure {
      rethrow;
    } on FormatException {
      throw const ApiFailure(ApiFailureKind.server, '同步服务返回了无法识别的数据');
    } catch (_) {
      throw const ApiFailure(ApiFailureKind.network, '暂时无法连接同步服务');
    }
  }

  ApiFailure _failureForStatus(int statusCode) {
    if (statusCode == 401)
      return const ApiFailure(ApiFailureKind.unauthorized, '登录已失效，请重新登录');
    if (statusCode == 409)
      return const ApiFailure(ApiFailureKind.conflict, '数据存在冲突，请在本机确认');
    if (statusCode == 422)
      return const ApiFailure(ApiFailureKind.validation, '提交的数据需要修正');
    return const ApiFailure(ApiFailureKind.server, '同步服务暂时不可用');
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
