import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:wealthmate_flutter/data/api_client.dart';
import 'package:wealthmate_flutter/data/drift_database.dart';
import 'package:wealthmate_flutter/data/finance_repository.dart';
import 'package:wealthmate_flutter/data/local_repository.dart';
import 'package:wealthmate_flutter/data/sync_queue.dart';
import 'package:wealthmate_flutter/domain/models.dart';
import 'package:wealthmate_flutter/state/finance_store.dart';

Future<AppDatabase> openTestDatabase(Directory directory, String name) async {
  final file = File('${directory.path}${Platform.pathSeparator}$name.sqlite');
  return AppDatabase(NativeDatabase(file));
}

FinanceRepository repositoryFor(AppDatabase database, {ApiClient? api}) {
  return FinanceRepository(
    local: LocalRepository(DriftKeyValueStore(database)),
    queue: SyncQueue(),
    api: api,
  );
}

class RecordingSyncClient extends http.BaseClient {
  int pushCount = 0;
  final List<int> requestedSinceVersions = [];
  final List<Map<String, Object?>> pushBodies = [];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request.url.path == '/sync/pull') {
      requestedSinceVersions
          .add(int.parse(request.url.queryParameters['since_version']!));
      return _jsonResponse(
          200,
          {
            'items': const <Object?>[],
            'accounts': const <Object?>[],
            'categories': const <Object?>[],
            'budgets': const <Object?>[],
            'server_version': 1,
          },
          request);
    }
    if (request.url.path == '/sync/push') {
      pushCount++;
      final body = request is http.Request
          ? jsonDecode(request.body)
          : jsonDecode(await request.finalize().bytesToString());
      pushBodies.add((body as Map).cast<String, Object?>());
      return _jsonResponse(
          200,
          {
            'accepted': const <Object?>[],
            'conflicts': const <Object?>[],
            'server_version': 1,
          },
          request);
    }
    return _jsonResponse(404, {'error': 'unexpected path'}, request);
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

class UnauthorizedClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    return http.StreamedResponse(
      Stream<List<int>>.value(utf8.encode('{"detail":"登录已失效"}')),
      401,
      request: request,
      headers: const {'content-type': 'application/json'},
    );
  }
}

const userAState = FinanceState(
  accounts: [
    Account(
      id: 'user-a-account',
      name: '用户 A 账户',
      type: AccountType.asset,
    ),
  ],
  categories: [
    Category(id: 'user-a-category', name: '用户 A 分类'),
  ],
  transactions: [
    FinanceTransaction(
      id: 'user-a-tx',
      date: '2026-09-05',
      type: TransactionType.expense,
      amount: 9.99,
      accountId: 'user-a-account',
      categoryId: 'user-a-category',
      note: '用户 A 本地数据',
    ),
  ],
  syncState: SyncState(serverVersion: 100),
);

