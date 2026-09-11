import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:wealthmate_flutter/data/api_client.dart';
import 'package:wealthmate_flutter/data/local_repository.dart';
import 'package:wealthmate_flutter/data/finance_repository.dart';
import 'package:wealthmate_flutter/data/sync_queue.dart';
import 'package:wealthmate_flutter/state/finance_store.dart';
import 'offline_owner_recovery_test.dart' as fixtures;
import 'v1_session_partition_test.dart' show Harness, DelayedStorage;

class DelayedCredentials extends fixtures.MemoryTokenStore {
  String? block;
  final started = Completer<void>();
  final release = Completer<void>();

  Future<void> pause(String operation) async {
    if (block != operation) return;
    block = null;
    started.complete();
    await release.future;
  }

  @override
  Future<void> write(String value) async {
    await pause('token');
    await super.write(value);
  }

  @override
  Future<void> writeLastVerifiedUserId(String value) async {
    await pause('identity');
    await super.writeLastVerifiedUserId(value);
  }
}

class DelayedPartitionRead extends fixtures.MemoryKeyValueStore {
  final started = Completer<void>();
  final release = Completer<void>();
  bool armed = true;

  @override
  Future<String?> read(String key) async {
    final value = await super.read(key);
    if (armed && key == '${LocalRepository.storageKey}:user:A') {
      armed = false;
      started.complete();
      await release.future;
    }
    return value;
  }
}

class DelayedOwnerWrite extends fixtures.MemoryKeyValueStore {
  final started = Completer<void>();
  final release = Completer<void>();
  bool armed = true;

  @override
  Future<void> write(String key, String value) async {
    if (armed && key == LocalRepository.ownerStorageKey) {
      armed = false;
      started.complete();
      await release.future;
    }
    await super.write(key, value);
  }
}

class DelayedOwnerRead extends fixtures.MemoryKeyValueStore {
  final started = Completer<void>();
  final release = Completer<void>();
  bool armed = false;
  @override
  Future<String?> read(String key) async {
    final value = await super.read(key);
    if (armed && key == LocalRepository.ownerStorageKey) {
      armed = false;
      started.complete();
      await release.future;
    }
    return value;
  }
}

