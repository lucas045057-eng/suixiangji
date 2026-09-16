import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:wealthmate_flutter/data/api_client.dart';
import 'package:wealthmate_flutter/data/finance_repository.dart';
import 'package:wealthmate_flutter/data/local_repository.dart';
import 'package:wealthmate_flutter/data/sync_queue.dart';
import 'package:wealthmate_flutter/domain/models.dart';
import 'package:wealthmate_flutter/state/finance_store.dart';

class SyncMemory implements KeyValueStore {
  final values = <String, String>{};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async => values[key] = value;
}

/// A response barrier captures a real request/response boundary, without timers.
class SyncBarrier {
  final entered = Completer<void>();
  final release = Completer<void>();
  Future<void> wait() async {
    entered.complete();
    await release.future;
  }
}

/// Transport fake: real ApiClient, queue, repositories and sessions stay in use.
/// Mirrors the existing per-owner version, conflict and idempotency contracts.
class MemorySyncServer extends http.BaseClient {
  int version = 2;
  final records = <String, Map<String, Map<String, Object?>>>{
    'accounts': {
      'account': {
        ...const Account(id: 'account', name: 'Cash', type: AccountType.asset)
            .toJson(),
        'server_version': 1
      },
    },
    'categories': {
      'category': {
        ...const Category(id: 'category', name: 'Food').toJson(),
        'server_version': 2
      },
    },
    'transactions': {},
    'budgets': {},
  };
  final receipts = <String, Map<String, Object?>>{};
  final cursors = <int>[];
  int pushCalls = 0;
  bool failPush = false;
  bool losePushResponse = false;
  bool failPull = false;
  final Set<String> forceConflictEntities = <String>{};
  SyncBarrier? pushBarrier;
  SyncBarrier? pullBarrier;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request.headers['Authorization'] != 'Bearer test-owner-token') {
      return response(request, {'detail': 'Unauthenticated'}, status: 401);
    }
    if (request.url.path == '/sync/push') {
      pushCalls++;
      if (failPush) {
        failPush = false;
        throw const SocketException('injected push failure');
      }
      final body = jsonDecode(await request.finalize().bytesToString()) as Map;
      final accepted = <Map<String, Object?>>[];
      final conflicts = <Map<String, Object?>>[];
      final operations = (body['operations'] as List).cast<Map>();
      // Server applies dependency order; all fixtures have valid references.
      const order = ['accounts', 'categories', 'transactions', 'budgets'];
      operations.sort((a, b) => order
          .indexOf(a['entity'] as String)
          .compareTo(order.indexOf(b['entity'] as String)));
      for (final op in operations) {
        final id = op['client_op_id'] as String;
        final previous = receipts[id];
        if (previous != null) {
          accepted.add({...previous, 'created': false});
          continue;
        }
        final entity = op['entity'] as String;
        final entityId = op['entity_id'] as String;
        final payload = (op['payload'] as Map).cast<String, Object?>();
        final current = records[entity]![entityId];
        final base = payload['server_version'] as num?;
        if (forceConflictEntities.remove(entity) ||
            (current != null &&
                base != null &&
                (current['server_version'] as int) > base)) {
          conflicts.add({
            'client_op_id': id,
            'entity_id': entityId,
            'reason': 'server has a newer version'
          });
          continue;
        }
        version++;
        records[entity]![entityId] = {
          ...payload,
          'id': entityId,
          'server_version': version,
          if (entity == 'transactions') 'client_op_id': id,
          if (op['type'] == 'delete') 'deleted_at': '2026-09-15T12:00:00Z',
        };
        final receipt = {
          'client_op_id': id,
          'entity_id': entityId,
          'server_version': version,
          'created': true
        };
        receipts[id] = receipt;
        accepted.add(receipt);
      }
      final result = {
        'accepted': accepted,
        'conflicts': conflicts,
        'server_version': version
      };
      final barrier = pushBarrier;
      pushBarrier = null;
      if (barrier != null) await barrier.wait();
      if (losePushResponse) {
        losePushResponse = false;
        throw const SocketException('accepted response lost');
      }
      return response(request, result);
    }
    if (request.url.path == '/sync/pull') {
      final since = int.parse(request.url.queryParameters['since_version']!);
      cursors.add(since);
      if (failPull) {
        failPull = false;
        throw const SocketException('injected pull failure');
      }
      List<Map<String, Object?>> newer(String entity) => records[entity]!
          .values
          .where((row) => (row['server_version'] as int) > since)
          .map((row) => Map<String, Object?>.from(row))
          .toList()
        ..sort((a, b) =>
            (a['server_version'] as int).compareTo(b['server_version'] as int));
      final result = {
        'items': newer('transactions'),
        'transactions': newer('transactions'),
        'accounts': newer('accounts'),
        'categories': newer('categories'),
        'budgets': newer('budgets'),
        'server_version': version
      };
      final barrier = pullBarrier;
      pullBarrier = null;
      if (barrier != null) await barrier.wait();
      return response(request, result);
    }
    return response(request, {'detail': 'unexpected path'}, status: 404);
  }

  http.StreamedResponse response(
          http.BaseRequest request, Map<String, Object?> body,
          {int status = 200}) =>
      http.StreamedResponse(Stream.value(utf8.encode(jsonEncode(body))), status,
          request: request, headers: {'content-type': 'application/json'});
}

