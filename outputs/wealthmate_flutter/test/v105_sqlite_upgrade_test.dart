import 'dart:convert';
import 'dart:io';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wealthmate_flutter/core/database/local_state_session.dart';
import 'package:wealthmate_flutter/data/drift_database.dart';
import 'package:wealthmate_flutter/data/local_repository.dart';
import 'package:wealthmate_flutter/data/sync_queue.dart';
import 'package:wealthmate_flutter/domain/models.dart';

void main() {
  test(
      'old SQLite JSON and offline operation retain IDs, amount and cursor through V105 reopen',
      () async {
    final directory =
        await Directory.systemTemp.createTemp('suixiangji-v105-upgrade-');
    final file = File('${directory.path}/old.sqlite');
    var db = AppDatabase(NativeDatabase(file));
    var kv = DriftKeyValueStore(db);
    const old = FinanceState(
        currentMonth: '2026-09',
        accounts: [
          Account(
              id: 'a',
              name: '卡',
              type: AccountType.asset,
              openingBalance: 123,
              serverVersion: 40)
        ],
        transactions: [
          FinanceTransaction(
              id: 'old',
              date: '2026-09-01',
              type: TransactionType.expense,
              amount: 16,
              accountId: 'a',
              clientOpId: 'original-op',
              serverVersion: 42)
        ],
        syncState: SyncState(serverVersion: 42));
    final json = old.toJson()
      ..remove('preferred_currency')
      ..remove('common_currencies');
    final account = (json['accounts'] as List).first as Map;
    account.remove('note');
    account.remove('archived_at');
    await kv.write(LocalRepository.storageKey, jsonEncode(json));
    await kv.write(
        LocalRepository.queueStorageKey,
        jsonEncode([
          SyncOperation(
                  clientOpId: 'offline-op',
                  entity: 'transactions',
                  entityId: 'old',
                  type: SyncOperationType.upsert,
                  payload: old.transactions.single.toJson())
              .toJson()
        ]));
    await db.close();
    db = AppDatabase(NativeDatabase(file));
    kv = DriftKeyValueStore(db);
    final local = LocalRepository(kv), queue = SyncQueue();
    final session = LocalStateSession(local: local, queue: queue);
    final loaded = (await session.load())!;
    expect(loaded.preferredCurrency, 'CNY');
    expect(loaded.accounts.single.note, '');
    expect(loaded.transactions.single.clientOpId, 'original-op');
    expect(loaded.transactions.single.amount, 16);
    expect(loaded.syncState.serverVersion, 42);
    expect(queue.pending().single.clientOpId, 'offline-op');
    await session.write((s) => s.copyWith(preferredCurrency: 'HKD'));
    await db.close();
    db = AppDatabase(NativeDatabase(file));
    final reopened = LocalRepository(DriftKeyValueStore(db));
    expect((await reopened.load())!.preferredCurrency, 'HKD');
    expect((await reopened.loadQueue()).single.clientOpId, 'offline-op');
    await db.close();
    await directory.delete(recursive: true);
  });
  test(
      'queue persistence failure rolls back financial state and in-memory queue atomically',
      () async {
    final db = AppDatabase(NativeDatabase.memory());
    final local = LocalRepository(DriftKeyValueStore(db));
    await local.save(const FinanceState(currentMonth: '2026-09'));
    await local.saveQueue(SyncQueue());
    await db.customStatement(
        "CREATE TRIGGER fail_queue BEFORE INSERT ON local_metadata WHEN NEW.key = '${LocalRepository.queueStorageKey}' BEGIN SELECT RAISE(FAIL, 'synthetic queue failure'); END");
    final queue = SyncQueue();
    final session = LocalStateSession(local: local, queue: queue);
    await expectLater(
        session.write((s) => s.copyWith(currentMonth: '2026-10'),
            appendOperations: [
              const SyncOperation(
                  clientOpId: 'new',
                  entity: 'accounts',
                  entityId: 'a',
                  type: SyncOperationType.upsert,
                  payload: {'name': '卡'})
            ]),
        throwsA(anything));
    expect((await local.load())!.currentMonth, '2026-09');
    expect(queue.pending(), isEmpty);
    await db.close();
  });
}
