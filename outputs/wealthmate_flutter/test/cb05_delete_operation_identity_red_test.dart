import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:wealthmate_flutter/data/api_client.dart';
import 'package:wealthmate_flutter/data/finance_repository.dart';
import 'package:wealthmate_flutter/data/local_repository.dart';
import 'package:wealthmate_flutter/data/sync_queue.dart';
import 'package:wealthmate_flutter/domain/models.dart';
import 'package:wealthmate_flutter/state/finance_store.dart';

class Cb05Memory implements KeyValueStore {
  final Map<String, String> values = {};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;
}

class Cb05PushClient extends http.BaseClient {
  final List<List<Map<String, Object?>>> pushes = [];
  bool failNextPush = false;
  int serverVersion = 21;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request.url.path == '/sync/push') {
      final body = request is http.Request
          ? request.body
          : await request.finalize().bytesToString();
      final decoded = jsonDecode(body) as Map;
      final operations = ((decoded['operations'] as List?) ?? const [])
          .map((item) => (item as Map).cast<String, Object?>())
          .toList();
      pushes.add(operations);
      if (failNextPush) {
        failNextPush = false;
        return _response(request, 503, {'detail': 'temporary outage'});
      }
      final accepted = operations.map((operation) {
        serverVersion += 1;
        return <String, Object?>{
          'client_op_id': operation['client_op_id'],
          'entity_id': operation['entity_id'],
          'server_version': serverVersion,
          'created': true,
        };
      }).toList();
      return _response(request, 200, {
        'accepted': accepted,
        'conflicts': const <Object?>[],
        'server_version': serverVersion,
      });
    }
    if (request.url.path == '/sync/pull') {
      return _response(request, 200, {
        'items': const <Object?>[],
        'accounts': const <Object?>[],
        'categories': const <Object?>[],
        'budgets': const <Object?>[],
        'server_version': serverVersion,
      });
    }
    return _response(request, 404, {'detail': 'unexpected path'});
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

class Cb05ConflictServer extends http.BaseClient {
  int serverVersion = 21;
  final Set<String> seenOperationIds = <String>{};

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request.url.path != '/sync/push') {
      return http.StreamedResponse(Stream<List<int>>.value(const []), 404,
          request: request);
    }
    final body = request is http.Request
        ? request.body
        : await request.finalize().bytesToString();
    final decoded = jsonDecode(body) as Map;
    final operations = ((decoded['operations'] as List?) ?? const [])
        .map((item) => (item as Map).cast<String, Object?>())
        .toList();
    final accepted = <Map<String, Object?>>[];
    final conflicts = <Map<String, Object?>>[];
    for (final operation in operations) {
      final clientOpId = operation['client_op_id']! as String;
      if (seenOperationIds.contains(clientOpId)) {
        accepted.add({
          'client_op_id': clientOpId,
          'entity_id': operation['entity_id'],
          'server_version': serverVersion,
          'created': false,
        });
        continue;
      }
      final payload = (operation['payload'] as Map).cast<String, Object?>();
      final baseVersion = (payload['server_version'] as num?)?.toInt() ?? 0;
      if (baseVersion < serverVersion) {
        conflicts.add({
          'client_op_id': clientOpId,
          'entity_id': operation['entity_id'],
          'reason': 'server has a newer version',
        });
        continue;
      }
      seenOperationIds.add(clientOpId);
      serverVersion += 1;
      accepted.add({
        'client_op_id': clientOpId,
        'entity_id': operation['entity_id'],
        'server_version': serverVersion,
        'created': true,
      });
    }
    return http.StreamedResponse(
      Stream<List<int>>.value(utf8.encode(jsonEncode({
        'accepted': accepted,
        'conflicts': conflicts,
        'server_version': serverVersion,
      }))),
      200,
      request: request,
      headers: const {'content-type': 'application/json'},
    );
  }
}

const cb05Transaction = FinanceTransaction(
  id: 'tx-X',
  date: '2026-09-05',
  type: TransactionType.expense,
  amount: 81.81,
  categoryId: 'cb05-category',
  accountId: 'cb05-account',
  note: 'CB05 baseline',
  clientOpId: 'edit-shared',
  serverVersion: 21,
);

FinanceStore cb05Store({
  Cb05Memory? memory,
  ApiClient? api,
  FinanceTransaction transaction = cb05Transaction,
}) {
  return FinanceStore(
    repository: FinanceRepository(
      local: LocalRepository(memory ?? Cb05Memory()),
      queue: SyncQueue(),
      api: api,
    ),
    initialState: FinanceState(
      currentMonth: '2026-09',
      accounts: const [
        Account(id: 'cb05-account', name: 'CB05 account', type: AccountType.asset),
      ],
      categories: const [Category(id: 'cb05-category', name: 'CB05 category')],
      transactions: [transaction],
      syncState: const SyncState(serverVersion: 21),
    ),
  );
}

Future<SyncOperation> deleteFrom(FinanceStore store) async {
  await store.deleteTransaction('tx-X');
  return store.repository.queue.pending().single;
}

