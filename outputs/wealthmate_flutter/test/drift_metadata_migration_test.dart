import 'dart:io';

import 'package:drift/drift.dart'
    show OpeningDetails, QueryExecutor, QueryExecutorUser;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wealthmate_flutter/data/drift_database.dart';

class _LegacyDatabaseUser implements QueryExecutorUser {
  @override
  int get schemaVersion => 2;

  @override
  Future<void> beforeOpen(
    QueryExecutor executor,
    OpeningDetails details,
  ) async {}
}

void main() {
  test('schema 3 drops unused tables and preserves metadata', () async {
    final directory =
        await Directory.systemTemp.createTemp('suixiangji-drift-v3-');
    final file = File('${directory.path}/legacy.sqlite');
    final legacyExecutor = NativeDatabase(
      file,
      enableMigrations: false,
      setup: (database) {
        database.execute('CREATE TABLE local_accounts (id TEXT PRIMARY KEY);');
        database
            .execute('CREATE TABLE local_transactions (id TEXT PRIMARY KEY);');
        database.execute(
            'CREATE TABLE local_sync_operations (client_op_id TEXT PRIMARY KEY);');
        database.execute(
            'CREATE TABLE local_metadata (`key` TEXT PRIMARY KEY, `value` TEXT NOT NULL);');
        database.execute('CREATE TABLE local_budgets (id TEXT PRIMARY KEY);');
        database.execute(
            "INSERT INTO local_metadata (`key`, `value`) VALUES ('keep-me', 'still here');");
        database.userVersion = 2;
      },
    );
    await legacyExecutor.ensureOpen(_LegacyDatabaseUser());
    await legacyExecutor.close();

    final database = AppDatabase(NativeDatabase(file));
    try {
      final metadata = await database.select(database.localMetadata).get();
      expect(metadata, hasLength(1));
      expect(metadata.single.key, 'keep-me');
      expect(metadata.single.value, 'still here');

      final oldTables = await database.customSelect(
        '''
        SELECT name
        FROM sqlite_master
        WHERE type = 'table'
          AND name IN (
            'local_accounts',
            'local_transactions',
            'local_sync_operations',
            'local_budgets'
          )
        ''',
      ).get();
      expect(oldTables, isEmpty);

      final version =
          await database.customSelect('PRAGMA user_version').getSingle();
      expect(version.read<int>('user_version'), 3);
    } finally {
      await database.close();
      await directory.delete(recursive: true);
    }
  });
}
