import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

part 'drift_database.g.dart';

class LocalMetadata extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};
}

@DriftDatabase(tables: [LocalMetadata])
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  @override
  int get schemaVersion => 3;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (Migrator m) => m.createAll(),
        onUpgrade: (Migrator m, int from, int to) async {
          if (from < 3) {
            // Earlier releases kept finance data in localMetadata; these
            // normalized tables were never used and can be removed safely.
            await customStatement('DROP TABLE IF EXISTS local_accounts');
            await customStatement('DROP TABLE IF EXISTS local_transactions');
            await customStatement('DROP TABLE IF EXISTS local_sync_operations');
            await customStatement('DROP TABLE IF EXISTS local_budgets');
          }
        },
      );

  static Future<AppDatabase> open() async {
    final directory = await getApplicationDocumentsDirectory();
    return AppDatabase(NativeDatabase.createInBackground(
        File(p.join(directory.path, 'wealthmate.sqlite'))));
  }
}
