import 'package:flutter_test/flutter_test.dart';
import 'package:wealthmate_flutter/core/database/local_state_session.dart';
import 'package:wealthmate_flutter/core/sync/sync_coordinator.dart';
import 'package:wealthmate_flutter/data/api_client.dart';
import 'package:wealthmate_flutter/data/local_repository.dart';
import 'package:wealthmate_flutter/data/sync_queue.dart';
import 'package:wealthmate_flutter/domain/models.dart';

class _MemoryStore implements KeyValueStore {
  final Map<String, String> values = {};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;
}

class _FakeSyncApi extends ApiClient {
  _FakeSyncApi() : super(baseUrl: 'http://sync-coordinator.test');

  int pushCalls = 0;
  int pullCalls = 0;
  int? pulledSince;

  @override
  Future<Map<String, Object?>> push(List<SyncOperation> operations) async {
    pushCalls++;
    return {
      'accepted': const <Object?>[],
      'conflicts': const <Object?>[],
      'server_version': 3,
    };
  }

  @override
  Future<PullResult> pullChanges(int sinceVersion) async {
    pullCalls++;
    pulledSince = sinceVersion;
    return const PullResult(
      transactions: [],
      accounts: [],
      categories: [],
      budgets: [],
      serverVersion: 3,
    );
  }
}

void main() {
  test('sync coordinator owns the push then pull lifecycle', () async {
    final local = LocalRepository(_MemoryStore());
    final session = LocalStateSession(local: local, queue: SyncQueue());
    final api = _FakeSyncApi();
    final coordinator = SyncCoordinator(
      session: session,
      api: api,
      isLocalOwnerBound: () => true,
    );

    final result = await coordinator.sync(const FinanceState());

    expect(api.pushCalls, 0);
    expect(api.pullCalls, 1);
    expect(api.pulledSince, 0);
    expect(result.syncState.serverVersion, 3);
    expect(await session.load(), result);
  });

  test('offline sync keeps the existing error contract', () async {
    final local = LocalRepository(_MemoryStore());
    final session = LocalStateSession(local: local, queue: SyncQueue());
    final coordinator = SyncCoordinator(
      session: session,
      api: null,
      isLocalOwnerBound: () => true,
    );

    final result = await coordinator.sync(const FinanceState());

    expect(result.syncState.error, '离线演示/待配置');
  });
}
