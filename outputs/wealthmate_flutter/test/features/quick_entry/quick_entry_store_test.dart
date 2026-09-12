import 'package:flutter_test/flutter_test.dart';
import 'package:wealthmate_flutter/core/database/local_state_session.dart';
import 'package:wealthmate_flutter/data/api_client.dart';
import 'package:wealthmate_flutter/data/finance_repository.dart';
import 'package:wealthmate_flutter/data/local_repository.dart';
import 'package:wealthmate_flutter/data/sync_queue.dart';
import 'package:wealthmate_flutter/domain/models.dart';
import 'package:wealthmate_flutter/features/ledger/data/ledger_repository.dart';
import 'package:wealthmate_flutter/features/ledger/state/ledger_store.dart';
import 'package:wealthmate_flutter/features/quick_entry/data/quick_entry_remote_data_source.dart';
import 'package:wealthmate_flutter/features/quick_entry/data/quick_entry_repository.dart';
import 'package:wealthmate_flutter/features/quick_entry/state/quick_entry_store.dart';
import 'package:wealthmate_flutter/state/finance_store.dart';

class _MemoryStore implements KeyValueStore {
  final Map<String, String> values = <String, String>{};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;
}

class _FailingMemoryStore implements KeyValueStore {
  @override
  Future<String?> read(String key) async => null;

  @override
  Future<void> write(String key, String value) async {
    throw StateError('local write failed');
  }
}

class _CountingApiClient extends ApiClient {
  _CountingApiClient() : super(baseUrl: 'https://online.test', token: 'token');

  int pushCount = 0;
  int pullCount = 0;

  @override
  Future<Map<String, Object?>> push(List<SyncOperation> operations) async {
    pushCount++;
    return {
      'accepted': [
        for (final operation in operations)
          {
            'client_op_id': operation.clientOpId,
            'entity_id': operation.entityId,
            'server_version': 1,
            'created': true,
          },
      ],
      'conflicts': const <Object?>[],
      'server_version': 1,
    };
  }

  @override
  Future<PullResult> pullChanges(int sinceVersion) async {
    pullCount++;
    return PullResult(
      transactions: const [],
      accounts: const [],
      categories: const [],
      budgets: const [],
      serverVersion: sinceVersion,
    );
  }
}

class _FakeRemote extends QuickEntryRemoteDataSource {
  _FakeRemote(this.result, {this.error}) : super();

  final AgentDraft result;
  final Object? error;

  @override
  Future<AgentDraft> createDraft(String text) async {
    if (error != null) throw error!;
    return result;
  }
}

FinanceState _state() => FinanceState(
      currentMonth: '2026-09',
      accounts: const [
        Account(
            id: 'alipay', name: '支付宝', type: AccountType.asset, isLiquid: true)
      ],
      categories: const [Category(id: 'food', name: '餐饮')],
      defaultAccountId: 'alipay',
    );

LocalStateSession _session() => LocalStateSession(
      local: LocalRepository(_MemoryStore()),
      queue: SyncQueue(),
    );

QuickEntryStore _store({
  LocalStateSession? session,
  QuickEntryRemoteDataSource? remote,
  Future<void> Function()? postConfirm,
}) {
  final effectiveSession = session ?? _session();
  return QuickEntryStore(
    repository: QuickEntryRepository(
      session: effectiveSession,
      remote: remote,
    ),
    initialState: _state(),
    postConfirm: postConfirm,
  );
}

