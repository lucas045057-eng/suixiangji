import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:wealthmate_flutter/data/api_client.dart';
import 'package:wealthmate_flutter/data/finance_repository.dart';
import 'package:wealthmate_flutter/data/local_repository.dart';
import 'package:wealthmate_flutter/data/sync_queue.dart';
import 'package:wealthmate_flutter/domain/models.dart';
import 'package:wealthmate_flutter/state/finance_store.dart';

class PendingEditMemory implements KeyValueStore {
  final Map<String, String> values = {};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;
}

class AcceptAllPushClient extends http.BaseClient {
  int serverVersion = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request.url.path == '/sync/push') {
      final decoded = request is http.Request
          ? jsonDecode(request.body) as Map
          : jsonDecode(await request.finalize().bytesToString()) as Map;
      final operations = ((decoded['operations'] as List?) ?? const [])
          .map((item) => (item as Map).cast<String, Object?>())
          .toList();
      final accepted = operations.map((operation) {
        serverVersion += 1;
        return {
          'client_op_id': operation['client_op_id'],
          'entity_id': operation['entity_id'],
          'server_version': serverVersion,
          'created': true,
        };
      }).toList();
      return _response(
          request,
          200,
          {
            'accepted': accepted,
            'conflicts': const <Object?>[],
            'server_version': serverVersion,
          });
    }

    if (request.url.path == '/sync/pull') {
      return _response(
          request,
          200,
          {
            'items': const <Object?>[],
            'transactions': const <Object?>[],
            'accounts': const <Object?>[],
            'categories': const <Object?>[],
            'budgets': const <Object?>[],
            'server_version': serverVersion,
          });
    }

    return _response(request, 404, {'error': 'unexpected path'});
  }

  http.StreamedResponse _response(
      http.BaseRequest request, int status, Map<String, Object?> body) {
    return http.StreamedResponse(
      Stream<List<int>>.value(utf8.encode(jsonEncode(body))),
      status,
      request: request,
      headers: const {'content-type': 'application/json'},
    );
  }
}

FinanceTransaction pendingTransaction({
  double amount = 8.09,
  String note = 'before-edit',
  String accountId = 'account-a',
  String categoryId = 'category-a',
}) {
  return FinanceTransaction(
    id: 'pending-edit-tx',
    date: '2026-09-05',
    type: TransactionType.expense,
    amount: amount,
    categoryId: categoryId,
    accountId: accountId,
    note: note,
    clientOpId: 'pending-edit-op',
  );
}

FinanceStore pendingEditStore({ApiClient? api}) {
  return FinanceStore(
    repository: FinanceRepository(
      local: LocalRepository(PendingEditMemory()),
      queue: SyncQueue(),
      api: api,
    ),
    initialState: const FinanceState(
      currentMonth: '2026-09',
      accounts: [
        Account(id: 'account-a', name: '账户 A', type: AccountType.asset),
        Account(id: 'account-b', name: '账户 B', type: AccountType.asset),
      ],
      categories: [
        Category(id: 'category-a', name: '分类 A'),
        Category(id: 'category-b', name: '分类 B'),
      ],
    ),
  );
}

SyncOperation onlyPendingTransactionOperation(FinanceStore store) {
  final operations = store.repository.queue
      .pending()
      .where((item) => item.entityId == 'pending-edit-tx')
      .toList();
  expect(operations, hasLength(1));
  return operations.single;
}

void main() {
  test('editing a pending transaction updates the queued create payload',
      () async {
    final store = pendingEditStore();

    await store.addTransaction(pendingTransaction());
    await store.updateTransaction(
        pendingTransaction(amount: 8.90, note: 'after-edit'));

    final operation = onlyPendingTransactionOperation(store);
    expect(store.state.transactions.single.amount, 8.90);
    expect(operation.type, SyncOperationType.upsert);
    expect(operation.clientOpId, 'pending-edit-op');
    expect(operation.payload['amount'], 8.90);
  });

  test('editing a pending transaction updates the queued note payload',
      () async {
    final store = pendingEditStore();

    await store.addTransaction(pendingTransaction());
    await store.updateTransaction(
        pendingTransaction(amount: 8.90, note: 'after-edit'));

    final operation = onlyPendingTransactionOperation(store);
    expect(store.state.transactions.single.note, 'after-edit');
    expect(operation.payload['note'], 'after-edit');
  });

  test('editing a pending transaction updates queued account and category IDs',
      () async {
    final store = pendingEditStore();

    await store.addTransaction(pendingTransaction());
    await store.updateTransaction(pendingTransaction(
      accountId: 'account-b',
      categoryId: 'category-b',
    ));

    final operation = onlyPendingTransactionOperation(store);
    expect(store.state.transactions.single.accountId, 'account-b');
    expect(store.state.transactions.single.categoryId, 'category-b');
    expect(operation.payload['account_id'], 'account-b');
    expect(operation.payload['category_id'], 'category-b');
  });

  test('editing a synced transaction queues its current update payload',
      () async {
    final client = AcceptAllPushClient();
    final store = pendingEditStore(
      api: ApiClient(
        baseUrl: 'http://queue-consistency.test',
        token: 'queue-consistency-token',
        client: client,
      ),
    );
    await store.repository.ensureLocalOwner('queue-consistency-user');

    await store.addTransaction(pendingTransaction());
    await store.sync();
    expect(store.repository.queue.pending(), isEmpty);

    await store.updateTransaction(
        pendingTransaction(amount: 8.90, note: 'after-sync-edit'));

    final operation = onlyPendingTransactionOperation(store);
    expect(operation.payload['amount'], 8.90);
    expect(operation.payload['note'], 'after-sync-edit');
  });

  test('multiple pending edits leave the latest effective payload', () async {
    final store = pendingEditStore();

    await store.addTransaction(pendingTransaction());
    await store.updateTransaction(pendingTransaction(amount: 8.50));
    await store.updateTransaction(
        pendingTransaction(amount: 8.90, note: 'final-edit'));

    final operation = onlyPendingTransactionOperation(store);
    expect(store.state.transactions.single.amount, 8.90);
    expect(store.state.transactions.single.note, 'final-edit');
    expect(operation.payload['amount'], 8.90);
    expect(operation.payload['note'], 'final-edit');
  });
}
