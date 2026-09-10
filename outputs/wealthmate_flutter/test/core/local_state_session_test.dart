import 'package:flutter_test/flutter_test.dart';
import 'package:wealthmate_flutter/core/database/local_state_session.dart';
import 'package:wealthmate_flutter/data/local_repository.dart';
import 'package:wealthmate_flutter/data/sync_queue.dart';

class _SessionMemoryStore implements KeyValueStore {
  final Map<String, String> values = <String, String>{};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }
}

void main() {
  test('serializes concurrent aggregate writes without losing updates',
      () async {
    final session = LocalStateSession(
      local: LocalRepository(_SessionMemoryStore()),
      queue: SyncQueue(),
    );

    final first = session.write(
      (state) => state.copyWith(currentMonth: '2026-09'),
    );
    final second = session.write(
      (state) => state.copyWith(defaultAccountId: 'a-2'),
    );
    await Future.wait([first, second]);

    final saved = await session.load();
    expect(saved?.currentMonth, '2026-09');
    expect(saved?.defaultAccountId, 'a-2');
  });

  test('persists a state mutation and its queued operation in one serial turn',
      () async {
    final session = LocalStateSession(
      local: LocalRepository(_SessionMemoryStore()),
      queue: SyncQueue(),
    );
    final operation = SyncOperation(
      clientOpId: 'op-1',
      entity: 'transactions',
      entityId: 'tx-1',
      type: SyncOperationType.upsert,
      payload: const {'id': 'tx-1'},
      createdAt: '2026-09-10T00:00:00Z',
    );

    await session.write(
      (state) => state.copyWith(currentMonth: '2026-09'),
      appendOperations: [operation],
    );

    expect((await session.load())?.currentMonth, '2026-09');
    expect((await session.pendingOperations()).single.clientOpId, 'op-1');
  });
}
