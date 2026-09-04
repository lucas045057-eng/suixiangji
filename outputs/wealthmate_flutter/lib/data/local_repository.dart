import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/models.dart';
import 'drift_database.dart';
import 'sync_queue.dart';

abstract class KeyValueStore {
  Future<String?> read(String key);

  Future<void> write(String key, String value);
}

class SharedPreferencesKeyValueStore implements KeyValueStore {
  SharedPreferencesKeyValueStore(this.preferences);

  final SharedPreferences preferences;

  @override
  Future<String?> read(String key) async => preferences.getString(key);

  @override
  Future<void> write(String key, String value) async {
    await preferences.setString(key, value);
  }
}

class DriftKeyValueStore implements KeyValueStore {
  DriftKeyValueStore(this.database);

  final AppDatabase database;

  @override
  Future<String?> read(String key) async {
    final row = await (database.select(database.localMetadata)
          ..where((item) => item.key.equals(key)))
        .getSingleOrNull();
    return row?.value;
  }

  @override
  Future<void> write(String key, String value) async {
    await database.into(database.localMetadata).insertOnConflictUpdate(
        LocalMetadataCompanion.insert(key: key, value: value));
  }
}

class LocalRepository {
  LocalRepository(this.store);

  static const storageKey = 'wealthmate-finance-state-v1';
  static const queueStorageKey = 'wealthmate-sync-queue-v1';
  final KeyValueStore store;

  Future<FinanceState?> load() async {
    final raw = await store.read(storageKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw) as Map;
      return FinanceState.fromJson(decoded.cast<String, Object?>());
    } on FormatException {
      return null;
    } on TypeError {
      return null;
    }
  }

  Future<void> save(FinanceState state) async {
    await store.write(storageKey, jsonEncode(state.toJson()));
  }

  Future<List<SyncOperation>> loadQueue() async {
    final raw = await store.read(queueStorageKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw) as List;
      return decoded
          .map((item) =>
              SyncOperation.fromJson((item as Map).cast<String, Object?>()))
          .toList();
    } on FormatException {
      return [];
    } on TypeError {
      return [];
    }
  }

  Future<void> saveQueue(SyncQueue queue) async {
    await store.write(queueStorageKey, jsonEncode(queue.toJson()));
  }
}
