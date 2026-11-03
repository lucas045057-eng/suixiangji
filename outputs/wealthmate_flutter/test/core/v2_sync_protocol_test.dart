import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:wealthmate_flutter/core/database/local_state_session.dart';
import 'package:wealthmate_flutter/core/network/api_transport.dart';
import 'package:wealthmate_flutter/core/sync/sync_coordinator.dart';
import 'package:wealthmate_flutter/core/sync/sync_protocol.dart';
import 'package:wealthmate_flutter/core/sync/sync_remote_data_source.dart';
import 'package:wealthmate_flutter/data/api_client.dart';
import 'package:wealthmate_flutter/data/finance_repository.dart';
import 'package:wealthmate_flutter/data/local_repository.dart';
import 'package:wealthmate_flutter/data/sync_queue.dart';
import 'package:wealthmate_flutter/data/token_store.dart';
import 'package:wealthmate_flutter/domain/models.dart';
import 'package:wealthmate_flutter/features/assets/data/assets_repository.dart';
import 'package:wealthmate_flutter/features/ledger/data/ledger_repository.dart';
import 'package:wealthmate_flutter/state/finance_store.dart';

class _MemoryStore implements KeyValueStore {
  final Map<String, String> values = {};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;
}

class _MemoryTokenStore implements TokenStore {
  String? value;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String token) async => value = token;

  @override
  Future<void> clear() async => value = null;

  @override
  Future<String?> readLastVerifiedUserId() async => null;

  @override
  Future<void> writeLastVerifiedUserId(String userId) async {}

  @override
  Future<void> clearLastVerifiedUserId() async {}
}

class _ScriptedApi extends ApiClient {
  _ScriptedApi({PullResult? pull})
      : pullResult = pull ??
            const PullResult(
              transactions: [],
              accounts: [],
              categories: [],
              budgets: [],
              serverVersion: 100,
            ),
        super(
          baseUrl: 'http://v2.test',
          token: 'token',
          client: MockClient((_) async => http.Response('{}', 200)),
          tokenStore: _MemoryTokenStore(),
        );

  Future<Map<String, Object?>> Function(List<SyncOperation>)? onPush;
  PullResult pullResult;
  int pushCalls = 0;
  int pullCalls = 0;
  int? pulledSince;
  List<SyncOperation> lastPushed = const [];

  @override
  Future<Map<String, Object?>> push(List<SyncOperation> operations) async {
    pushCalls++;
    lastPushed = List.unmodifiable(operations);
    final handler = onPush;
    if (handler == null) {
      return {
        'accepted': const <Object?>[],
        'conflicts': const <Object?>[],
        'server_version': 1,
      };
    }
    return handler(operations);
  }

  @override
  Future<PullResult> pullChanges(int sinceVersion) async {
    pullCalls++;
    pulledSince = sinceVersion;
    return pullResult;
  }
}

LocalStateSession _session() {
  return LocalStateSession(
    local: LocalRepository(_MemoryStore()),
    queue: SyncQueue(),
  );
}

SyncCoordinator _coordinator(LocalStateSession session, ApiClient api) {
  return SyncCoordinator(
    session: session,
    api: api,
    isLocalOwnerBound: () => true,
  );
}

Account _cash({int? serverVersion, String name = '现金'}) => Account(
      id: 'cash',
      name: name,
      type: AccountType.asset,
      serverVersion: serverVersion,
    );

Map<String, Object?> _v2Success(List<SyncOperation> operations,
        {int version = 12}) =>
    {
      'results': [
        for (final operation in operations)
          {
            'op_id': operation.clientOpId,
            'entity': operation.entity,
            'id': operation.entityId,
            'status': 'applied',
            'fields_applied': const <Object?>[],
            'row': operation.entity == 'user_preferences'
                ? {
                    'id': 'self',
                    'default_account_id': 'cash',
                    'server_version': version,
                    'updated_at': '2026-11-03T07:00:00',
                  }
                : operation.entity == 'transactions'
                    ? {
                        ...operation.payload,
                        'server_version': version,
                      }
                    : operation.entity == 'categories'
                        ? {
                            ...operation.payload,
                            'server_version': version,
                          }
                        : _cash(serverVersion: version).toJson(),
          },
      ],
      'rejected': const <Object?>[],
      'conflicts': const <Object?>[],
      'server_version': version,
    };

