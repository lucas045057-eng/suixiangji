import 'package:flutter_test/flutter_test.dart';
import 'package:wealthmate_flutter/data/api_client.dart';
import 'package:wealthmate_flutter/data/sync_queue.dart';
import 'package:wealthmate_flutter/data/token_store.dart';

class IntegrationTokenStore implements TokenStore {
  String? value;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String token) async => value = token;

  @override
  Future<void> clear() async => value = null;
}

void main() {
  test('Flutter API Client completes the real PostgreSQL API contract',
      () async {
    const baseUrl = String.fromEnvironment('WEALTHMATE_INTEGRATION_BASE_URL');
    const username = String.fromEnvironment('WEALTHMATE_INTEGRATION_USERNAME');
    const password = String.fromEnvironment('WEALTHMATE_INTEGRATION_PASSWORD');
    const accountId = String.fromEnvironment('WEALTHMATE_INTEGRATION_ACCOUNT_ID');
    const categoryId =
        String.fromEnvironment('WEALTHMATE_INTEGRATION_CATEGORY_ID');
    expect(baseUrl, isNotEmpty);
    expect(username, isNotEmpty);
    expect(password, isNotEmpty);
    expect(accountId, isNotEmpty);
    expect(categoryId, isNotEmpty);

    final api = ApiClient(
      baseUrl: baseUrl,
      tokenStore: IntegrationTokenStore(),
    );
    final login = await api.login(username, password);
    expect(login['username'], username);
    expect(api.token, isNotEmpty);

    final profile = await api.fetchProfile();
    expect(profile.username, username);
    expect((await api.fetchAccounts()).any((item) => item.id == accountId),
        isTrue);
    expect((await api.fetchCategories()).any((item) => item.id == categoryId),
        isTrue);
    expect((await api.fetchTransactions()), isNotEmpty);
    expect((await api.fetchBudgets(month: '2026-09')), isNotEmpty);

    final suffix = DateTime.now().microsecondsSinceEpoch;
    final transactionId = 'flutter-api-integration-$suffix';
    final operation = SyncOperation(
      clientOpId: 'flutter-api-integration-op-$suffix',
      entity: 'transactions',
      entityId: transactionId,
      type: SyncOperationType.upsert,
      payload: {
        'id': transactionId,
        'type': 'expense',
        'amount': 3.33,
        'currency': 'CNY',
        'account_id': accountId,
        'category_id': categoryId,
        'date': '2026-09-04',
        'occurred_on': '2026-09-04',
        'note': 'FLUTTER-API-INTEGRATION',
        'client_op_id': 'flutter-api-integration-op-$suffix',
      },
    );
    final pushed = await api.push([operation]);
    final accepted = (pushed['accepted'] as List<Object?>).single as Map;
    expect(accepted['client_op_id'], operation.clientOpId);
    expect(accepted['server_version'], isNotNull);

    final pulled = await api.pullChanges(0);
    final row = pulled.transactions.firstWhere((item) => item.id == transactionId);
    expect(row.amount, 3.33);
    expect(row.note, 'FLUTTER-API-INTEGRATION');
    expect(row.serverVersion, accepted['server_version']);
  });
}
