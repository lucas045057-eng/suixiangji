import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:wealthmate_flutter/data/api_client.dart';
import 'package:wealthmate_flutter/data/finance_repository.dart';
import 'package:wealthmate_flutter/data/local_repository.dart';
import 'package:wealthmate_flutter/data/sync_queue.dart';
import 'package:wealthmate_flutter/domain/models.dart';
import 'package:wealthmate_flutter/state/finance_store.dart';

const _userId = 'cb01-user-a';
const _transactionId = 'cb01-transaction';
const _conflictOpId = 'android-edit-A';
const _acceptedOpId = 'accepted-op-A';
const _unrelatedOpId = 'unrelated-op-C';

class Cb01MemoryStore implements KeyValueStore {
  final Map<String, String> values = {};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;
}

class ConflictRecoveryClient extends http.BaseClient {
  ConflictRecoveryClient({
    this.failRecoveryPull = false,
    this.includeAcceptedOperation = false,
  });

  final bool failRecoveryPull;
  final bool includeAcceptedOperation;
  final List<String> pushedClientOpIds = [];
  final List<int> requestedSinceVersions = [];
  int pushRequestCount = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request.url.path == '/sync/push') {
      pushRequestCount++;
      final decoded = jsonDecode((request as http.Request).body) as Map;
      final operations = ((decoded['operations'] as List?) ?? const [])
          .map((item) => (item as Map).cast<String, Object?>())
          .toList();
      pushedClientOpIds.addAll(
          operations.map((item) => item['client_op_id']! as String).toList());
      final accepted = includeAcceptedOperation
          ? [
              {
                'client_op_id': _acceptedOpId,
                'entity_id': 'cb01-accepted-transaction',
                'server_version': 15,
              }
            ]
          : const <Object?>[];
      return _response(request, {
        'accepted': accepted,
        'conflicts': [
          {
            'client_op_id': _conflictOpId,
            'entity_id': _transactionId,
            'reason': 'server has a newer version',
          }
        ],
        'server_version': 15,
      });
    }

    if (request.url.path == '/sync/pull') {
      final since = int.parse(request.url.queryParameters['since_version']!);
      requestedSinceVersions.add(since);
      if (failRecoveryPull) {
        throw StateError('recovery pull unavailable');
      }
      final items = since <= 14
          ? [
              {
                'id': _transactionId,
                'date': '2026-09-06',
                'type': 'expense',
                'amount': 42.42,
                'currency': 'CNY',
                'account_id': 'windows-account',
                'category_id': 'windows-category',
                'note': 'CB01-WINDOWS-FIRST-COMMIT',
                'client_op_id': 'windows-op-001',
                'server_version': 15,
                'deleted_at': null,
              }
            ]
          : const <Object?>[];
      return _response(request, {
        'items': items,
        'accounts': const <Object?>[],
        'categories': const <Object?>[],
        'budgets': const <Object?>[],
        'server_version': 15,
      });
    }

    return _response(request, {'detail': 'unexpected path'}, status: 404);
  }

  http.StreamedResponse _response(
      http.BaseRequest request, Map<String, Object?> body,
      {int status = 200}) {
    return http.StreamedResponse(
      Stream<List<int>>.value(utf8.encode(jsonEncode(body))),
      status,
      request: request,
      headers: const {'content-type': 'application/json'},
    );
  }
}

FinanceTransaction _staleTransaction({
  String id = _transactionId,
  String clientOpId = _conflictOpId,
  double amount = 41.41,
  String note = 'CB01-ANDROID-STALE-EDIT',
}) {
  return FinanceTransaction(
    id: id,
    date: '2026-09-06',
    type: TransactionType.expense,
    amount: amount,
    currency: 'CNY',
    accountId: 'android-account',
    categoryId: 'android-category',
    note: note,
    clientOpId: clientOpId,
    serverVersion: 14,
  );
}

SyncOperation _operation(FinanceTransaction transaction) => SyncOperation(
      clientOpId: transaction.clientOpId,
      entity: 'transactions',
      entityId: transaction.id,
      type: SyncOperationType.upsert,
      payload: transaction.toJson(),
    );

Future<FinanceStore> _store(
  ConflictRecoveryClient client, {
  int cursor = 14,
  List<FinanceTransaction> transactions = const [],
  List<SyncOperation> operations = const [],
}) async {
  final repository = FinanceRepository(
    local: LocalRepository(Cb01MemoryStore()),
    queue: SyncQueue(),
    api: ApiClient(
      baseUrl: 'http://cb01.test',
      token: 'cb01-token',
      client: client,
    ),
  );
  await repository.ensureLocalOwner(_userId);
  repository.queue.replace(operations);
  return FinanceStore(
    repository: repository,
    initialState: FinanceState(
      currentMonth: '2026-09',
      transactions: transactions,
      syncState: SyncState(serverVersion: cursor),
    ),
  );
}