const syncSeed = FinanceState(
  currentMonth: '2026-09',
  accounts: [
    Account(
        id: 'account', name: 'Cash', type: AccountType.asset, serverVersion: 1)
  ],
  categories: [Category(id: 'category', name: 'Food')],
  syncState: SyncState(serverVersion: 2),
);

FinanceTransaction syncTransaction(String id, {String note = 'original'}) =>
    FinanceTransaction(
      id: id,
      clientOpId: 'create-$id',
      date: '2026-09-15',
      type: TransactionType.expense,
      amount: 12,
      accountId: 'account',
      categoryId: 'category',
      note: note,
    );

Future<FinanceStore> syncDevice(MemorySyncServer server,
    {SyncMemory? memory, FinanceState? initial}) async {
  final fresh = memory == null || memory.values.isEmpty;
  final repository = FinanceRepository(
      local: LocalRepository(memory ?? SyncMemory()),
      queue: SyncQueue(),
      api: ApiClient(
          baseUrl: 'http://memory-sync.test',
          token: 'test-owner-token',
          client: server));
  await repository.ensureLocalOwner('same-owner');
  final state = fresh ? initial ?? syncSeed : (await repository.load())!;
  await repository.save(state);
  return FinanceStore(repository: repository, initialState: state);
}

void main() {
  late MemorySyncServer server;
  late FinanceStore a;
  late FinanceStore b;
  setUp(() async {
    server = MemorySyncServer();
    a = await syncDevice(server);
    b = await syncDevice(server);
  });

  test('A create/push then B old-cursor pull receives the record', () async {
    await a.addTransaction(syncTransaction('a'));
    await a.sync();
    await b.sync();
    expect(b.state.transactions.single.id, 'a');
    expect(b.state.transactions.single.serverVersion, 3);
    expect(server.cursors.last, 2);
  });

  test('B edit then A pull converges to the accepted edit', () async {
    await a.addTransaction(syncTransaction('a'));
    await a.sync();
    await b.sync();
    await b.updateTransaction(
        b.state.transactions.single.copyWith(note: 'B edit'));
    await b.sync();
    await a.sync();
    expect(a.state.transactions.single.note, 'B edit');
    expect(a.state.transactions.single.serverVersion, 4);
  });

  test('A/B different additions are both downloaded during push then pull',
      () async {
    await a.addTransaction(syncTransaction('a'));
    await b.addTransaction(syncTransaction('b'));
    await a.sync();
    await b.sync();
    await a.sync();
    expect(a.state.transactions.map((t) => t.id), unorderedEquals(['a', 'b']));
    expect(b.state.transactions.map((t) => t.id), unorderedEquals(['a', 'b']));
  });

  test('offline push retains pending, cursor and prior successful timestamp',
      () async {
    await a.sync();
    final prior = a.state.syncState.lastSyncedAt;
    await a.addTransaction(syncTransaction('a'));
    server.failPush = true;
    await a.sync();
    expect(a.repository.queue.pending(), hasLength(1));
    expect(a.state.syncState.error, isNotNull);
    expect(a.state.syncState.serverVersion, 2);
    expect(a.state.syncState.lastSyncedAt, prior);
  });

  test('lost acceptance retry is idempotent and eventually clears pending',
      () async {
    await a.addTransaction(syncTransaction('a'));
    server.losePushResponse = true;
    await a.sync();
    expect(a.repository.queue.pending(), hasLength(1));
    expect(a.state.syncState.error, isNotNull);
    await a.sync();
    await b.sync();
    expect(a.repository.queue.pending(), isEmpty);
    expect(b.state.transactions, hasLength(1));
    expect(b.state.transactions.single.serverVersion, 3);
    expect(server.version, 3);
  });

  test('failed pull retains prior success time and unaccepted queue', () async {
    await a.addTransaction(syncTransaction('a'));
    await a.sync();
    await b.sync();
    final prior = b.state.syncState.lastSyncedAt;
    await a.updateTransaction(
        a.state.transactions.single.copyWith(note: 'winner'));
    await a.sync();
    await b.updateTransaction(
        b.state.transactions.single.copyWith(note: 'conflict'));
    server.failPull = true;
    await b.sync();
    expect(b.repository.queue.pending(), hasLength(1));
    expect(b.state.syncState.error, isNotNull);
    expect(b.state.syncState.lastSyncedAt, prior);
  });

  test(
      'conflict recovery downloads authoritative record and permits later edit',
      () async {
    await a.addTransaction(syncTransaction('a'));
    await a.sync();
    await b.sync();
    await a.updateTransaction(
        a.state.transactions.single.copyWith(note: 'winner'));
    await b
        .updateTransaction(b.state.transactions.single.copyWith(note: 'loser'));
    await a.sync();
    await b.sync();
    expect(b.state.transactions.single.note, 'winner');
    expect(b.state.conflicts, isEmpty);
    expect(b.repository.queue.pending(), isEmpty);
    await b.updateTransaction(
        b.state.transactions.single.copyWith(note: 'recovered edit'));
    await b.sync();
    await a.sync();
    expect(a.state.transactions.single.note, 'recovered edit');
  });

  test('restart and same-owner relogin retain cursor and pending snapshot',
      () async {
    final memory = SyncMemory();
    a = await syncDevice(server, memory: memory);
    await b.addTransaction(syncTransaction('b'));
    await b.sync();
    await a.sync();
    await a.addTransaction(syncTransaction('a'));
    final restarted = await syncDevice(server, memory: memory);
    expect(restarted.state.syncState.serverVersion, 3);
    expect(restarted.repository.queue.pending().single.entityId, 'a');
    restarted.repository.unbindLocalOwner();
    await restarted.repository.ensureLocalOwner('same-owner');
    await restarted.sync();
    expect(server.cursors.last, 3);
    expect(restarted.repository.queue.pending(), isEmpty);
    expect(restarted.state.transactions.map((t) => t.id),
        unorderedEquals(['a', 'b']));
  });

  test('restart after accepted push and failed pull downloads missed additions',
      () async {
    final memory = SyncMemory();
    a = await syncDevice(server, memory: memory);
    await a.sync();
    final prior = a.state.syncState.lastSyncedAt;
    await b.addTransaction(syncTransaction('b'));
    await b.sync();
    await a.addTransaction(syncTransaction('a'));
    server.failPull = true;
    await a.sync();
    expect(a.state.syncState.serverVersion, 2);
    expect(a.state.syncState.lastSyncedAt, prior);
    expect(a.state.syncState.error, isNotNull);
    // Accepted work is done; a failed pull must not resurrect it.
    expect(a.repository.queue.pending(), isEmpty);
    final restarted = await syncDevice(server, memory: memory);
    expect(restarted.state.syncState.serverVersion, 2);
    await restarted.sync();
    expect(server.cursors.last, 2);
    expect(restarted.state.transactions.map((t) => t.id),
        unorderedEquals(['a', 'b']));
    expect(restarted.state.syncState.serverVersion, 4);
  });

  test('budget merge does not replace a newer record with an older version',
      () {
    final current = syncSeed.copyWith(budgets: [
      const Budget(
          id: 'budget',
          month: '2026-09',
          categoryId: 'category',
          limit: 200,
          serverVersion: 4),
    ]);
    final merged = a.repository.mergePulledBudgets(current, [
      const Budget(
          id: 'budget',
          month: '2026-09',
          categoryId: 'category',
          limit: 100,
          serverVersion: 3),
    ]);
    expect(merged.budgets.single.limit, 200);
    expect(merged.budgets.single.serverVersion, 4);
  });

  for (final entity in ['transactions', 'accounts', 'categories', 'budgets']) {
    test('$entity converge across devices and reject delayed older pull',
        () async {
      Future<FinanceState> save(FinanceStore device, bool edited) async {
        final repo = device.repository;
        final state = await repo.load() ?? device.state;
        switch (entity) {
          case 'transactions':
            final tx = state.transactions.isEmpty
                ? syncTransaction('row')
                : state.transactions.single
                    .copyWith(clientOpId: 'edit-row', note: 'new');
            return repo.applyLocalTransaction(state, tx);
          case 'accounts':
            return repo.applyLocalAccount(
                state,
                Account(
                    id: 'row',
                    name: edited ? 'new' : 'old',
                    type: AccountType.asset,
                    serverVersion:
                        edited ? state.accounts.last.serverVersion : null));
          case 'categories':
            return repo.applyLocalCategory(
                state, Category(id: 'row', name: edited ? 'new' : 'old'));
          default:
            return repo.applyLocalBudget(
                state,
                Budget(
                    id: 'row',
                    month: '2026-09',
                    categoryId: 'category',
                    limit: edited ? 200 : 100,
                    serverVersion:
                        edited ? state.budgets.single.serverVersion : null));
        }
      }

      final created = await save(b, false);
      await b.repository.sync(created);
      final barrier = SyncBarrier();
      server.pullBarrier = barrier;
      final oldPull = a.repository.pullChanges(a.state);
      await barrier.entered.future;
      final edited = await save(b, true);
      await b.repository.sync(edited);
      final latest = await a.repository.pullChanges(a.state);
      barrier.release.complete();
      final delayed = await oldPull;
      expect(delayed.syncState.serverVersion, latest.syncState.serverVersion);
      switch (entity) {
        case 'transactions':
          expect(delayed.transactions.single.note, 'new');
        case 'accounts':
          expect(delayed.accounts.last.name, 'new');
        case 'categories':
          expect(delayed.categories.last.name, 'new');
        case 'budgets':
          expect(delayed.budgets.single.limit, 200);
      }
    });
  }

  test('old accepted push cannot complete an in-flight same-entity edit',
      () async {
    await a.addTransaction(syncTransaction('a'));
    final barrier = SyncBarrier();
    server.pushBarrier = barrier;
    final syncing = a.sync();
    await barrier.entered.future;
    await a.updateTransaction(
        a.state.transactions.single.copyWith(note: 'newer snapshot'));
    barrier.release.complete();
    await syncing;
    expect(a.repository.queue.pending(), hasLength(1));
    expect(
        a.repository.queue.pending().single.payload['note'], 'newer snapshot');
    expect(a.state.transactions.single.note, 'newer snapshot');
    expect(a.repository.queue.pending().single.clientOpId, isNot('create-a'));
    await a.sync();
    await b.sync();
    expect(a.repository.queue.pending(), isEmpty);
    expect(b.state.transactions.single.note, 'newer snapshot');
  });

  test('accepted in-flight update preserves a later distinct operation ID',
      () async {
    await a.addTransaction(syncTransaction('a'));
    await a.sync();
    await a.updateTransaction(
        a.state.transactions.single.copyWith(note: 'first edit'));
    final barrier = SyncBarrier();
    server.pushBarrier = barrier;
    final syncing = a.sync();
    await barrier.entered.future;
    await a.updateTransaction(
        a.state.transactions.single.copyWith(note: 'second edit'));
    final laterId = a.repository.queue.pending().single.clientOpId;
    barrier.release.complete();
    await syncing;
    expect(a.repository.queue.pending().single.clientOpId, laterId);
    expect(a.state.transactions.single.note, 'second edit');
    await a.sync();
    await b.sync();
    expect(b.state.transactions.single.note, 'second edit');
    expect(a.repository.queue.pending(), isEmpty);
  });

  for (final entity in ['transactions', 'accounts', 'categories', 'budgets']) {
    test('$entity keeps a local edit made during blocked conflict recovery',
        () async {
      Future<void> createSharedRecord() async {
        switch (entity) {
          case 'transactions':
            await a.addTransaction(syncTransaction('conflict-row'));
          case 'accounts':
            await a.updateAccount(
                a.state.accounts.single.copyWith(name: 'shared account'));
          case 'categories':
            await a.updateCategory('category',
                name: 'shared category', active: true);
          case 'budgets':
            await a.upsertBudget(
              id: 'conflict-budget',
              month: '2026-09',
              categoryId: 'category',
              limit: 100,
            );
        }
        await a.sync();
        await b.sync();
      }

      Future<void> edit(FinanceStore device, String label) async {
        switch (entity) {
          case 'transactions':
            await device.updateTransaction(
                device.state.transactions.single.copyWith(note: label));
          case 'accounts':
            await device.updateAccount(
                device.state.accounts.single.copyWith(name: label));
          case 'categories':
            await device.updateCategory('category', name: label, active: true);
          case 'budgets':
            await device.upsertBudget(
              id: 'conflict-budget',
              month: '2026-09',
              categoryId: 'category',
              limit: label == 'later local edit' ? 300 : 200,
            );
        }
      }

      String value(FinanceState state) {
        switch (entity) {
          case 'transactions':
            return state.transactions.single.note;
          case 'accounts':
            return state.accounts.single.name;
          case 'categories':
            return state.categories.single.name;
          case 'budgets':
            return state.budgets.single.limit.toString();
          default:
            throw StateError('unknown entity');
        }
      }

      await createSharedRecord();
      await edit(a, 'remote winner');
      await a.sync();
      await edit(b, 'conflicted local edit');
      server.forceConflictEntities.add(entity);
      final barrier = SyncBarrier();
      server.pullBarrier = barrier;

      final recovering = b.sync();
      await barrier.entered.future;
      await edit(b, 'later local edit');
      barrier.release.complete();
      await recovering;

      expect(
          value(b.state), entity == 'budgets' ? '300.0' : 'later local edit');
      expect(b.repository.queue.pending(), hasLength(1));
      expect(b.repository.queue.pending().single.entity, entity);
    });
  }
}
