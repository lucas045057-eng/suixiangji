import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:wealthmate_flutter/data/api_client.dart';
import 'package:wealthmate_flutter/data/finance_repository.dart';
import 'package:wealthmate_flutter/data/local_repository.dart';
import 'package:wealthmate_flutter/data/sync_queue.dart';
import 'package:wealthmate_flutter/domain/models.dart';
import 'package:wealthmate_flutter/state/finance_store.dart';

const serverAccountId = 'server-account-001';
const serverCategoryId = 'server-category-001';

const demoAccountIds = <String>{'cash', 'bank', 'alipay', 'wechat', 'credit'};
const demoCategoryIds = <String>{
  'food',
  'transport',
  'shopping',
  'home',
  'entertainment',
  'health',
  'salary',
  'other',
};
const demoTransactionIds = <String>{
  'tx-01',
  'tx-02',
  'tx-03',
  'tx-04',
  'tx-05',
  'tx-06',
  'tx-07',
  'tx-08',
  'tx-09',
  'tx-10',
  'tx-11',
  'tx-12',
};
const demoBudgetIds = <String>{
  'budget-food',
  'budget-transport',
  'budget-shopping',
  'budget-entertainment',
  'budget-home',
};

class MemoryKeyValueStore implements KeyValueStore {
  final Map<String, String> values = {};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;
}

class OnlineDemoDataClient extends http.BaseClient {
  OnlineDemoDataClient({this.failAgentDraft = false});

  final bool failAgentDraft;
  final List<Map<String, Object?>> pushBodies = [];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final path = request.url.path;
    if (path == '/sync/pull') {
      return _jsonResponse(
          200,
          {
            'items': const <Object?>[],
            'accounts': [
              {
                'id': serverAccountId,
                'name': '服务器正式账户',
                'type': 'asset',
                'account_kind': 'wechat',
                'currency': 'CNY',
                'opening_balance': 0,
                'server_version': 11,
              }
            ],
            'categories': [
              {
                'id': serverCategoryId,
                'name': '服务器正式分类',
                'type': 'expense',
                'active': true,
              }
            ],
            'budgets': const <Object?>[],
            'server_version': 42,
          },
          request);
    }

    if (path == '/agent/draft' && failAgentDraft) {
      return _jsonResponse(503, {'error': 'agent unavailable'}, request);
    }

    if (path == '/auth/me') {
      return _jsonResponse(
          200,
          {
            'id': 'online-demo-test-user',
            'username': 'online-demo-test-user',
            'display_name': '在线隔离测试用户',
            'quick_memories': const <Object?>[],
          },
          request);
    }

    if (path == '/sync/push') {
      final body = request is http.Request
          ? jsonDecode(request.body)
          : jsonDecode(await request.finalize().bytesToString());
      final decoded = (body as Map).cast<String, Object?>();
      pushBodies.add(decoded);
      final operations =
          ((decoded['operations'] as List<Object?>?) ?? const <Object?>[])
              .map((item) => (item! as Map).cast<String, Object?>())
              .toList();
      return _jsonResponse(
          200,
          {
            'accepted': operations
                .map((operation) => {
                      'client_op_id': operation['client_op_id'],
                      'entity_id': operation['entity_id'],
                      'server_version': 43,
                      'created': true,
                    })
                .toList(),
            'conflicts': const <Object?>[],
            'server_version': 43,
          },
          request);
    }

    return _jsonResponse(404, {'error': 'unexpected path: $path'}, request);
  }

  http.StreamedResponse _jsonResponse(
      int status, Map<String, Object?> body, http.BaseRequest request) {
    return http.StreamedResponse(
      Stream<List<int>>.value(utf8.encode(jsonEncode(body))),
      status,
      request: request,
      headers: const {'content-type': 'application/json'},
    );
  }
}