Future<void> syncOnce(FinanceStore store) async {
  await store.repository.ensureLocalOwner(_userId);
  await store.sync();
}

void main() {
  test('RED-01 conflict operation must not retry forever', () async {
    final transaction = _staleTransaction();
    final client = ConflictRecoveryClient();
    final store = await _store(client,
        transactions: [transaction], operations: [_operation(transaction)]);

    await syncOnce(store);

    expect(store.repository.queue.pending(), isEmpty);
    await syncOnce(store);
    expect(client.pushedClientOpIds, [_conflictOpId]);
  });

  test('RED-02 conflict recovery pulls from the conflict base version',
      () async {
    final transaction = _staleTransaction();
    final client = ConflictRecoveryClient();
    final store = await _store(client,
        transactions: [transaction], operations: [_operation(transaction)]);

    await syncOnce(store);

    expect(client.requestedSinceVersions, [14]);
  });

  test('RED-03 poisoned cursor recovers the authoritative transaction',
      () async {
    final transaction = _staleTransaction();
    final client = ConflictRecoveryClient();
    final store = await _store(client,
        cursor: 15,
        transactions: [transaction],
        operations: [_operation(transaction)]);

    await syncOnce(store);

    expect(store.state.transactions.single.amount, 42.42);
    expect(store.state.transactions.single.note, 'CB01-WINDOWS-FIRST-COMMIT');
    expect(store.state.transactions.single.serverVersion, 15);
    expect(store.state.syncState.serverVersion, 15);
    expect(store.repository.queue.pending(), isEmpty);
  });

  test('RED-04 authoritative server state wins over local stale state',
      () async {
    final transaction = _staleTransaction();
    final client = ConflictRecoveryClient();
    final store = await _store(client,
        transactions: [transaction], operations: [_operation(transaction)]);

    await syncOnce(store);

    expect(store.state.transactions.single.amount, isNot(41.41));
    expect(
        store.state.transactions.single.note, isNot('CB01-ANDROID-STALE-EDIT'));
  });

  test('RED-05 recovery pull failure keeps conflict operation pending',
      () async {
    final transaction = _staleTransaction();
    final client = ConflictRecoveryClient(failRecoveryPull: true);
    final store = await _store(client,
        transactions: [transaction], operations: [_operation(transaction)]);

    await syncOnce(store);

    expect(client.requestedSinceVersions, [14]);
    expect(store.repository.queue.pending().map((item) => item.clientOpId),
        [_conflictOpId]);
  });

  test('RED-06 mixed accepted and conflict operations stay isolated', () async {
    final conflict = _staleTransaction();
    final accepted = _staleTransaction(
        id: 'cb01-accepted-transaction', clientOpId: _acceptedOpId);
    final unrelated = _staleTransaction(
        id: 'cb01-unrelated-transaction', clientOpId: _unrelatedOpId);
    final client = ConflictRecoveryClient(includeAcceptedOperation: true);
    final store = await _store(client, transactions: [
      conflict,
      accepted,
      unrelated
    ], operations: [
      _operation(accepted),
      _operation(conflict),
      _operation(unrelated)
    ]);

    await syncOnce(store);

    expect(store.repository.queue.pending().map((item) => item.clientOpId),
        [_unrelatedOpId]);
  });

  test('RED-07 recovery failure preserves the original operation identity',
      () async {
    final transaction = _staleTransaction();
    final client = ConflictRecoveryClient(failRecoveryPull: true);
    final store = await _store(client,
        transactions: [transaction], operations: [_operation(transaction)]);

    await syncOnce(store);
    await syncOnce(store);

    expect(client.pushedClientOpIds, [_conflictOpId, _conflictOpId]);
    expect(store.repository.queue.pending().single.clientOpId, _conflictOpId);
  });

  test('RED-08 recovery query may look back without regressing the cursor',
      () async {
    final transaction = _staleTransaction();
    final client = ConflictRecoveryClient();
    final store = await _store(client,
        cursor: 15,
        transactions: [transaction],
        operations: [_operation(transaction)]);

    await syncOnce(store);

    expect(client.requestedSinceVersions, [14]);
    expect(store.state.syncState.serverVersion, 15);
  });

  test('RED-09 conflict recovery never falls back to since_version zero',
      () async {
    final transaction = _staleTransaction();
    final client = ConflictRecoveryClient();
    final store = await _store(client,
        transactions: [transaction], operations: [_operation(transaction)]);

    await syncOnce(store);

    expect(client.requestedSinceVersions, isNot(contains(0)));
  });
}
