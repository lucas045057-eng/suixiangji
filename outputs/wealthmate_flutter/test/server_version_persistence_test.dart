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

class MemoryKeyValueStore implements KeyValueStore {
  final Map<String, String> values = {};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;
}

class RecordingPullClient extends http.BaseClient {
  RecordingPullClient({this.remoteServerVersion = 50});

  final int remoteServerVersion;
  final List<int> requestedSinceVersions = [];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request.url.path != '/sync/pull') {
      return _jsonResponse(404, {'error': 'unexpected path'}, request);
    }
    requestedSinceVersions
        .add(int.parse(request.url.queryParameters['since_version']!));
    return _jsonResponse(
        200,
        {
          'items': const <Object?>[],
          'accounts': const <Object?>[],
          'categories': const <Object?>[],
          'budgets': const <Object?>[],
          'server_version': remoteServerVersion,
        },
        request);
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

FinanceRepository repositoryWithApi(
    {required LocalRepository local,
    required SyncQueue queue,
    required RecordingPullClient client}) {
  return FinanceRepository(
    local: local,
    queue: queue,
    api: ApiClient(
      baseUrl: 'http://server-version.test',
      token: 'server-version-test-token',
      client: client,
    ),
  );
}

void main() {
  test('finance state JSON round trip preserves server version', () {
    const state = FinanceState(
      syncState: SyncState(serverVersion: 123),
    );

    final restored = FinanceState.fromJson(state.toJson());

    expect(restored.syncState.serverVersion, 123);
  });

  test('old finance state JSON without sync state defaults to zero', () {
    final restored = FinanceState.fromJson(<String, Object?>{});

    expect(restored.syncState.serverVersion, 0);
  });

  test('local repository restart preserves server version', () async {
    final directory =
        await Directory.systemTemp.createTemp('suixiangji-server-version-');
    final file =
        File('${directory.path}${Platform.pathSeparator}server-version.sqlite');
    AppDatabase? firstDatabase;
    AppDatabase? restartedDatabase;
    try {
      firstDatabase = AppDatabase(NativeDatabase(file));
      final firstRepository = FinanceRepository(
        local: LocalRepository(DriftKeyValueStore(firstDatabase)),
        queue: SyncQueue(),
      );
      await firstRepository.save(const FinanceState(
        syncState: SyncState(serverVersion: 321),
      ));
      await firstDatabase.close();
      firstDatabase = null;

      restartedDatabase = AppDatabase(NativeDatabase(file));
      final restartedRepository = FinanceRepository(
        local: LocalRepository(DriftKeyValueStore(restartedDatabase)),
        queue: SyncQueue(),
      );
      final restored = await restartedRepository.load();

      expect(restored?.syncState.serverVersion, 321);
    } finally {
      await firstDatabase?.close();
      await restartedDatabase?.close();
      await directory.delete(recursive: true);
    }
  });

  test('app restart uses the restored server version for incremental pull',
      () async {
    final directory =
        await Directory.systemTemp.createTemp('suixiangji-server-version-');
    final file =
        File('${directory.path}${Platform.pathSeparator}incremental.sqlite');
    AppDatabase? firstDatabase;
    AppDatabase? restartedDatabase;
    final client = RecordingPullClient();
    try {
      firstDatabase = AppDatabase(NativeDatabase(file));
      final firstRepository = repositoryWithApi(
        local: LocalRepository(DriftKeyValueStore(firstDatabase)),
        queue: SyncQueue(),
        client: client,
      );
      final firstState =
          await firstRepository.pullChanges(const FinanceState());
      expect(firstState.syncState.serverVersion, 50);
      await firstDatabase.close();
      firstDatabase = null;

      restartedDatabase = AppDatabase(NativeDatabase(file));
      final restartedRepository = repositoryWithApi(
        local: LocalRepository(DriftKeyValueStore(restartedDatabase)),
        queue: SyncQueue(),
        client: client,
      );
      final restored = await restartedRepository.load();
      await restartedRepository.pullChanges(restored!);

      expect(client.requestedSinceVersions, [0, 50]);
    } finally {
      await firstDatabase?.close();
      await restartedDatabase?.close();
      await directory.delete(recursive: true);
    }
  });

  test('fresh online client starts incremental state at server version zero',
      () async {
    final client = RecordingPullClient();
    final repository = repositoryWithApi(
      local: LocalRepository(MemoryKeyValueStore()),
      queue: SyncQueue(),
      client: client,
    );
    final store = FinanceStore(repository: repository);

    expect(store.state.syncState.serverVersion, 0);
    await store.sync();

    expect(client.requestedSinceVersions, [0]);
  });
}