Future<FinanceStore> bootstrappedOnlineStore(
    OnlineDemoDataClient client, MemoryKeyValueStore storage) async {
  final repository = FinanceRepository(
    local: LocalRepository(storage),
    queue: SyncQueue(),
    api: ApiClient(
      baseUrl: 'http://online-demo.test',
      token: 'online-demo-token',
      client: client,
    ),
  );
  final store = FinanceStore(repository: repository);
  expect(store.isDemoMode, isFalse);
  expect(storage.values, isEmpty);

  await store.loadProfile();
  await store.sync();
  return store;
}

void main() {
  test('online full pull removes DemoData accounts from empty local state',
      () async {
    final client = OnlineDemoDataClient();
    final store = await bootstrappedOnlineStore(client, MemoryKeyValueStore());

    expect(
        store.state.accounts.map((item) => item.id), contains(serverAccountId));
    expect(
        store.state.accounts.where((item) => demoAccountIds.contains(item.id)),
        isEmpty);
  });

  test('online full pull removes DemoData categories from empty local state',
      () async {
    final store = await bootstrappedOnlineStore(
        OnlineDemoDataClient(), MemoryKeyValueStore());

    expect(store.state.categories.map((item) => item.id),
        contains(serverCategoryId));
    expect(
        store.state.categories
            .where((item) => demoCategoryIds.contains(item.id)),
        isEmpty);
  });

  test('online full pull with empty transactions leaves no DemoData entries',
      () async {
    final store = await bootstrappedOnlineStore(
        OnlineDemoDataClient(), MemoryKeyValueStore());

    expect(store.state.transactions, isEmpty);
    expect(
        store.state.transactions
            .where((item) => demoTransactionIds.contains(item.id)),
        isEmpty);
  });

  test('online full pull with empty budgets leaves no DemoData entries',
      () async {
    final store = await bootstrappedOnlineStore(
        OnlineDemoDataClient(), MemoryKeyValueStore());

    expect(store.state.budgets, isEmpty);
    expect(store.state.budgets.where((item) => demoBudgetIds.contains(item.id)),
        isEmpty);
  });

  test('new transaction after online bootstrap uses only server entity IDs',
      () async {
    final client = OnlineDemoDataClient();
    final store = await bootstrappedOnlineStore(client, MemoryKeyValueStore());

    // Mirrors TransactionForm's initial account/category selection after
    // bootstrap, then follows the production Store -> Queue path.
    final accountId = store.state.defaultAccountId ??
        store.state.accounts.firstOrNull?.id ??
        '';
    final categoryId = store.state.categories.firstOrNull?.id ?? '';
    expect(store.state.defaultAccountId, serverAccountId);
    await store.addTransaction(FinanceTransaction(
      id: 'online-bootstrap-tx-001',
      date: '2026-09-05',
      type: TransactionType.expense,
      amount: 1.23,
      accountId: accountId,
      categoryId: categoryId,
      note: '在线正式 ID 测试',
    ));

    final transaction = store.state.transactions
        .singleWhere((item) => item.id == 'online-bootstrap-tx-001');
    final operation = store.repository.queue.pending().single;
    final transactionPayload = operation.payload;

    expect({
      'transaction.account_id': transaction.accountId,
      'transaction.category_id': transaction.categoryId,
      'payload.account_id': transactionPayload['account_id'],
      'payload.category_id': transactionPayload['category_id'],
    }, {
      'transaction.account_id': serverAccountId,
      'transaction.category_id': serverCategoryId,
      'payload.account_id': serverAccountId,
      'payload.category_id': serverCategoryId,
    });
  });

  test('offline demo mode explicitly keeps DemoData available', () async {
    final repository = FinanceRepository(
      local: LocalRepository(MemoryKeyValueStore()),
      queue: SyncQueue(),
    );
    final store = FinanceStore(repository: repository);

    expect(store.isDemoMode, isTrue);
    await store.load();

    expect(store.state.accounts.map((item) => item.id), contains('alipay'));
    expect(store.state.categories.map((item) => item.id), contains('food'));
    expect(store.state.transactions.map((item) => item.id), contains('tx-01'));
    expect(store.state.budgets.map((item) => item.id), contains('budget-food'));
  });
}