void main() {
  test('user B does not restore user A finance state', () async {
    final directory =
        await Directory.systemTemp.createTemp('suixiangji-user-isolation-');
    AppDatabase? database;
    try {
      database = await openTestDatabase(directory, 'finance-state');
      final userARepository = repositoryFor(database);
      await userARepository.loadForUser('user-a');
      await userARepository.save(userAState);
      await database.close();
      database = null;

      database = await openTestDatabase(directory, 'finance-state');
      final userBRepository = repositoryFor(database);
      final restoredByB = await userBRepository.loadForUser('user-b');

      final leakedIds = [
        ...?restoredByB?.accounts.map((item) => item.id),
        ...?restoredByB?.transactions.map((item) => item.id),
      ];
      expect(leakedIds, isEmpty);
    } finally {
      await database?.close();
      await directory.delete(recursive: true);
    }
  });

  test('new user does not inherit previous user server version', () async {
    final directory =
        await Directory.systemTemp.createTemp('suixiangji-user-isolation-');
    AppDatabase? database;
    try {
      database = await openTestDatabase(directory, 'server-version');
      final userARepository = repositoryFor(database);
      await userARepository.loadForUser('user-a');
      await userARepository.save(const FinanceState(
        syncState: SyncState(serverVersion: 321),
      ));
      await database.close();
      database = null;

      database = await openTestDatabase(directory, 'server-version');
      final userBRepository = repositoryFor(database);
      final restoredByB = await userBRepository.loadForUser('user-b');

      expect(restoredByB?.syncState.serverVersion, 0);
    } finally {
      await database?.close();
      await directory.delete(recursive: true);
    }
  });

  test('user B does not inherit user A pending queue', () async {
    final directory =
        await Directory.systemTemp.createTemp('suixiangji-user-isolation-');
    AppDatabase? database;
    try {
      database = await openTestDatabase(directory, 'sync-queue');
      final userARepository = repositoryFor(database);
      await userARepository.loadForUser('user-a');
      userARepository.queue.enqueue(const SyncOperation(
        clientOpId: 'user-a-pending-op',
        entity: 'transactions',
        entityId: 'user-a-pending-tx',
        type: SyncOperationType.upsert,
        payload: {
          'id': 'user-a-pending-tx',
          'date': '2026-09-05',
          'type': 'expense',
          'amount': 1.23,
        },
      ));
      await userARepository.persistQueue();
      await database.close();
      database = null;

      database = await openTestDatabase(directory, 'sync-queue');
      final userBRepository = repositoryFor(database);
      await userBRepository.loadForUser('user-b');

      expect(
        userBRepository.queue
            .pending()
            .where((item) => item.clientOpId == 'user-a-pending-op'),
        isEmpty,
      );
    } finally {
      await database?.close();
      await directory.delete(recursive: true);
    }
  });

  test('unbound online repository never pushes a pending queue', () async {
    final directory =
        await Directory.systemTemp.createTemp('suixiangji-user-isolation-');
    AppDatabase? database;
    final client = RecordingSyncClient();
    try {
      database = await openTestDatabase(directory, 'unbound-push');
      final repository = repositoryFor(
        database,
        api: ApiClient(
          baseUrl: 'http://user-isolation.test',
          token: 'user-b-token',
          client: client,
        ),
      );
      repository.queue.enqueue(const SyncOperation(
        clientOpId: 'user-a-pending-op',
        entity: 'transactions',
        entityId: 'user-a-pending-tx',
        type: SyncOperationType.upsert,
        payload: {'id': 'user-a-pending-tx'},
      ));

      final result = await repository.pushPending(const FinanceState());

      expect(client.pushCount, 0);
      expect(result.syncState.error, contains('身份'));
    } finally {
      await database?.close();
      await directory.delete(recursive: true);
    }
  });

  test('same user relog preserves state queue and server version', () async {
    final directory =
        await Directory.systemTemp.createTemp('suixiangji-user-isolation-');
    AppDatabase? database;
    try {
      database = await openTestDatabase(directory, 'a-b-a');
      final userARepository = repositoryFor(database);
      await userARepository.loadForUser('user-a');
      final relogState = userAState.copyWith(
        syncState: const SyncState(serverVersion: 321),
      );
      await userARepository.save(relogState);
      userARepository.queue.enqueue(const SyncOperation(
        clientOpId: 'user-a-pending-op',
        entity: 'transactions',
        entityId: 'user-a-pending-tx',
        type: SyncOperationType.upsert,
        payload: {'id': 'user-a-pending-tx'},
      ));
      await userARepository.persistQueue();
      await database.close();
      database = null;

      database = await openTestDatabase(directory, 'a-b-a');
      final userARepositoryAfterRelog = repositoryFor(database);
      final restoredByA = await userARepositoryAfterRelog.loadForUser('user-a');

      expect(
        restoredByA?.transactions.map((item) => item.id),
        contains('user-a-tx'),
      );
      expect(restoredByA?.syncState.serverVersion, 321);
      expect(userARepositoryAfterRelog.queue.pending().single.clientOpId,
          'user-a-pending-op');
    } finally {
      await database?.close();
      await directory.delete(recursive: true);
    }
  });

  test('returning to user A after user B restores A data',
      () async {
    final directory =
        await Directory.systemTemp.createTemp('suixiangji-user-isolation-');
    AppDatabase? database;
    try {
      database = await openTestDatabase(directory, 'a-b-a-reset');
      final userARepository = repositoryFor(database);
      await userARepository.loadForUser('user-a');
      await userARepository.save(userAState);
      await database.close();
      database = null;

      database = await openTestDatabase(directory, 'a-b-a-reset');
      final userBRepository = repositoryFor(database);
      await userBRepository.loadForUser('user-b');
      await database.close();
      database = null;

      database = await openTestDatabase(directory, 'a-b-a-reset');
      final userARepositoryAfterB = repositoryFor(database);
      final restoredByA = await userARepositoryAfterB.loadForUser('user-a');

      expect(restoredByA?.accounts.map((item) => item.id),
          contains('user-a-account'));
      expect(restoredByA?.transactions.map((item) => item.id),
          contains('user-a-tx'));
      expect(restoredByA?.syncState.serverVersion, 100);
    } finally {
      await database?.close();
      await directory.delete(recursive: true);
    }
  });

  test('legacy unowned local data is cleared before first online owner binds',
      () async {
    final directory =
        await Directory.systemTemp.createTemp('suixiangji-user-isolation-');
    AppDatabase? database;
    try {
      database = await openTestDatabase(directory, 'legacy-unowned');
      final legacyRepository = repositoryFor(database);
      await legacyRepository.save(userAState);
      legacyRepository.queue.enqueue(const SyncOperation(
        clientOpId: 'legacy-pending-op',
        entity: 'transactions',
        entityId: 'legacy-pending-tx',
        type: SyncOperationType.upsert,
        payload: {'id': 'legacy-pending-tx'},
      ));
      await legacyRepository.persistQueue();

      final onlineRepository = repositoryFor(
        database,
        api: ApiClient(
          baseUrl: 'http://user-isolation.test',
          token: 'user-b-token',
          client: RecordingSyncClient(),
        ),
      );
      final restored = await onlineRepository.loadForUser('user-b');

      expect(restored?.accounts, isEmpty);
      expect(restored?.transactions, isEmpty);
      expect(restored?.syncState.serverVersion, 0);
      expect(onlineRepository.queue.pending(), isEmpty);
      expect(await onlineRepository.local.loadOwnerUserId(), 'user-b');
    } finally {
      await database?.close();
      await directory.delete(recursive: true);
    }
  });

  test('logout preserves persisted data for the same user relog', () async {
    final directory =
        await Directory.systemTemp.createTemp('suixiangji-user-isolation-');
    AppDatabase? database;
    try {
      database = await openTestDatabase(directory, 'logout-relog');
      final repository = repositoryFor(
        database,
        api: ApiClient(
          baseUrl: 'http://user-isolation.test',
          token: 'user-a-token',
          client: RecordingSyncClient(),
        ),
      );
      await repository.loadForUser('user-a');
      await repository.save(userAState);
      repository.queue.enqueue(const SyncOperation(
        clientOpId: 'user-a-pending-op',
        entity: 'transactions',
        entityId: 'user-a-pending-tx',
        type: SyncOperationType.upsert,
        payload: {'id': 'user-a-pending-tx'},
      ));
      await repository.persistQueue();

      final store = FinanceStore(repository: repository);
      store.clearAuthenticatedSession();
      final restored = await repository.loadForUser('user-a');

      expect(
          restored?.transactions.map((item) => item.id), contains('user-a-tx'));
      expect(restored?.syncState.serverVersion, 100);
      expect(repository.queue.pending().single.clientOpId, 'user-a-pending-op');
    } finally {
      await database?.close();
      await directory.delete(recursive: true);
    }
  });

  test('401 keeps local data available for the same user relog', () async {
    final directory =
        await Directory.systemTemp.createTemp('suixiangji-user-isolation-');
    AppDatabase? database;
    try {
      database = await openTestDatabase(directory, 'auth-expired');
      final api = ApiClient(
        baseUrl: 'http://user-isolation.test',
        token: 'expired-token',
        client: UnauthorizedClient(),
      );
      final repository = repositoryFor(database, api: api);
      await repository.loadForUser('user-a');
      await repository.save(userAState);
      repository.queue.enqueue(const SyncOperation(
        clientOpId: 'user-a-pending-op',
        entity: 'transactions',
        entityId: 'user-a-pending-tx',
        type: SyncOperationType.upsert,
        payload: {'id': 'user-a-pending-tx'},
      ));
      await repository.persistQueue();

      final store = FinanceStore(repository: repository);
      api.onAuthExpired = store.clearAuthenticatedSession;
      await expectLater(api.fetchProfile(), throwsA(isA<ApiFailure>()));
      final restored = await repository.loadForUser('user-a');

      expect(
          restored?.transactions.map((item) => item.id), contains('user-a-tx'));
      expect(restored?.syncState.serverVersion, 100);
      expect(repository.queue.pending().single.clientOpId, 'user-a-pending-op');
    } finally {
      await database?.close();
      await directory.delete(recursive: true);
    }
  });

  test('fresh online owner starts pull at server version zero', () async {
    final directory =
        await Directory.systemTemp.createTemp('suixiangji-user-isolation-');
    AppDatabase? database;
    final client = RecordingSyncClient();
    try {
      database = await openTestDatabase(directory, 'fresh-online');
      final repository = repositoryFor(
        database,
        api: ApiClient(
          baseUrl: 'http://user-isolation.test',
          token: 'user-a-token',
          client: client,
        ),
      );
      final state = await repository.loadForUser('user-a');
      final pulled = await repository.pullChanges(state!);

      expect(state.syncState.serverVersion, 0);
      expect(pulled.syncState.serverVersion, 1);
      expect(client.pushCount, 0);
      expect(client.requestedSinceVersions, [0]);
    } finally {
      await database?.close();
      await directory.delete(recursive: true);
    }
  });
}
