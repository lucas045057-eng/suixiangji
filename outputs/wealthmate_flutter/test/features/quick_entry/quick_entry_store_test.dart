import 'package:flutter_test/flutter_test.dart';
import 'package:wealthmate_flutter/core/database/local_state_session.dart';
import 'package:wealthmate_flutter/data/api_client.dart';
import 'package:wealthmate_flutter/data/local_repository.dart';
import 'package:wealthmate_flutter/data/sync_queue.dart';
import 'package:wealthmate_flutter/domain/models.dart';
import 'package:wealthmate_flutter/features/ledger/data/ledger_repository.dart';
import 'package:wealthmate_flutter/features/ledger/state/ledger_store.dart';
import 'package:wealthmate_flutter/features/quick_entry/data/quick_entry_remote_data_source.dart';
import 'package:wealthmate_flutter/features/quick_entry/data/quick_entry_repository.dart';
import 'package:wealthmate_flutter/features/quick_entry/state/quick_entry_store.dart';

class _MemoryStore implements KeyValueStore {
  final Map<String, String> values = <String, String>{};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;
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
}) {
  final effectiveSession = session ?? _session();
  return QuickEntryStore(
    repository: QuickEntryRepository(
      session: effectiveSession,
      remote: remote,
    ),
    initialState: _state(),
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
}
