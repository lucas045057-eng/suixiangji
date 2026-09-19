import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:wealthmate_flutter/data/api_client.dart';
import 'package:wealthmate_flutter/data/finance_repository.dart';
import 'package:wealthmate_flutter/data/local_repository.dart';
import 'package:wealthmate_flutter/data/sync_queue.dart';
import 'package:wealthmate_flutter/domain/models.dart';
import 'package:wealthmate_flutter/state/finance_store.dart';
import 'package:wealthmate_flutter/ui/theme.dart';
import 'package:wealthmate_flutter/ui/transaction_detail_page.dart';

class Dc03SyncedEditMemory implements KeyValueStore {
  final Map<String, String> values = {};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;
}

class Dc03EditSyncClient extends http.BaseClient {
  int serverVersion = 9;
  bool failNextPush = false;
  int pushFailuresRemaining = 0;
  final List<List<Map<String, Object?>>> pushes = [];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request.url.path == '/sync/push') {
      final decoded = request is http.Request
          ? jsonDecode(request.body) as Map
          : jsonDecode(await request.finalize().bytesToString()) as Map;
      final operations = ((decoded['operations'] as List?) ?? const [])
          .map((item) => (item as Map).cast<String, Object?>())
          .toList();
      pushes.add(operations);
      if (failNextPush || pushFailuresRemaining > 0) {
        failNextPush = false;
        if (pushFailuresRemaining > 0) pushFailuresRemaining--;
        return _response(request, 503, {'detail': 'temporary outage'});
      }
      final accepted = operations.map((operation) {
        serverVersion += 1;
        return {
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
        'transactions': const <Object?>[],
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

const syncedEditTransaction = FinanceTransaction(
  id: 'tx-synced-1',
  date: '2026-09-05',
  type: TransactionType.expense,
  amount: 22.02,
  currency: 'USD',
  cnyAmount: 158.544,
  exchangeRate: 7.2,
  exchangeRateDate: '2026-09-05',
  exchangeRateSource: 'sentinel-rate-source',
  conversionStatus: 'ready',
  categoryId: 'synced-category',
  accountId: 'synced-account',
  note: 'old',
  clientOpId: 'create-op-1',
  serverVersion: 9,
  updatedAt: '2026-09-05T10:00:00Z',
);

FinanceStore syncedEditStore({
  ApiClient? api,
  Dc03SyncedEditMemory? memory,
}) {
  return FinanceStore(
    repository: FinanceRepository(
      local: LocalRepository(memory ?? Dc03SyncedEditMemory()),
      queue: SyncQueue(),
      api: api,
    ),
    initialState: const FinanceState(
      currentMonth: '2026-09',
      accounts: [
        Account(
          id: 'synced-account',
          name: '已同步账户',
          type: AccountType.asset,
        ),
      ],
      categories: [
        Category(id: 'synced-category', name: '已同步分类'),
      ],
      transactions: [syncedEditTransaction],
    ),
  );
}

Future<void> submitSyncedEdit(WidgetTester tester, FinanceStore store,
    {String amount = '23.03', String note = 'edited'}) async {
  await tester.pumpWidget(MaterialApp(
    theme: wealthMateTheme(),
    home: TransactionDetailPage(
      store: store,
      transaction: store.state.transactions.single,
    ),
  ));
  await tester.tap(find.byTooltip('编辑'));
  await tester.pumpAndSettle();
  final fields = find.byType(TextFormField);
  expect(fields, findsNWidgets(4));
  await tester.enterText(fields.at(0), amount);
  await tester.enterText(fields.at(3), note);
  final saveButton = find.text('保存修改');
  await tester.ensureVisible(saveButton);
  await tester.tap(saveButton);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
      'RED-SYNC-01 a synced transaction edit uses a new operation identity',
      (tester) async {
    final store = syncedEditStore();

    await submitSyncedEdit(tester, store);

    final operation = store.repository.queue.pending().single;
    expect(operation.entityId, 'tx-synced-1');
    expect(operation.payload['amount'], 23.03);
    expect(operation.clientOpId, isNot('create-op-1'));
  });

  testWidgets('RED-SYNC-02 repeated unsynced edits keep one latest snapshot',
      (tester) async {
    final store = syncedEditStore();

    await store.updateTransaction(
        syncedEditTransaction.copyWith(amount: 23.03, note: 'first-edit'));
    await store.updateTransaction(
        syncedEditTransaction.copyWith(amount: 24.04, note: 'latest-edit'));

    final operations = store.repository.queue.pending();
    expect(operations, hasLength(1));
    expect(operations.single.entityId, 'tx-synced-1');
    expect(operations.single.payload['amount'], 24.04);
    expect(operations.single.payload['note'], 'latest-edit');
  });

  testWidgets('RED-META-01 a synced edit preserves server metadata',
      (tester) async {
    final store = syncedEditStore();

    await submitSyncedEdit(tester, store);

    final updated = store.state.transactions.single;
    expect(updated.serverVersion, 9);
    expect(updated.cnyAmount, 165.82);
    expect(updated.exchangeRate, 7.2);
    expect(updated.exchangeRateDate, '2026-09-05');
    expect(updated.exchangeRateSource, 'sentinel-rate-source');
    expect(updated.updatedAt, '2026-09-05T10:00:00Z');
  });

  testWidgets('RED-SYNC-03 retry preserves the pending edit operation ID',
      (tester) async {
    final memory = Dc03SyncedEditMemory();
    final client = Dc03EditSyncClient();
    final store = syncedEditStore(
      memory: memory,
      api: ApiClient(
        baseUrl: 'http://dc03.test',
        token: 'dc03-token',
        client: client,
      ),
    );
    await store.repository.ensureLocalOwner('dc03-user');

    // The local mutation callback schedules the debounced automatic drain.
    // Make that first automatic round fail so this test can inspect retry
    // persistence instead of racing a successful background push.
    client.pushFailuresRemaining = 2;
    await submitSyncedEdit(tester, store);
    final operationId = store.repository.queue.pending().single.clientOpId;
    await store.sync();
    expect(store.repository.queue.pending(), hasLength(1));

    final persisted = jsonDecode((await LocalRepository(memory)
        .forUser('dc03-user')
        .readMetadata(LocalRepository.queueStorageKey))!) as List<dynamic>;
    expect((persisted.single as Map)['client_op_id'], operationId);

    await store.sync();
    expect(client.pushes.length, greaterThanOrEqualTo(3));
    for (final push in client.pushes) {
      expect(push.single['client_op_id'], operationId);
    }
  });

  testWidgets(
      'RED-SYNC-04 a committed edit creates a new operation for the same entity',
      (tester) async {
    final client = Dc03EditSyncClient();
    final store = syncedEditStore(
      api: ApiClient(
        baseUrl: 'http://dc03.test',
        token: 'dc03-token',
        client: client,
      ),
    );
    await store.repository.ensureLocalOwner('dc03-user');

    await submitSyncedEdit(tester, store, amount: '23.03', note: 'first-edit');
    await store.sync();
    final firstOperationId = store.state.transactions.single.clientOpId;

    // Preserve the second edit in the queue so the test verifies operation
    // identity independently from automatic-drain timing.
    client.failNextPush = true;
    await submitSyncedEdit(tester, store, amount: '24.04', note: 'second-edit');
    final secondOperation = store.repository.queue.pending().single;

    expect(store.state.transactions, hasLength(1));
    expect(store.state.transactions.single.id, 'tx-synced-1');
    expect(secondOperation.entityId, 'tx-synced-1');
    expect(secondOperation.clientOpId, isNot(firstOperationId));
    expect(secondOperation.payload['amount'], 24.04);
  });
}
