import 'package:flutter_test/flutter_test.dart';
import 'package:wealthmate_flutter/data/finance_repository.dart';
import 'package:wealthmate_flutter/data/local_repository.dart';
import 'package:wealthmate_flutter/data/sync_queue.dart';
import 'package:wealthmate_flutter/domain/models.dart';

class _MemoryStore implements KeyValueStore {
  final values = <String, String>{};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;
}

const _userA = 'phase1r-user-a';
const _userB = 'phase1r-user-b';

FinanceState _stateFor(String userId) => FinanceState(
      accounts: [
        Account(
          id: '$userId-account',
          name: '$userId account',
          type: AccountType.asset,
        ),
      ],
    );

SyncOperation _operationFor(String userId) => SyncOperation(
      clientOpId: '$userId-operation',
      entity: 'accounts',
      entityId: '$userId-account',
      type: SyncOperationType.upsert,
      payload: {'id': '$userId-account'},
    );

void main() {
  test('A to B to A restores isolated state and queued operations', () async {
    final storage = _MemoryStore();
    final repository = FinanceRepository(
      local: LocalRepository(storage),
      queue: SyncQueue(),
    );

    await repository.ensureLocalOwner(_userA);
    await repository.save(_stateFor(_userA));
    repository.queue.enqueue(_operationFor(_userA));
    await repository.persistQueue();

    await repository.ensureLocalOwner(_userB);
    expect((await repository.load())?.accounts, isEmpty);
    expect(repository.queue.pending(), isEmpty);

    await repository.save(_stateFor(_userB));
    repository.queue.enqueue(_operationFor(_userB));
    await repository.persistQueue();

    await repository.ensureLocalOwner(_userA);
    expect((await repository.load())?.accounts.single.id, '$_userA-account');
    expect(repository.queue.pending().single.clientOpId, '$_userA-operation');
  });
}