void main() {
  group('V2 request envelope', () {
    test('account updates carry base_version and the previous field snapshot',
        () async {
      final session = _session();
      final repository = AssetsRepository(session: session);
      final state = FinanceState(
        accounts: [_cash(serverVersion: 7)],
        syncState: const SyncState(serverVersion: 10),
      );

      await repository.saveAccount(_cash(serverVersion: 7, name: '钱包'),
          baseState: state);

      final operation = session.queue.pending().single;
      expect(operation.entity, 'accounts');
      expect(operation.baseVersion, 7);
      expect(operation.base?['name'], '现金');
      // The default flag is a read-only projection; never send it.
      expect(operation.payload.containsKey('is_default_payment'), isFalse);
    });

    test('a create without an authoritative baseline fabricates nothing',
        () async {
      final session = _session();
      final repository = AssetsRepository(session: session);

      await repository.saveAccount(_cash(name: '现金'),
          baseState: const FinanceState());

      final operation = session.queue.pending().single;
      expect(operation.base, isNull);
      expect(operation.baseVersion, isNull);
    });

    test('setting the default account writes the preference singleton',
        () async {
      final session = _session();
      final repository = AssetsRepository(session: session);
      final state = FinanceState(
        accounts: [_cash(serverVersion: 7)],
        preference:
            const UserPreference(defaultAccountId: 'other', serverVersion: 4),
      );

      final next = await repository.setDefaultAccount('cash', baseState: state);

      final operation = session.queue.pending().single;
      expect(operation.entity, 'user_preferences');
      expect(operation.entityId, UserPreference.singletonId);
      expect(operation.payload, {'default_account_id': 'cash'});
      expect(operation.baseVersion, 4);
      expect(operation.base?['default_account_id'], 'other');
      expect(next.defaultAccountId, 'cash');
      expect(next.accounts.single.isDefaultPayment, isTrue);
    });
  });

  group('V2 push outcomes', () {
    test('rejected drains the queue, rolls back only that op and keeps going',
        () async {
      final session = _session();
      final assets = AssetsRepository(session: session);
      final ledger = LedgerRepository(session: session);
      var state = FinanceState(
        accounts: [_cash(serverVersion: 7)],
        syncState: const SyncState(serverVersion: 10),
      );
      await assets.saveAccount(_cash(serverVersion: 7, name: '钱包'),
          baseState: state);
      state = (await session.load())!;
      const transaction = FinanceTransaction(
        id: 'tx-1',
        date: '2026-11-03',
        type: TransactionType.expense,
        amount: 12,
        accountId: 'cash',
        clientOpId: 'tx-1',
      );
      await ledger.saveTransaction(transaction, baseState: state);
      final before = (await session.load())!;
      final operations = session.queue.pending();
      expect(
          operations.map((item) => item.entity), ['accounts', 'transactions']);

      final api = _ScriptedApi();
      api.onPush = (sent) async => {
            'server_version': 11,
            'results': [
              {
                'op_id': sent[0].clientOpId,
                'entity': 'accounts',
                'id': 'cash',
                'status': 'rejected',
              },
              {
                'op_id': sent[1].clientOpId,
                'entity': 'transactions',
                'id': 'tx-1',
                'status': 'applied',
                'fields_applied': ['amount'],
                'row': transaction.copyWith(serverVersion: 11).toJson(),
              },
            ],
            'rejected': [
              {
                'op_id': sent[0].clientOpId,
                'entity': 'accounts',
                'id': 'cash',
                'code': 'invalid_field',
                'detail': 'Input should be asset or liability',
                'field': 'kind',
              },
            ],
            'conflicts': const <Object?>[],
          };

      final result = await _coordinator(session, api).pushPending(before);

      expect(session.queue.pending(), isEmpty);
      expect(result.accounts.single.name, '现金');
      expect(result.transactions.single.serverVersion, 11);
      expect(result.syncIssues, hasLength(1));
      expect(result.syncIssues.single.code, 'invalid_field');
      expect(result.syncIssues.single.userMessage, contains('已跳过'));
    });

    test('field_conflicts keeps the merged server row without an issue',
        () async {
      final session = _session();
      final assets = AssetsRepository(session: session);
      final state = FinanceState(
        accounts: [_cash(serverVersion: 7)],
        syncState: const SyncState(serverVersion: 10),
      );
      final edited = _cash(serverVersion: 7, name: '钱包')
          .copyWith(note: '随身', isLiquid: true);
      await assets.saveAccount(edited, baseState: state);
      final before = (await session.load())!;
      final operation = session.queue.pending().single;

      final serverRow = _cash(serverVersion: 8, name: '现金账户')
          .copyWith(note: '随身', isLiquid: true)
          .toJson();
      final api = _ScriptedApi();
      api.onPush = (_) async => {
            'server_version': 11,
            'results': [
              {
                'op_id': operation.clientOpId,
                'entity': 'accounts',
                'id': 'cash',
                'status': 'merged',
                'fields_applied': ['note'],
                'field_conflicts': [
                  {
                    'field': 'name',
                    'base': '现金',
                    'client': '钱包',
                    'server': '现金账户'
                  },
                ],
                'row': serverRow,
              },
            ],
            'rejected': const <Object?>[],
            'conflicts': const <Object?>[],
          };

      final result = await _coordinator(session, api).pushPending(before);

      expect(session.queue.pending(), isEmpty);
      expect(result.accounts.single.name, '现金账户');
      expect(result.accounts.single.note, '随身');
      expect(result.accounts.single.serverVersion, 8);
      expect(result.syncIssues, isEmpty);
      expect(result.conflicts, isEmpty);
    });

    test('conflicts adopts the authoritative row and records an issue',
        () async {
      final session = _session();
      final assets = AssetsRepository(session: session);
      final state = FinanceState(
        accounts: [_cash(serverVersion: 7)],
        syncState: const SyncState(serverVersion: 10),
      );
      await assets.saveAccount(_cash(serverVersion: 7, name: '钱包'),
          baseState: state);
      final before = (await session.load())!;
      final operation = session.queue.pending().single;

      final api = _ScriptedApi();
      api.onPush = (_) async => {
            'server_version': 12,
            'results': const <Object?>[],
            'rejected': const <Object?>[],
            'conflicts': [
              {
                'op_id': operation.clientOpId,
                'entity': 'accounts',
                'id': 'cash',
                'reason': 'version_conflict',
                'authoritative_row':
                    _cash(serverVersion: 12, name: '现金账户').toJson(),
              },
            ],
          };

      final result = await _coordinator(session, api).pushPending(before);

      expect(session.queue.pending(), isEmpty);
      expect(result.accounts.single.name, '现金账户');
      expect(result.accounts.single.serverVersion, 12);
      expect(result.syncIssues.single.code, 'version_conflict');
      expect(result.syncIssues.single.userMessage, contains('采用服务器版本'));
    });

    test('balance_changed conflict drops the optimistic adjustment', () async {
      final session = _session();
      const optimistic = FinanceTransaction(
        id: 'adj-local',
        date: '2026-11-03',
        type: TransactionType.adjustment,
        amount: 10,
        accountId: 'cash',
        clientOpId: 'cal-1',
      );
      final state = FinanceState(
        transactions: [optimistic],
        syncState: const SyncState(serverVersion: 10),
      );
      await session.mutateQueue((queue) => queue.enqueue(SyncOperation(
            clientOpId: 'cal-1',
            entity: 'transactions',
            entityId: 'adj-local',
            type: SyncOperationType.upsert,
            payload: optimistic.toJson(),
            createdAt: '2026-11-03T10:00:00Z',
          )));

      final api = _ScriptedApi();
      api.onPush = (_) async => {
            'server_version': 12,
            'results': const <Object?>[],
            'rejected': const <Object?>[],
            'conflicts': [
              {
                'op_id': 'cal-1',
                'entity': 'transactions',
                'id': 'adj-local',
                'reason': 'balance_changed',
                'authoritative_row': null,
              },
            ],
          };

      final result = await _coordinator(session, api).pushPending(state);

      expect(session.queue.pending(), isEmpty);
      expect(result.transactions, isEmpty);
      expect(result.syncIssues.single.code, 'balance_changed');
      expect(result.syncIssues.single.userMessage, contains('重新核对校准'));
    });
  });

  group('426 upgrade gate', () {
    test('transport parses min_protocol and explains the upgrade', () async {
      final client = MockClient((request) async => http.Response(
          jsonEncode({'code': 'upgrade_required', 'min_protocol': 3}), 426));
      final transport = ApiTransport(
        baseUrl: 'http://v2.test',
        client: client,
        tokenProvider: () => 'token',
      );

      await expectLater(
        transport.requestMap('POST', '/sync/push', body: const {}),
        throwsA(predicate((error) =>
            error is ApiFailure &&
            error.kind == ApiFailureKind.upgradeRequired &&
            error.minProtocol == 3 &&
            error.message.contains('v3'))),
      );
    });

    test('a 426 without min_protocol keeps the requirement unknown', () async {
      final client = MockClient((request) async =>
          http.Response(jsonEncode({'code': 'upgrade_required'}), 426));
      final transport = ApiTransport(
        baseUrl: 'http://v2.test',
        client: client,
        tokenProvider: () => 'token',
      );

      await expectLater(
        transport.requestMap('POST', '/sync/push', body: const {}),
        throwsA(predicate((error) =>
            error is ApiFailure &&
            error.kind == ApiFailureKind.upgradeRequired &&
            error.minProtocol == null &&
            error.clientNeedsUpgrade &&
            error.message.contains('未提供具体版本') &&
            !error.message.contains('null'))),
      );
    });

    test('coordinator persists an unknown requirement without a version',
        () async {
      final session = _session();
      final assets = AssetsRepository(session: session);
      final state = FinanceState(
        accounts: [_cash(serverVersion: 7)],
        syncState: const SyncState(serverVersion: 10),
      );
      await assets.saveAccount(_cash(serverVersion: 7, name: '钱包'),
          baseState: state);
      final before = (await session.load())!;

      final api = _ScriptedApi();
      api.onPush = (_) async => throw ApiFailure(
            ApiFailureKind.upgradeRequired,
            syncUpgradeMessage(null),
            statusCode: 426,
            code: 'upgrade_required',
          );

      final result = await _coordinator(session, api).pushPending(before);

      expect(result.syncState.upgradeRequiredProtocol, isNull);
      expect(result.syncState.upgradeRequiredWithoutVersion, isTrue);
      expect(result.syncState.needsUpgrade, isTrue);
      expect(result.syncState.requiresUpgrade(kSupportedSyncProtocolVersion),
          isTrue);
      expect(result.syncState.error, contains('未提供具体版本'));
      expect(result.syncState.error, isNot(contains('null')));
      expect(result.syncState.upgradeRequirementLabel, isNot(contains('null')));
      expect(session.queue.pending(), hasLength(1));

      // The unknown gate is sticky across an aggregate restart too.
      final restored = FinanceState.fromJson(result.toJson());
      expect(restored.syncState.upgradeRequiredWithoutVersion, isTrue);
      expect(restored.syncState.upgradeRequiredProtocol, isNull);
      expect(restored.syncState.needsUpgrade, isTrue);
      expect(restored.syncState.requiresUpgrade(kSupportedSyncProtocolVersion),
          isTrue);
    });

    test('coordinator persists the gate and keeps the pending queue', () async {
      final session = _session();
      final assets = AssetsRepository(session: session);
      final state = FinanceState(
        accounts: [_cash(serverVersion: 7)],
        syncState: const SyncState(serverVersion: 10),
      );
      await assets.saveAccount(_cash(serverVersion: 7, name: '钱包'),
          baseState: state);
      final before = (await session.load())!;

      final api = _ScriptedApi();
      api.onPush = (_) async => throw const ApiFailure(
            ApiFailureKind.upgradeRequired,
            '客户端协议版本过低，请升级到支持协议 v3 的版本后再同步',
            statusCode: 426,
            code: 'upgrade_required',
            minProtocol: 3,
          );

      final result = await _coordinator(session, api).pushPending(before);

      expect(result.syncState.needsUpgrade, isTrue);
      expect(result.syncState.upgradeRequiredProtocol, 3);
      expect(result.syncState.error, contains('v3'));
      expect(session.queue.pending(), hasLength(1));
    });

    test('FinanceStore stops automatic retries and allows an explicit retry',
        () async {
      final api = _ScriptedApi();
      api.onPush = (operations) async {
        if (api.pushCalls == 1) {
          throw const ApiFailure(
            ApiFailureKind.upgradeRequired,
            '客户端协议版本过低，请升级到支持协议 v3 的版本后再同步',
            statusCode: 426,
            code: 'upgrade_required',
            minProtocol: 3,
          );
        }
        return {
          'results': [
            for (final operation in operations)
              {
                'op_id': operation.clientOpId,
                'entity': operation.entity,
                'id': operation.entityId,
                'status': 'applied',
                'fields_applied': const <Object?>[],
                'row': operation.entity == 'user_preferences'
                    ? {
                        'id': 'self',
                        'default_account_id': 'cash',
                        'server_version': 12,
                        'updated_at': '2026-11-03T07:00:00',
                      }
                    : _cash(serverVersion: 12).toJson(),
              },
          ],
          'rejected': const <Object?>[],
          'conflicts': const <Object?>[],
          'server_version': 12,
        };
      };
      final repository = FinanceRepository(
        local: LocalRepository(_MemoryStore()),
        queue: SyncQueue(),
        api: api,
      );
      await repository.ensureLocalOwner('user');
      repository.queue.enqueue(SyncOperation(
        clientOpId: 'account-1',
        entity: 'accounts',
        entityId: 'cash',
        type: SyncOperationType.upsert,
        payload: _cash(serverVersion: 7).toJson(),
        createdAt: '2026-11-03T07:00:00Z',
        baseVersion: 7,
        base: _cash(serverVersion: 7).toJson(),
      ));
      final store = FinanceStore(
        repository: repository,
        initialState: FinanceState(
          accounts: [_cash(serverVersion: 7)],
          syncState: const SyncState(serverVersion: 10),
        ),
      );

      await store.sync();
      expect(store.state.syncState.needsUpgrade, isTrue);
      expect(api.pushCalls, 1);

      // A normal local mutation must not wake the gated pipeline.
      await store.assets.setDefaultAccount('cash');
      await Future<void>.delayed(const Duration(milliseconds: 350));
      expect(api.pushCalls, 1);

      // The explicit retry is the escape hatch.
      await store.sync();
      expect(api.pushCalls, 2);
      expect(store.state.syncState.needsUpgrade, isFalse);
    });
  });

  group('user_preferences', () {
    test('pull adopts the singleton preference and its projection', () async {
      final session = _session();
      final state = FinanceState(
        accounts: [_cash(serverVersion: 7)],
        syncState: const SyncState(serverVersion: 10),
      );
      final api = _ScriptedApi(
        pull: const PullResult(
          transactions: [],
          accounts: [],
          categories: [],
          budgets: [],
          preference:
              UserPreference(defaultAccountId: 'cash', serverVersion: 11),
          serverVersion: 11,
        ),
      );

      final result = await _coordinator(session, api).pullChanges(state);

      expect(result.preference?.defaultAccountId, 'cash');
      expect(result.defaultAccountId, 'cash');
      expect(result.accounts.single.isDefaultPayment, isTrue);
    });

    test('an empty preferences list is "not established yet", not cleared',
        () async {
      final session = _session();
      final state = FinanceState(
        accounts: [_cash(serverVersion: 7)],
        syncState: const SyncState(serverVersion: 10),
      );
      final api = _ScriptedApi(
        pull: const PullResult(
          transactions: [],
          accounts: [],
          categories: [],
          budgets: [],
          serverVersion: 10,
        ),
      );

      final result = await _coordinator(session, api).pullChanges(state);

      expect(result.preference, isNull);
      expect(result.defaultAccountId, isNull);
    });

    test('a pending preference op protects the newer local intent', () async {
      final session = _session();
      final state = FinanceState(
        accounts: [_cash(serverVersion: 7)],
        defaultAccountId: 'cash',
        preference: const UserPreference(serverVersion: 5),
        syncState: const SyncState(serverVersion: 10),
      );
      await session.mutateQueue((queue) => queue.enqueue(const SyncOperation(
            clientOpId: 'preference-1',
            entity: 'user_preferences',
            entityId: UserPreference.singletonId,
            type: SyncOperationType.upsert,
            payload: {'default_account_id': 'cash'},
          )));
      final api = _ScriptedApi(
        pull: const PullResult(
          transactions: [],
          accounts: [],
          categories: [],
          budgets: [],
          preference: UserPreference(serverVersion: 11),
          serverVersion: 11,
        ),
      );

      final result = await _coordinator(session, api).pullChanges(state);

      expect(result.defaultAccountId, 'cash');
      expect(result.preference?.defaultAccountId, isNull);
    });

    test('pull parses preferences and treats [] as no row', () async {
      Future<PullResult> pullWith(Map<String, Object?> body) {
        final api = ApiClient(
          baseUrl: 'http://v2.test',
          token: 'token',
          client: MockClient((_) async => http.Response(jsonEncode(body), 200)),
          tokenStore: _MemoryTokenStore(),
        );
        return SyncRemoteDataSource(api: api).pullChanges(0);
      }

      final populated = await pullWith({
        'server_version': 18,
        'transactions': const <Object?>[],
        'preferences': [
          {
            'id': 'self',
            'default_account_id': 'cash',
            'server_version': 18,
            'updated_at': '2026-11-03T07:00:00',
          },
        ],
      });
      expect(populated.preference?.defaultAccountId, 'cash');
      expect(populated.preference?.serverVersion, 18);

      final empty = await pullWith({
        'server_version': 18,
        'transactions': const <Object?>[],
        'preferences': const <Object?>[],
      });
      expect(empty.preference, isNull);
    });
  });

  group('O-2 category version', () {
    test('editing a synced category carries base_version and its snapshot',
        () async {
      final session = _session();
      final repository = LedgerRepository(session: session);
      final state = FinanceState(
        categories: const [Category(id: 'food', name: '餐饮', serverVersion: 9)],
        syncState: const SyncState(serverVersion: 10),
      );

      // The caller deliberately omits the version: the repository restores it.
      await repository.saveCategory(const Category(id: 'food', name: '吃饭'),
          baseState: state);

      final operation = session.queue.pending().single;
      expect(operation.baseVersion, 9);
      expect(operation.payload['server_version'], 9);
      expect(operation.base?['name'], '餐饮');
      expect(operation.base?['server_version'], 9);
    });

    test('a brand-new category submits without a fabricated baseline',
        () async {
      final session = _session();
      final repository = LedgerRepository(session: session);

      await repository.saveCategory(const Category(id: 'new', name: '新分类'),
          baseState: const FinanceState());

      final operation = session.queue.pending().single;
      expect(operation.baseVersion, isNull);
      expect(operation.base, isNull);
    });

    test('an upgraded install backfills category versions with one full pull',
        () async {
      final session = _session();
      final state = FinanceState(
        categories: const [Category(id: 'food', name: '餐饮')],
        financialSchemaVersion: 2,
        syncState: const SyncState(serverVersion: 10),
      );
      final api = _ScriptedApi(
        pull: const PullResult(
          transactions: [],
          accounts: [],
          categories: [Category(id: 'food', name: '餐饮', serverVersion: 9)],
          budgets: [],
          serverVersion: 11,
        ),
      );

      final result = await _coordinator(session, api).pullChanges(state);

      expect(api.pulledSince, 0);
      expect(result.financialSchemaVersion, 3);
      expect(result.categories.single.serverVersion, 9);
    });

    test('a serial second-device rename hits conflicts and adopts the row',
        () async {
      final session = _session();
      final repository = LedgerRepository(session: session);
      final state = FinanceState(
        categories: const [Category(id: 'food', name: '餐饮', serverVersion: 9)],
        syncState: const SyncState(serverVersion: 10),
      );
      await repository.saveCategory(
          const Category(id: 'food', name: '吃饭', serverVersion: 9),
          baseState: state);
      final before = (await session.load())!;
      final operation = session.queue.pending().single;

      final api = _ScriptedApi();
      api.onPush = (_) async => {
            'server_version': 11,
            'results': const <Object?>[],
            'rejected': const <Object?>[],
            'conflicts': [
              {
                'op_id': operation.clientOpId,
                'entity': 'categories',
                'id': 'food',
                'reason': 'version_conflict',
                'authoritative_row':
                    const Category(id: 'food', name: '餐饮（新）', serverVersion: 10)
                        .toJson(),
              },
            ],
          };

      final result = await _coordinator(session, api).pushPending(before);

      expect(session.queue.pending(), isEmpty);
      expect(result.categories.single.name, '餐饮（新）');
      expect(result.categories.single.serverVersion, 10);
      expect(result.syncIssues.single.code, 'version_conflict');
    });
  });

  group('O-5 protocol capability', () {
    test('a client at or above min_protocol is not gated', () async {
      final session = _session();
      final assets = AssetsRepository(session: session);
      final state = FinanceState(
        accounts: [_cash(serverVersion: 7)],
        syncState: const SyncState(serverVersion: 10),
      );
      await assets.saveAccount(_cash(serverVersion: 7, name: '钱包'),
          baseState: state);
      final before = (await session.load())!;

      final api = _ScriptedApi();
      api.onPush = (_) async => throw const ApiFailure(
            ApiFailureKind.upgradeRequired,
            '服务端要求更高协议（v2），客户端已支持 v2；请稍后重试',
            statusCode: 426,
            code: 'upgrade_required',
            minProtocol: 2,
          );

      final result = await _coordinator(session, api).pushPending(before);

      expect(result.syncState.upgradeRequiredProtocol, isNull);
      expect(result.syncState.needsUpgrade, isFalse);
      expect(result.syncState.error, contains('服务端要求更高协议'));
      expect(session.queue.pending(), hasLength(1));
    });

    test('a stale gate at or below local capability does not block', () {
      const stale = SyncState(upgradeRequiredProtocol: 2);
      const real = SyncState(upgradeRequiredProtocol: 3);
      expect(stale.requiresUpgrade(kSupportedSyncProtocolVersion), isFalse);
      expect(real.requiresUpgrade(kSupportedSyncProtocolVersion), isTrue);
    });

    test('transport wording distinguishes client upgrade from server demand',
        () {
      final needsUpgrade = ApiTransport.upgradeMessage(
          ApiFailureKind.upgradeRequired, kSupportedSyncProtocolVersion + 1);
      final serverDemand = ApiTransport.upgradeMessage(
          ApiFailureKind.upgradeRequired, kSupportedSyncProtocolVersion);

      expect(needsUpgrade, contains('客户端需升级'));
      expect(serverDemand, contains('服务端要求更高协议'));
      expect(serverDemand, contains('客户端已支持'));
    });

    test('a qualified 426 allows the next automatic sync to retry', () async {
      final api = _ScriptedApi();
      api.onPush = (operations) async {
        if (api.pushCalls == 1) {
          throw const ApiFailure(
            ApiFailureKind.upgradeRequired,
            '服务端要求更高协议（v2），客户端已支持 v2；请稍后重试',
            statusCode: 426,
            code: 'upgrade_required',
            minProtocol: 2,
          );
        }
        return _v2Success(operations);
      };
      final repository = FinanceRepository(
        local: LocalRepository(_MemoryStore()),
        queue: SyncQueue(),
        api: api,
      );
      await repository.ensureLocalOwner('user');
      repository.queue.enqueue(SyncOperation(
        clientOpId: 'account-1',
        entity: 'accounts',
        entityId: 'cash',
        type: SyncOperationType.upsert,
        payload: _cash(serverVersion: 7).toJson(),
        createdAt: '2026-11-03T07:00:00Z',
        baseVersion: 7,
        base: _cash(serverVersion: 7).toJson(),
      ));
      final store = FinanceStore(
        repository: repository,
        initialState: FinanceState(
          accounts: [_cash(serverVersion: 7)],
          syncState: const SyncState(serverVersion: 10),
        ),
      );

      await store.sync();
      expect(store.state.syncState.needsUpgrade, isFalse);
      expect(api.pushCalls, 1);

      // Not gated: the next local mutation wakes the pipeline automatically.
      await store.assets.setDefaultAccount('cash');
      await Future<void>.delayed(const Duration(milliseconds: 500));
      expect(api.pushCalls, 2);
      expect(store.state.syncState.needsUpgrade, isFalse);
    });

    test('an unversioned 426 keeps the gate closed with readable text',
        () async {
      final api = _ScriptedApi();
      api.onPush = (operations) async {
        if (api.pushCalls == 1) {
          throw ApiFailure(
            ApiFailureKind.upgradeRequired,
            syncUpgradeMessage(null),
            statusCode: 426,
            code: 'upgrade_required',
          );
        }
        return _v2Success(operations);
      };
      final repository = FinanceRepository(
        local: LocalRepository(_MemoryStore()),
        queue: SyncQueue(),
        api: api,
      );
      await repository.ensureLocalOwner('user');
      repository.queue.enqueue(SyncOperation(
        clientOpId: 'account-1',
        entity: 'accounts',
        entityId: 'cash',
        type: SyncOperationType.upsert,
        payload: _cash(serverVersion: 7).toJson(),
        createdAt: '2026-11-03T07:00:00Z',
        baseVersion: 7,
        base: _cash(serverVersion: 7).toJson(),
      ));
      final store = FinanceStore(
        repository: repository,
        initialState: FinanceState(
          accounts: [_cash(serverVersion: 7)],
          syncState: const SyncState(serverVersion: 10),
        ),
      );

      await store.sync();
      expect(api.pushCalls, 1);
      expect(store.state.syncState.upgradeRequiredProtocol, isNull);
      expect(store.state.syncState.upgradeRequiredWithoutVersion, isTrue);
      expect(
          store.state.syncState.requiresUpgrade(kSupportedSyncProtocolVersion),
          isTrue);
      expect(store.message, contains('未提供具体版本'));
      expect(store.message, isNot(contains('null')));

      // The gate stops automatic retries even though the version is unknown.
      await store.assets.setDefaultAccount('cash');
      await Future<void>.delayed(const Duration(milliseconds: 350));
      expect(api.pushCalls, 1);

      // Manual retry stays the escape hatch.
      await store.sync();
      expect(api.pushCalls, 2);
      expect(store.state.syncState.needsUpgrade, isFalse);
      expect(store.state.syncState.upgradeRequiredWithoutVersion, isFalse);
    });
  });

  test('O-1: adopting a renamed adjustment cannot leave two rows', () async {
    final session = _session();
    final repository = AssetsRepository(session: session);
    const optimistic = FinanceTransaction(
      id: 'adj-local',
      date: '2026-11-03',
      type: TransactionType.adjustment,
      amount: 10,
      accountId: 'cash',
      clientOpId: 'cal-1',
    );
    await repository.saveLocalAdjustment(optimistic);
    const authoritative = FinanceTransaction(
      id: 'adj-server',
      date: '2026-11-03',
      type: TransactionType.adjustment,
      amount: 10,
      accountId: 'cash',
      clientOpId: 'cal-2',
      serverVersion: 5,
    );

    final result = await repository.adoptAdjustment(
      authoritative,
      accountId: 'cash',
      optimisticAdjustmentId: 'adj-local',
      optimisticClientOpId: 'cal-1',
    );

    expect(result.transactions, hasLength(1));
    expect(result.transactions.single.id, 'adj-server');
  });
}
