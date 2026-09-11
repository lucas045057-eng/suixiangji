import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:wealthmate_flutter/data/api_client.dart';
import 'package:wealthmate_flutter/data/finance_repository.dart';
import 'package:wealthmate_flutter/data/local_repository.dart';
import 'package:wealthmate_flutter/data/sync_queue.dart';
import 'package:wealthmate_flutter/state/finance_store.dart';
import 'offline_owner_recovery_test.dart' as fixtures;

class DelayedStorage extends fixtures.MemoryKeyValueStore {
  Completer<void>? gate;
  final started = Completer<void>();

  @override
  Future<void> write(String key, String value) async {
    final pending = gate;
    if (pending != null) {
      gate = null;
      started.complete();
      await pending.future;
    }
    await super.write(key, value);
  }
}

class Harness {
  Harness({fixtures.MemoryKeyValueStore? storage, http.Client? client}) {
    localStorage = storage ?? fixtures.MemoryKeyValueStore();
    api = ApiClient(
        baseUrl: 'http://v1.test',
        tokenStore: tokens,
        client: client ??
            MockClient((request) async => http.Response(
                jsonEncode({
                  'id': api.token,
                  'username': api.token,
                  'display_name': api.token,
                  'quick_memories': [],
                }),
                200)));
    repository = FinanceRepository(
        local: LocalRepository(localStorage), queue: SyncQueue(), api: api);
    store = FinanceStore(repository: repository);
  }
  final tokens = fixtures.MemoryTokenStore();
  late final fixtures.MemoryKeyValueStore localStorage;
  late final ApiClient api;
  late final FinanceRepository repository;
  late final FinanceStore store;

  Future<void> login(String id) async {
    await api.saveToken(id);
    expect(await store.loadProfile(), isTrue);
  }

  Future<void> seed() async {
    await repository.save(fixtures.ownerAState());
    repository.queue.enqueue(fixtures.pendingOperation);
    await repository.persistQueue();
    await store.load();
  }

  Future<void> logout() async {
    await api.logout();
    store.clearAuthenticatedSession();
  }

  void expectA() {
    expect(store.state.toJson(), fixtures.ownerAState().toJson());
    expect(repository.queue.toJson(), [fixtures.pendingOperation.toJson()]);
  }
}

