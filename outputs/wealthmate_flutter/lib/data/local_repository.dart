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
  LocalRepository(this.store, {this.userId});

  static const storageKey = 'wealthmate-finance-state-v1';
  static const queueStorageKey = 'wealthmate-sync-queue-v1';
  static const ownerStorageKey = 'wealthmate-local-owner-user-id-v1';
  static const legacyMigrationKey = 'wealthmate-legacy-partition-migration-v1';
  static const budgetAlertsKey = 'wealthmate-budget-alerts-v1';
  static const pendingAccountCleanupKey =
      'wealthmate-pending-account-cleanup-user-id-v1';
  static const pendingAccountCleanupBackupKey =
      'wealthmate-pending-account-cleanup-user-id-backup-v1';
  final KeyValueStore store;
  final String? userId;
  static final _writes = Expando<Map<String, Future<void>>>();
  static final _migrations = Expando<Future<void>>();

  LocalRepository forUser(String id) => LocalRepository(store, userId: id);

  String _partitionKey(String key, String id) =>
      '$key:user:${Uri.encodeComponent(id)}';

  Future<String> _key(String key) async {
    if (userId != null) return _partitionKey(key, userId!);
    if (await store.read(legacyMigrationKey) != null) {
      final owner = await loadOwnerUserId();
      if (owner != null) return _partitionKey(key, owner);
    }
    return key;
  }

  Future<void> _write(String key, String value) {
    return _serializedWrite(key, () => store.write(key, value));
  }

  Future<void> _serializedWrite(
      String key, Future<void> Function() action) {
    final pending = _writes[store] ??= {};
    final previous = pending[key] ?? Future<void>.value();
    final next = previous.then((_) => action());
    pending[key] = next.then<void>((_) {}, onError: (Object _) {});
    return next;
  }

  Future<String?> readMetadata(String key) async => store.read(await _key(key));

  Future<void> writeMetadata(String key, String value) async =>
      _write(await _key(key), value);

  Future<void> migrateLegacy() {
    final existing = _migrations[store];
    if (existing != null) return existing;
    final migration = _migrateLegacy();
    _migrations[store] = migration;
    migration.then<void>((_) {}, onError: (Object _) {
      _migrations[store] = null;
    });
    return migration;
  }

  Future<void> _migrateLegacy() async {
    if (await store.read(legacyMigrationKey) != null) return;
    final owner = await loadOwnerUserId();
    if (owner != null) {
      for (final key in [storageKey, queueStorageKey, budgetAlertsKey]) {
        final target = _partitionKey(key, owner);
        final raw = await store.read(key);
        if (raw != null && await store.read(target) == null) {
          await _write(target, raw);
        }
      }
    }
    // Unowned legacy bytes remain quarantined. Mark only after all copies finish.
    await _write(legacyMigrationKey, owner ?? '');
  }

  Future<void> purge() async {
    if (userId == null) throw StateError('A verified partition is required');
    await clearFinanceStateAndQueue();
    await writeMetadata(budgetAlertsKey, '[]');
    if (await store.read(legacyMigrationKey) == userId) {
      await _write(storageKey, '');
      await _write(queueStorageKey, '[]');
      await _write(budgetAlertsKey, '[]');
      await _write(legacyMigrationKey, '');
    }
    await _serializedWrite(ownerStorageKey, () async {
      if (await loadOwnerUserId() == userId) {
        await store.write(ownerStorageKey, '');
      }
    });
  }

  Future<String?> loadOwnerUserId() async {
    final raw = await store.read(ownerStorageKey);
    final owner = raw?.trim();
    return owner == null || owner.isEmpty ? null : owner;
  }

  Future<void> saveOwnerUserId(String userId) async {
    await _write(ownerStorageKey, userId.trim());
  }

  List<String> _decodePendingAccountCleanupValue(String value) {
    try {
      final decoded = jsonDecode(value);
      if (decoded is List) {
        return decoded
            .whereType<String>()
            .map((item) => item.trim())
            .where((item) => item.isNotEmpty)
            .toList(growable: false);
      }
    } on FormatException {
      // Read the single-value format from the first beta build.
    }
    return [value];
  }

  Future<List<String>> _readPendingAccountCleanupUserIds() async {
    final userIds = <String>{};
    for (final key in [
      pendingAccountCleanupKey,
      pendingAccountCleanupBackupKey,
    ]) {
      final raw = await store.read(key);
      final value = raw?.trim();
      if (value != null && value.isNotEmpty) {
        userIds.addAll(_decodePendingAccountCleanupValue(value));
      }
    }
    return userIds.toList(growable: false);
  }

  Future<List<String>> loadPendingAccountCleanupUserIds() async =>
      _readPendingAccountCleanupUserIds();

  Future<String?> loadPendingAccountCleanupUserId() async {
    final userIds = await loadPendingAccountCleanupUserIds();
    return userIds.isEmpty ? null : userIds.first;
  }

  Future<void> markPendingAccountCleanup(String userId) async {
    final normalizedUserId = userId.trim();
    if (normalizedUserId.isEmpty) return;
    await _serializedWrite(pendingAccountCleanupKey, () async {
      final userIds = await _readPendingAccountCleanupUserIds();
      if (userIds.contains(normalizedUserId)) return;
      final encoded = jsonEncode([...userIds, normalizedUserId]);
      Object? failure;
      var wrote = false;
      for (final key in [
        pendingAccountCleanupKey,
        pendingAccountCleanupBackupKey,
      ]) {
        try {
          await store.write(key, encoded);
          wrote = true;
        } catch (error) {
          failure ??= error;
        }
      }
      if (!wrote && failure != null) throw failure;
    });
  }

  Future<void> clearPendingAccountCleanup(String userId) async {
    final normalizedUserId = userId.trim();
    if (normalizedUserId.isEmpty) return;
    await _serializedWrite(pendingAccountCleanupKey, () async {
      final userIds = (await _readPendingAccountCleanupUserIds()).toList()
        ..remove(normalizedUserId);
      final encoded = userIds.isEmpty ? '' : jsonEncode(userIds);
      Object? failure;
      for (final key in [
        pendingAccountCleanupKey,
        pendingAccountCleanupBackupKey,
      ]) {
        try {
          await store.write(key, encoded);
        } catch (error) {
          failure ??= error;
        }
      }
      if (failure != null) throw failure;
    });
  }

  Future<void> clearFinanceStateAndQueue() async {
    await save(const FinanceState());
    await writeMetadata(queueStorageKey, jsonEncode(const <Object?>[]));
  }

  Future<FinanceState?> load() async {
    final raw = await readMetadata(storageKey);
    if (raw == null || raw.isEmpty) {
      return userId == null ? null : const FinanceState();
    }
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
    await writeMetadata(storageKey, jsonEncode(state.toJson()));
  }

  Future<List<SyncOperation>> loadQueue() async {
    final raw = await readMetadata(queueStorageKey);
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
    await writeMetadata(queueStorageKey, jsonEncode(queue.toJson()));
  }
}
