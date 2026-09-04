import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

part 'drift_database.g.dart';

class LocalAccounts extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get type => text()();
  TextColumn get accountKind => text().withDefault(const Constant('other'))();
  TextColumn get currency => text().withDefault(const Constant('CNY'))();
  RealColumn get openingBalance => real().withDefault(const Constant(0))();
  RealColumn get openingCnyAmount => real().nullable()();
  TextColumn get exchangeRateDate => text().nullable()();
  TextColumn get exchangeRateSource => text().nullable()();
  BoolColumn get isLiquid => boolean().withDefault(const Constant(false))();
  BoolColumn get isDefaultPayment =>
      boolean().withDefault(const Constant(false))();
  TextColumn get deletedAt => text().nullable()();
  IntColumn get serverVersion => integer().withDefault(const Constant(0))();
  TextColumn get updatedAt => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

class LocalTransactions extends Table {
  TextColumn get id => text()();
  TextColumn get date => text()();
  TextColumn get type => text()();
  RealColumn get amount => real()();
  TextColumn get currency => text().withDefault(const Constant('CNY'))();
  RealColumn get cnyAmount => real().nullable()();
  RealColumn get exchangeRate => real().nullable()();
  TextColumn get exchangeRateDate => text().nullable()();
  TextColumn get exchangeRateSource => text().nullable()();
  TextColumn get conversionStatus =>
      text().withDefault(const Constant('ready'))();
  TextColumn get categoryId => text().nullable()();
  TextColumn get accountId => text().nullable()();
  TextColumn get fromAccountId => text().nullable()();
  TextColumn get toAccountId => text().nullable()();
  TextColumn get occurredAt => text().nullable()();
  TextColumn get note => text().withDefault(const Constant(''))();
  TextColumn get clientOpId => text()();
  TextColumn get deletedAt => text().nullable()();
  IntColumn get serverVersion => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {id};
}

class LocalSyncOperations extends Table {
  TextColumn get clientOpId => text()();
  TextColumn get entity => text()();
  TextColumn get entityId => text()();
  TextColumn get type => text()();
  TextColumn get payload => text()();
  TextColumn get createdAt => text().nullable()();

  @override
  Set<Column> get primaryKey => {clientOpId};
}

class LocalMetadata extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};
}

class LocalBudgets extends Table {
  TextColumn get id => text()();
  TextColumn get month => text()();
  TextColumn get categoryId => text()();
  RealColumn get budgetLimit => real()();
  BoolColumn get active => boolean().withDefault(const Constant(true))();
  TextColumn get deletedAt => text().nullable()();
  IntColumn get serverVersion => integer().withDefault(const Constant(0))();
  TextColumn get updatedAt => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

@DriftDatabase(tables: [
  LocalAccounts,
  LocalTransactions,
  LocalSyncOperations,
  LocalMetadata,
  LocalBudgets
])
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (Migrator m) => m.createAll(),
        onUpgrade: (Migrator m, int from, int to) async {
          if (from < 2) {
            await m.addColumn(localAccounts, localAccounts.accountKind);
            await m.addColumn(localAccounts, localAccounts.isLiquid);
            await m.addColumn(localAccounts, localAccounts.isDefaultPayment);
            await m.addColumn(localAccounts, localAccounts.updatedAt);
            await m.addColumn(localTransactions, localTransactions.occurredAt);
            await m.createTable(localBudgets);
          }
        },
      );

  static Future<AppDatabase> open() async {
    final directory = await getApplicationDocumentsDirectory();
    return AppDatabase(NativeDatabase.createInBackground(
        File(p.join(directory.path, 'wealthmate.sqlite'))));
  }
}