void main() {
  test('late A partition purge keeps active B owner and B data', () async {
    final storage = DelayedStorage();
    final h = Harness(storage: storage);
    await h.login('A');
    await h.seed();
    final a = h.repository.local;
    final gate = Completer<void>();
    storage.gate = gate;
    final purging = a.purge();
    await storage.started.future;
    await h.logout();
    await h.login('B');
    await h.seed();
    gate.complete();
    await purging;
    expect(await h.repository.local.loadOwnerUserId(), 'B');
    h.expectA();
    expect((await a.load())!.transactions, isEmpty);
  });

  test('same user relogin restores exact state queue and cursor', () async {
    final h = Harness();
    await h.login('A');
    await h.seed();
    await h.logout();
    await h.login('A');
    h.expectA();
  });

  test('A unsynced logout B empty logout A restores exact partition', () async {
    final h = Harness();
    await h.login('A');
    await h.seed();
    await h.logout();
    await h.login('B');
    expect(h.store.state.transactions, isEmpty);
    expect(h.repository.queue.pending(), isEmpty);
    expect(h.store.state.syncState.serverVersion, 0);
    await h.logout();
    await h.login('A');
    h.expectA();
  });

  test('restart offline restores persisted queue cursor and complete state',
      () async {
    final h = Harness();
    await h.login('A');
    await h.seed();
    final api = ApiClient(
        baseUrl: 'http://v1.test',
        tokenStore: h.tokens,
        client: MockClient((_) async => throw Exception('offline')));
    await api.restoreToken();
    final repository = FinanceRepository(
        local: LocalRepository(h.localStorage), queue: SyncQueue(), api: api);
    final store = FinanceStore(repository: repository);
    await store.load();
    await store.loadProfile();
    await store.sync();
    expect(store.state.transactions.single.toJson(),
        fixtures.ownerAState().transactions.single.toJson());
    expect(store.state.syncState.serverVersion, 50);
    expect(repository.queue.toJson(), [fixtures.pendingOperation.toJson()]);
    expect(api.token, 'A');
  });

  test('owned legacy data survives B first login and migrates only to A',
      () async {
    final storage = fixtures.MemoryKeyValueStore();
    final legacy = LocalRepository(storage);
    await legacy.save(fixtures.ownerAState());
    await legacy.saveQueue(SyncQueue()..enqueue(fixtures.pendingOperation));
    await legacy.saveOwnerUserId('A');
    final h = Harness(storage: storage);
    await h.login('B');
    expect(h.store.state.transactions, isEmpty);
    await h.logout();
    await h.login('A');
    h.expectA();
  });

  test('unowned legacy bytes remain recoverable and never adopted', () async {
    final storage = fixtures.MemoryKeyValueStore();
    final legacy = LocalRepository(storage);
    await legacy.save(fixtures.ownerAState());
    await legacy.saveQueue(SyncQueue()..enqueue(fixtures.pendingOperation));
    final originalState = storage.values[LocalRepository.storageKey];
    final originalQueue = storage.values[LocalRepository.queueStorageKey];
    final h = Harness(storage: storage);
    await h.login('B');
    expect(h.store.state.transactions, isEmpty);
    expect(h.repository.queue.pending(), isEmpty);
    expect(storage.values[LocalRepository.storageKey], originalState);
    expect(storage.values[LocalRepository.queueStorageKey], originalQueue);
  });

  for (final kind in ['401', 'profile', 'profile rotation', 'push', 'pull']) {
    test(
        'delayed A $kind cannot affect B session state queue cursor or storage',
        () async {
      final response = Completer<http.Response>();
      final started = Completer<void>();
      var delay = false;
      final h = Harness(client: MockClient((request) async {
        if (delay && request.headers['authorization'] == 'Bearer A') {
          started.complete();
          return response.future;
        }
        final id = request.headers['authorization']!.split(' ').last;
        return http.Response(
            jsonEncode({
              'id': id,
              'username': id,
              'display_name': id,
              'quick_memories': []
            }),
            200);
      }));
      await h.login('A');
      await h.seed();
      delay = true;
      final Future<Object?> pending = switch (kind) {
        'push' => h.store.sync(),
        'pull' => h.repository.pullChanges(h.store.state),
        'profile rotation' => h.store.updateProfile(displayName: 'late A'),
        _ => h.store.loadProfile(),
      };
      await started.future;
      await h.logout();
      await h.login('B');
      final stateB = h.store.state.toJson();
      response.complete(http.Response(
          jsonEncode(kind == 'push'
              ? {
                  'accepted': [
                    {
                      'client_op_id': 'offline-pending-A',
                      'entity_id': 'offline-pending-A',
                      'server_version': 99
                    }
                  ],
                  'conflicts': [],
                  'server_version': 99
                }
              : kind == 'pull'
                  ? {
                      'items': fixtures
                          .ownerAState()
                          .transactions
                          .map((e) => e.toJson())
                          .toList(),
                      'server_version': 99
                    }
                  : {
                      'id': 'A',
                      'username': 'A',
                      'display_name': 'late A',
                      'quick_memories': [],
                      'access_token': 'rotated-A'
                    }),
          kind == '401' ? 401 : 200));
      await pending;
      expect(h.api.token, 'B');
      expect(h.api.lastVerifiedUserId, 'B');
      expect(h.tokens.token, 'B');
      expect(h.tokens.lastVerifiedUserId, 'B');
      expect(h.store.profile?.id, 'B');
      expect(h.store.state.toJson(), stateB);
      expect((await h.repository.load())!.toJson(), stateB);
      expect(h.repository.queue.pending(), isEmpty);
      delay = false;
      await h.logout();
      await h.login('A');
      h.expectA();
    });
  }

  test('delayed A local save cannot populate B or overwrite B queue', () async {
    final storage = DelayedStorage();
    final h = Harness(storage: storage);
    await h.login('A');
    await h.seed();
    final gate = Completer<void>();
    storage.gate = gate;
    final pending = h.store.addTransaction(fixtures
        .ownerAState()
        .transactions
        .single
        .copyWith(id: 'late-local-A'));
    await storage.started.future;
    await h.logout();
    await h.login('B');
    gate.complete();
    await pending;
    expect(h.store.state.transactions, isEmpty);
    expect((await h.repository.load())!.transactions, isEmpty);
    expect(h.repository.queue.pending(), isEmpty);
    await h.logout();
    await h.login('A');
    expect(
        h.store.state.transactions.map((e) => e.id), contains('late-local-A'));
    expect(h.repository.queue.pending(), hasLength(2));
  });
}