void main() {
  test('stale offline-owner recovery cannot clear newly bound B queue',
      () async {
    final storage = DelayedOwnerRead();
    final h = Harness(storage: storage);
    await h.login('A');
    await h.seed();
    final repository = FinanceRepository(
        local: LocalRepository(storage), queue: SyncQueue(), api: h.api);
    storage.armed = true;
    final oldLoad = repository.load();
    await storage.started.future;
    await h.logout();
    await h.api.saveToken('B');
    await h.api.fetchProfile();
    await repository.loadForUser('B');
    const pendingB = SyncOperation(
        clientOpId: 'B-op',
        entity: 'accounts',
        entityId: 'B-account',
        type: SyncOperationType.upsert,
        payload: {'id': 'B-account'});
    repository.queue.enqueue(pendingB);
    await repository.persistQueue();
    storage.release.complete();
    await oldLoad;
    expect(repository.queue.toJson(), [pendingB.toJson()]);
    expect(repository.localOwnerUserId, 'B');
  });
  test('concurrent legacy adoption cannot overwrite a completed partition edit',
      () async {
    final storage = DelayedPartitionRead();
    final local = LocalRepository(storage);
    await local.save(fixtures.ownerAState());
    await local.saveOwnerUserId('A');
    final first = local.migrateLegacy();
    await storage.started.future;
    final second = local.migrateLegacy().then((_) => local
        .forUser('A')
        .save(fixtures.ownerAState().copyWith(currentMonth: '2026-10')));
    await Future<void>.delayed(Duration.zero);
    storage.release.complete();
    await Future.wait([first, second]);
    expect((await local.forUser('A').load())!.currentMonth, '2026-10');
  });

  test(
      'delayed A owner-pointer write cannot replace B final binding or pointer',
      () async {
    final storage = DelayedOwnerWrite();
    final h = Harness(storage: storage);
    await h.api.saveToken('A');
    final oldProfile = h.store.loadProfile();
    await storage.started.future;
    await h.logout();
    await h.api.saveToken('B');
    final newProfile = h.store.loadProfile();
    await Future<void>.delayed(Duration.zero);
    storage.release.complete();
    expect(await oldProfile, isFalse);
    expect(await newProfile, isTrue);
    expect(h.repository.localOwnerUserId, 'B');
    expect(await h.repository.local.loadOwnerUserId(), 'B');
    expect(h.store.profile!.id, 'B');
    expect(h.repository.queue.pending(), isEmpty);
  });
  test(
      'replacement credentials cannot send retained A queue before B identity is bound',
      () async {
    final syncRequests = <String>[];
    final h = Harness(client: MockClient((request) async {
      if (request.url.path.startsWith('/sync/')) {
        syncRequests.add(request.url.path);
        return http.Response(
            '{"accepted":[],"conflicts":[],"items":[],"server_version":0}',
            200);
      }
      return http.Response(
          '{"id":"A","username":"Alice","display_name":"A","quick_memories":[]}',
          200);
    }));
    await h.login('A');
    await h.seed();
    await h.logout();
    await h.api.saveToken('B');
    await h.store.sync();
    expect(syncRequests, isEmpty);
    expect(h.repository.queue.toJson(), [fixtures.pendingOperation.toJson()]);
  });
  test(
      'offline restart after verified relogin restores A even if last active pointer is B',
      () async {
    final h = Harness();
    await h.login('A');
    await h.seed();
    await h.logout();
    await h.login('B');
    await h.logout();
    // Identity was verified, but the app stopped before local initialization.
    await h.api.saveToken('A');
    await h.api.fetchProfile();
    final api = ApiClient(
        baseUrl: 'http://v1.test',
        tokenStore: h.tokens,
        client: MockClient((_) async => throw Exception('offline')));
    await api.restoreToken();
    final repository = FinanceRepository(
        local: LocalRepository(h.localStorage), queue: SyncQueue(), api: api);
    final store = FinanceStore(repository: repository);
    await store.load();
    expect(store.state.toJson(), fixtures.ownerAState().toJson());
    expect(repository.queue.toJson(), [fixtures.pendingOperation.toJson()]);
  });
  test(
      'configured replacement token cannot restore another token verified owner',
      () async {
    final tokens = fixtures.MemoryTokenStore()
      ..token = 'A-token'
      ..lastVerifiedUserId = 'A';
    final api = ApiClient(
        baseUrl: 'http://v1.test', token: 'B-token', tokenStore: tokens);
    expect(await api.restoreToken(), isTrue);
    expect(api.token, 'B-token');
    expect(api.lastVerifiedUserId, isNull);
  });

  for (final operation in ['login', 'register', 'profile']) {
    test('delayed $operation credential write cannot complete A auth flow in B',
        () async {
      final tokens = DelayedCredentials()
        ..block = operation == 'profile' ? 'identity' : 'token';
      final api = ApiClient(
          baseUrl: 'http://v1.test',
          token: 'A',
          tokenStore: tokens,
          client: MockClient((request) async => http.Response(
              jsonEncode(request.url.path == '/auth/me'
                  ? {
                      'id': request.headers['authorization']!.split(' ').last,
                      'username': 'user',
                      'display_name': 'name',
                      'quick_memories': []
                    }
                  : {'access_token': 'A'}),
              200)));
      final Future<Object?> pending = switch (operation) {
        'login' => api.login('A', 'password123'),
        'register' => api.register(
            username: 'Alice', password: 'password123', inviteCode: 'invite'),
        _ => api.fetchProfile(),
      };
      final outcome =
          pending.then<Object?>((_) => 'completed', onError: (Object e) => e);
      await tokens.started.future;
      final logout = api.logout();
      final newLogin = api.saveToken('B');
      tokens.release.complete();
      await Future.wait([logout, newLogin]);
      await api.fetchProfile();
      expect(await outcome, isA<ApiFailure>());
      expect(api.token, 'B');
      expect(tokens.token, 'B');
      expect(api.lastVerifiedUserId, 'B');
      expect(tokens.lastVerifiedUserId, 'B');
    });
  }

  test(
      'remote deletion invalidates in-flight sync before local purge awaits storage',
      () async {
    final pushStarted = Completer<void>();
    final pushResponse = Completer<http.Response>();
    final storage = DelayedStorage();
    final h = Harness(
        storage: storage,
        client: MockClient((request) async {
          if (request.method == 'DELETE')
            return http.Response('{"deleted":true}', 200);
          if (request.url.path == '/sync/push') {
            pushStarted.complete();
            return pushResponse.future;
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
    final sync = h.store.sync();
    await pushStarted.future;
    final gate = Completer<void>();
    storage.gate = gate;
    final deletion = h.store.deleteAccount('password');
    await storage.started.future;
    pushResponse.complete(http.Response(
        '{"accepted":[{"client_op_id":"offline-pending-A","entity_id":"offline-pending-A","server_version":99}],"conflicts":[],"server_version":99}',
        200));
    // Let the already issued response reach the pending purge boundary.
    await Future<void>.delayed(Duration.zero);
    gate.complete();
    expect(await deletion, isTrue);
    await sync;
    final deletedPartition = LocalRepository(storage).forUser('A');
    expect((await deletedPartition.load())!.transactions, isEmpty);
    expect(await deletedPartition.loadQueue(), isEmpty);
  });

  for (final status in [500, 200]) {
    test(
        'unconfirmed deletion response $status preserves all local records and credentials',
        () async {
      final h = Harness(client: MockClient((request) async {
        if (request.method == 'DELETE')
          return http.Response('{"deleted":false}', status);
        return http.Response(
            '{"id":"A","username":"Alice","display_name":"A","quick_memories":[]}',
            200);
      }));
      await h.login('A');
      await h.seed();
      expect(await h.store.deleteAccount('password'), isFalse);
      h.expectA();
      expect(h.api.token, 'A');
      expect(h.tokens.token, 'A');
    });
  }
}