void main() {
  test('RED-01 two clients deleting one entity get different operation IDs',
      () async {
    final androidOperation = await deleteFrom(cb05Store());
    final windowsOperation = await deleteFrom(cb05Store());

    expect(androidOperation.entityId, 'tx-X');
    expect(windowsOperation.entityId, 'tx-X');
    expect(androidOperation.clientOpId, isNot(windowsOperation.clientOpId));
  });

  test('RED-02 delete identity is not derived from the previous entity op',
      () async {
    final operation = await deleteFrom(cb05Store());

    expect(operation.clientOpId, isNot('edit-shared'));
    expect(operation.clientOpId, isNot('edit-shared:delete'));
  });

  test('RED-03 retry keeps the same pending delete operation ID', () async {
    final memory = Cb05Memory();
    final client = Cb05PushClient();
    final store = cb05Store(
      memory: memory,
      api: ApiClient(baseUrl: 'http://cb05.test', token: 'cb05-token', client: client),
    );
    await store.repository.ensureLocalOwner('cb05-user');
    final operation = await deleteFrom(store);

    client.failNextPush = true;
    await store.sync();
    expect(store.repository.queue.pending(), hasLength(1));
    await store.sync();

    expect(client.pushes, hasLength(2));
    expect(client.pushes[0].single['client_op_id'], operation.clientOpId);
    expect(client.pushes[1].single['client_op_id'], operation.clientOpId);
    expect(store.repository.queue.pending(), isEmpty);
  });

  test('RED-04 restart keeps the same pending delete operation ID', () async {
    final memory = Cb05Memory();
    final firstStore = cb05Store(memory: memory);
    await firstStore.repository.ensureLocalOwner('cb05-user');
    final operation = await deleteFrom(firstStore);

    final restartedRepository = FinanceRepository(
      local: LocalRepository(memory),
      queue: SyncQueue(),
    );
    final restartedStore = FinanceStore(repository: restartedRepository);
    await restartedRepository.ensureLocalOwner('cb05-user');
    await restartedStore.load();

    expect(restartedStore.repository.queue.pending(), hasLength(1));
    expect(restartedStore.repository.queue.pending().single.clientOpId,
        operation.clientOpId);
  });

  test('RED-05 one persisted delete remains one queued mutation', () async {
    final memory = Cb05Memory();
    final store = cb05Store(memory: memory);
    final operation = await deleteFrom(store);

    final reloadedQueue = await store.repository.local.loadQueue();
    store.repository.queue.replace(reloadedQueue);
    store.repository.queue.enqueue(operation);

    expect(store.repository.queue.pending(), hasLength(1));
    expect(store.repository.queue.pending().single.clientOpId,
        operation.clientOpId);
  });

  test('RED-06 delete after edit uses an independent operation identity',
      () async {
    final store = cb05Store();
    final createOp = cb05Transaction.clientOpId;
    const edited = FinanceTransaction(
      id: 'tx-X',
      date: '2026-09-05',
      type: TransactionType.expense,
      amount: 82.82,
      categoryId: 'cb05-category',
      accountId: 'cb05-account',
      note: 'edited',
      clientOpId: 'edit-001',
      serverVersion: 21,
    );
    await store.updateTransaction(edited);
    final editOp = store.repository.queue.pending().single.clientOpId;
    final deleteOp = (await deleteFrom(store)).clientOpId;

    expect(createOp, isNot(editOp));
    expect(editOp, isNot(deleteOp));
    expect(deleteOp, isNot('$editOp:delete'));
  });

  test('RED-07 same queued delete retry remains backend-idempotent', () async {
    final client = Cb05PushClient();
    final api = ApiClient(
      baseUrl: 'http://cb05.test',
      token: 'cb05-token',
      client: client,
    );
    final operation = await deleteFrom(cb05Store()).then((item) => item);

    final first = await api.push([operation]);
    final second = await api.push([operation]);

    expect(first['accepted'], hasLength(1));
    expect(second['accepted'], hasLength(1));
    expect(client.pushes[0].single['client_op_id'], operation.clientOpId);
    expect(client.pushes[1].single['client_op_id'], operation.clientOpId);
  });

  test('RED-08 same-base concurrent deletes produce a stale conflict',
      () async {
    final androidOperation = await deleteFrom(cb05Store());
    final windowsOperation = await deleteFrom(cb05Store());
    expect(androidOperation.clientOpId, isNot(windowsOperation.clientOpId));

    final server = Cb05ConflictServer();
    final api = ApiClient(
      baseUrl: 'http://cb05.test',
      token: 'cb05-token',
      client: server,
    );
    final first = await api.push([windowsOperation]);
    final stale = await api.push([androidOperation]);

    expect(first['accepted'], hasLength(1));
    expect(first['conflicts'], isEmpty);
    expect(stale['accepted'], isEmpty);
    expect(stale['conflicts'], hasLength(1));
    expect((stale['conflicts'] as List).single['reason'],
        'server has a newer version');
    expect(server.serverVersion, 22);
  });
}