void main() {
  test('local parsing creates a reviewable draft with missing facts', () async {
    final store = _store();

    await store.createDraft('今天吃饭吃了30元', now: DateTime(2026, 9, 4, 10));

    expect(store.draft?.amount, 30);
    expect(store.draft?.categoryId, 'food');
    expect(store.draft?.accountId, 'alipay');
    expect(store.draft?.missingFacts, isEmpty);
    expect(store.draft?.confidence, greaterThanOrEqualTo(.85));
  });

  test('remote draft merges into local draft and failures keep local draft',
      () async {
    final remote = _FakeRemote(const AgentDraft(
      amount: 31,
      type: TransactionType.expense,
      categoryId: null,
      accountId: null,
      date: '2026-09-04',
      note: '远端备注',
      currency: 'CNY',
      confidence: .2,
    ));
    final store = _store(remote: remote);

    await store.createDraft('今天吃饭吃了30元', now: DateTime(2026, 9, 4, 10));

    expect(store.draft?.amount, 31);
    expect(store.draft?.categoryId, 'food');
    expect(store.draft?.accountId, 'alipay');
    expect(store.draft?.note, '远端备注');

    final fallback = _store(
      remote: _FakeRemote(
        const AgentDraft(
          amount: 99,
          type: TransactionType.expense,
          categoryId: null,
          accountId: null,
          date: '',
          note: '',
          confidence: .1,
        ),
        error: const ApiFailure(ApiFailureKind.network, 'offline'),
      ),
    );
    await fallback.createDraft('今天吃饭吃了30元', now: DateTime(2026, 9, 4, 10));

    expect(fallback.draft?.amount, 30);
    expect(fallback.message, contains('本地规则草稿'));
  });

  test('editing a draft makes it confirmable, while cancel never posts',
      () async {
    final store = _store();
    await store.createDraft('今天花了一笔钱', now: DateTime(2026, 9, 4, 10));
    final incomplete = store.draft!;
    var postCount = 0;

    expect(await store.confirmDraft(incomplete, null, (_) async => postCount++),
        isFalse);
    expect(postCount, 0);

    store.updateDraft(incomplete.copyWith(
      amount: 30,
      categoryId: 'food',
      accountId: 'alipay',
    ));
    expect(store.draft?.missingFacts, isEmpty);
    store.clearDraft();

    expect(store.draft, isNull);
    expect(postCount, 0);
    expect(await store.repository.session.pendingOperations(), isEmpty);
  });

  test(
      'remembering a choice persists through LocalStateSession without queueing',
      () async {
    final session = _session();
    final store = _store(session: session);
    const draft = AgentDraft(
      amount: 30,
      type: TransactionType.expense,
      categoryId: 'food',
      accountId: 'alipay',
      date: '2026-09-04',
      note: '午餐',
      confidence: .98,
    );

    await store.rememberDraftChoice('今天吃饭吃了30元', draft);

    final saved = await session.load();
    expect(saved?.quickMemories.single.categoryId, 'food');
    expect(saved?.quickMemories.single.accountId, 'alipay');
    expect(await session.pendingOperations(), isEmpty);
  });

  test('QuickMemory persistence preserves the current aggregate state',
      () async {
    final session = _session();
    final store = _store(session: session);
    const draft = AgentDraft(
      amount: 30,
      type: TransactionType.expense,
      categoryId: 'food',
      accountId: 'alipay',
      date: '2026-09-04',
      note: '午餐',
      confidence: .98,
    );

    await store.rememberDraftChoice('今天吃饭吃了30元', draft);

    final saved = await session.load();
    expect(saved?.accounts.single.id, 'alipay');
    expect(saved?.categories.single.id, 'food');
    expect(await session.pendingOperations(), isEmpty);
  });

  test(
      'confirm posts one transaction through LedgerStore and duplicate confirm is inert',
      () async {
    final session = _session();
    final ledger = LedgerStore(
      repository: LedgerRepository(session: session),
      initialState: _state(),
    );
    final store = _store(session: session);
    const draft = AgentDraft(
      amount: 30,
      type: TransactionType.expense,
      categoryId: 'food',
      accountId: 'alipay',
      date: '2026-09-04',
      note: '午餐',
      confidence: .98,
    );
    var callbackCount = 0;
    Future<void> post(FinanceTransaction transaction) async {
      callbackCount++;
      await ledger.addTransaction(transaction);
    }

    await store.createDraft('今天吃饭吃了30元', now: DateTime(2026, 9, 4, 10));
    final confirmable = store.draft!.copyWith(
      amount: draft.amount,
      categoryId: draft.categoryId,
      accountId: draft.accountId,
      confidence: draft.confidence,
      missingFacts: const [],
    );
    store.updateDraft(confirmable);

    expect(await store.confirmDraft(confirmable, '今天吃饭吃了30元', post), isTrue);
    expect(await store.confirmDraft(confirmable, '今天吃饭吃了30元', post), isFalse);
    expect(callbackCount, 1);
    expect(ledger.transactions, hasLength(1));
    expect(ledger.transactions.single.amount, 30);
    expect(
        ledger.transactions.single.clientOpId, ledger.transactions.single.id);
    expect(await session.pendingOperations(), hasLength(1));
  });

  test('online confirmation invokes the post-confirm callback once', () async {
    var postConfirmCount = 0;
    final store = _store(
      postConfirm: () async {
        postConfirmCount++;
      },
    );
    const draft = AgentDraft(
      amount: 30,
      type: TransactionType.expense,
      categoryId: 'food',
      accountId: 'alipay',
      date: '2026-09-04',
      note: '午餐',
      confidence: .98,
    );
    var postCount = 0;

    expect(
      await store.confirmDraft(draft, '今天吃饭吃了30元', (_) async {
        postCount++;
      }),
      isTrue,
    );

    expect(postCount, 1);
    expect(postConfirmCount, 1);
  });

  test('failed QuickMemory persistence makes duplicate confirmation inert',
      () async {
    final session = LocalStateSession(
      local: LocalRepository(_FailingMemoryStore()),
      queue: SyncQueue(),
    );
    final store = _store(session: session);
    const draft = AgentDraft(
      amount: 30,
      type: TransactionType.expense,
      categoryId: 'food',
      accountId: 'alipay',
      date: '2026-09-04',
      note: '午餐',
      confidence: .98,
    );
    var postCount = 0;

    await expectLater(
      store.confirmDraft(draft, '今天吃饭吃了30元', (_) async {
        postCount++;
      }),
      throwsStateError,
    );
    expect(await store.confirmDraft(draft, '今天吃饭吃了30元', (_) async {
      postCount++;
    }), isFalse);
    expect(postCount, 1);
  });

  test('failed Ledger posting leaves the draft retryable', () async {
    final store = _store();
    const draft = AgentDraft(
      amount: 30,
      type: TransactionType.expense,
      categoryId: 'food',
      accountId: 'alipay',
      date: '2026-09-04',
      note: '午餐',
      confidence: .98,
    );
    var postCount = 0;

    Future<void> post(FinanceTransaction transaction) async {
      postCount++;
      if (postCount == 1) throw StateError('ledger unavailable');
    }

    await expectLater(store.confirmDraft(draft, null, post), throwsStateError);
    expect(await store.confirmDraft(draft, null, post), isTrue);
    expect(postCount, 2);
  });

  test('failed post-confirm callback makes duplicate confirmation inert',
      () async {
    final store = _store(
      postConfirm: () async {
        throw StateError('sync unavailable');
      },
    );
    const draft = AgentDraft(
      amount: 30,
      type: TransactionType.expense,
      categoryId: 'food',
      accountId: 'alipay',
      date: '2026-09-04',
      note: '午餐',
      confidence: .98,
    );
    var postCount = 0;

    await expectLater(store.confirmDraft(draft, null, (_) async {
      postCount++;
    }), throwsStateError);
    expect(await store.confirmDraft(draft, null, (_) async {
      postCount++;
    }), isFalse);
    expect(postCount, 1);
  });

  test('online FinanceStore confirmation syncs once after Ledger mutation',
      () async {
    final local = LocalRepository(_MemoryStore());
    final queue = SyncQueue();
    final api = _CountingApiClient();
    final repository = FinanceRepository(
      local: local,
      queue: queue,
      api: api,
    );
    await repository.ensureLocalOwner('online-user');
    final store = FinanceStore(repository: repository, initialState: _state());
    const draft = AgentDraft(
      amount: 30,
      type: TransactionType.expense,
      categoryId: 'food',
      accountId: 'alipay',
      date: '2026-09-04',
      note: '午餐',
      confidence: .98,
    );

    expect(await store.confirmDraft(draft), isTrue);
    expect(store.ledger.transactions, hasLength(1));
    expect(api.pushCount, 1);
    expect(api.pullCount, 1);
  });
}
