import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:wealthmate_flutter/core/database/local_state_session.dart';
import 'package:wealthmate_flutter/core/network/api_transport.dart';
import 'package:wealthmate_flutter/data/local_repository.dart';
import 'package:wealthmate_flutter/data/sync_queue.dart';
import 'package:wealthmate_flutter/domain/finance_rules.dart';
import 'package:wealthmate_flutter/domain/models.dart';
import 'package:wealthmate_flutter/features/quick_entry/data/quick_entry_remote_data_source.dart';
import 'package:wealthmate_flutter/features/quick_entry/data/quick_entry_repository.dart';
import 'package:wealthmate_flutter/features/quick_entry/domain/quick_entry_batch.dart';
import 'package:wealthmate_flutter/features/quick_entry/state/quick_entry_store.dart';

const _text = '跟昨天差不多，吃饭32元';

class _AtomicStore implements AtomicKeyValueStore {
  final Map<String, String> values = <String, String>{};
  bool failWrites = false;

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    if (failWrites) throw StateError('disk failed');
    values[key] = value;
  }

  @override
  Future<void> writeBatch(Map<String, String> batch) async {
    if (failWrites) throw StateError('disk failed');
    values.addAll(batch);
  }
}

class _NonAtomicStore implements KeyValueStore {
  final Map<String, String> values = <String, String>{};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;
}

class _FakeRemote extends QuickEntryRemoteDataSource {
  _FakeRemote(this.handler);

  final FutureOr<Map<String, Object?>> Function(Map<String, Object?> body)
      handler;
  int calls = 0;
  final List<Map<String, Object?>> bodies = <Map<String, Object?>>[];

  @override
  Future<Map<String, Object?>> createDrafts(Map<String, Object?> body) async {
    calls += 1;
    bodies.add(body);
    return handler(body);
  }
}

Map<String, Object?> _sourceEvidence(String quote, int start, int end) => {
      'kind': 'source_text',
      'quote': quote,
      'start': start,
      'end': end,
    };

Map<String, Object?> _explicitDraft(
  Map<String, Object?> request, {
  String id = 'd1',
  String amount = '32.00',
  String quote = '吃饭32元',
  int start = 7,
  int end = 12,
  String note = '吃饭',
  String? categoryId = 'food',
  String? accountId = 'alipay',
  bool selected = true,
}) {
  final missing = <String>[
    if (amount.isEmpty) '请输入金额',
    if (categoryId == null) '请选择分类',
    if (accountId == null) '请选择支付账户',
  ];
  return {
    'client_draft_id': id,
    'source': 'explicit',
    'type': 'expense',
    'amount': amount.isEmpty ? null : amount,
    'amount_range': null,
    'is_approximate': false,
    'currency': 'CNY',
    'category_hint': null,
    'category_id': categoryId,
    'account_hint': null,
    'account_id': accountId,
    'date': request['local_today'],
    'note': note,
    'confidence': 0.96,
    'missing_facts': missing,
    'selected_by_default': selected,
    'evidence': [_sourceEvidence(quote, start, end)],
    'derivation': null,
  };
}

Map<String, Object?> _inferredDraft(
  Map<String, Object?> request, {
  String id = 'd9',
}) {
  final context = (request['ledger_context'] as Map).cast<String, Object?>();
  return {
    'client_draft_id': id,
    'source': 'inferred',
    'type': 'expense',
    'amount': '87.50',
    'amount_range': null,
    'is_approximate': true,
    'currency': 'CNY',
    'category_hint': null,
    'category_id': null,
    'account_hint': null,
    'account_id': null,
    'date': context['target_date'],
    'note': '其他支出（按昨日推算）',
    'confidence': 0.6,
    'missing_facts': const ['请选择分类'],
    'selected_by_default': false,
    'evidence': [
      _sourceEvidence('跟昨天差不多', 0, 6),
      {
        'kind': 'ledger_context',
        'context_path': 'currencies.CNY.reference_day',
        'reference_date': context['reference_date'],
      },
    ],
    'derivation': {
      'kind': 'previous_day_expense_residual',
      'reference_date': context['reference_date'],
      'target_date': context['target_date'],
      'operands': [
        {
          'key': 'reference_expense',
          'label': '昨日已记消费',
          'amount': '132.50',
          'is_approximate': false,
        },
        {
          'key': 'target_recorded',
          'label': '今日已记消费',
          'amount': '0.00',
          'is_approximate': false,
        },
        {
          'key': 'explicit_candidates',
          'label': '本次明确卡合计',
          'amount': '45.00',
          'is_approximate': true,
        },
      ],
      'formula': 'reference_expense - target_recorded - explicit_candidates',
      'result': '87.50',
      'context_fingerprint': context['fingerprint'],
    },
  };
}

Map<String, Object?> _ok(
  Map<String, Object?> request, {
  required List<Map<String, Object?>> drafts,
  List<Map<String, Object?>> notices = const [],
  String status = 'ok',
}) =>
    {
      'schema_version': 1,
      'request_id': request['request_id'],
      'status': status,
      'engine': 'llm',
      'requires_confirmation': true,
      'drafts': drafts,
      'notices': notices,
    };

FinanceState _state({List<FinanceTransaction> transactions = const []}) =>
    FinanceState(
      currentMonth: '2026-10',
      preferredCurrency: 'CNY',
      defaultAccountId: 'alipay',
      accounts: const [
        Account(id: 'alipay', name: '支付宝', type: AccountType.asset),
      ],
      categories: const [
        Category(id: 'food', name: '餐饮'),
        Category(id: 'transport', name: '交通'),
        Category(id: 'salary', name: '工资', type: TransactionType.income),
      ],
      transactions: transactions,
    );

FinanceState _stateWithTransportAsIncome() => FinanceState(
      currentMonth: '2026-10',
      preferredCurrency: 'CNY',
      defaultAccountId: 'alipay',
      accounts: const [
        Account(id: 'alipay', name: '支付宝', type: AccountType.asset),
      ],
      categories: const [
        Category(id: 'food', name: '餐饮'),
        Category(
            id: 'transport', name: '交通', type: TransactionType.income),
        Category(id: 'salary', name: '工资', type: TransactionType.income),
      ],
    );

({
  QuickEntryStore store,
  _AtomicStore storage,
  LocalStateSession session,
}) _build({
  QuickEntryRemoteDataSource? remote,
  FinanceState? state,
}) {
  final storage = _AtomicStore();
  final session = LocalStateSession(
    local: LocalRepository(storage),
    queue: SyncQueue(),
  );
  final store = QuickEntryStore(
    repository: QuickEntryRepository(session: session, remote: remote),
    initialState: state ?? _state(),
  );
  return (store: store, storage: storage, session: session);
}

void main() {
  test('cloud batch becomes selected explicit cards and unselected inferences',
      () async {
    final remote = _FakeRemote((body) => _ok(
          body,
          drafts: [_explicitDraft(body), _inferredDraft(body)],
          notices: const [
            {
              'code': 'approximate_amount',
              'message': '有界金额区间已按中值约记，可修改。',
            }
          ],
        ));
    final harness = _build(remote: remote);

    final parsed = await harness.store
        .createBatch(_text, now: DateTime(2026, 10, 28, 10));

    expect(parsed, isTrue);
    expect(remote.calls, 1);
    expect(harness.store.batch!.mode, QuickEntryParseMode.cloud);
    expect(harness.store.candidates, hasLength(2));
    expect(harness.store.candidates.first.selected, isTrue);
    expect(harness.store.candidates.last.isInferred, isTrue);
    expect(harness.store.candidates.last.selected, isFalse);
    expect(harness.store.candidates.first.draft.categoryId, 'food');
    expect(harness.store.candidates.first.draft.accountId, 'alipay');
    expect(harness.store.batch!.notices.single.code, 'approximate_amount');

    final context =
        (remote.bodies.single['ledger_context'] as Map).cast<String, Object?>();
    expect(context['status'], 'ready');
    expect(context['target_date'], '2026-10-28');
    expect(context['reference_date'], '2026-10-27');
    expect(remote.bodies.single['schema_version'], 1);
    expect(remote.bodies.single['utc_offset_minutes'], isA<int>());
  });

  test('a slow first parse can never overwrite a newer input', () async {
    final first = Completer<Map<String, Object?>>();
    final second = Completer<Map<String, Object?>>();
    final bodies = <String, Map<String, Object?>>{};
    final remote = _FakeRemote((body) {
      final text = body['text'] as String;
      bodies[text] = body;
      return text == '甲' ? first.future : second.future;
    });
    final harness = _build(remote: remote);
    await harness.store.loadCloudPreference();

    final pendingFirst = harness.store.createBatch('甲');
    final pendingSecond = harness.store.createBatch('乙');
    await Future<void>.delayed(Duration.zero);

    second.complete(_ok(bodies['乙']!, drafts: [
      _explicitDraft(bodies['乙']!,
          amount: '5.00', quote: '乙', start: 0, end: 1, note: '乙'),
    ]));
    expect(await pendingSecond, isTrue);
    expect(harness.store.batch!.sourceText, '乙');

    first.complete(_ok(bodies['甲']!, drafts: [
      _explicitDraft(bodies['甲']!,
          amount: '9.00', quote: '甲', start: 0, end: 1, note: '甲'),
    ]));
    expect(await pendingFirst, isFalse);
    expect(harness.store.batch!.sourceText, '乙');
    expect(harness.store.candidates.single.draft.amount, 5);
  });

  test('turning the cloud switch off drops in-flight results and stops requests',
      () async {
    final gate = Completer<Map<String, Object?>>();
    Map<String, Object?>? captured;
    final remote = _FakeRemote((body) {
      captured = body;
      return gate.future;
    });
    final harness = _build(remote: remote);
    await harness.store.loadCloudPreference();

    final pending = harness.store.createBatch(_text);
    await Future<void>.delayed(Duration.zero);
    await harness.store.setCloudParsingEnabled(false);
    expect(harness.store.batch, isNull);
    expect(harness.store.message, '已切换为本地解析');

    gate.complete(_ok(captured!, drafts: [_explicitDraft(captured!)]));
    expect(await pending, isFalse);
    expect(harness.store.batch, isNull);
    expect(remote.calls, 1);

    expect(await harness.store.createBatch('吃饭32元'), isTrue);
    expect(remote.calls, 1, reason: '云端关闭后不得再发请求');
    expect(harness.store.batch!.mode, QuickEntryParseMode.local);
    expect(harness.store.batch!.candidates.single.selected, isTrue);
  });

  test('the cloud switch persists per device', () async {
    final harness = _build(remote: _FakeRemote((body) => _ok(body, drafts: [
          _explicitDraft(body)
        ])));
    await harness.store.setCloudParsingEnabled(false);

    final reloaded = QuickEntryRepository(
      session: LocalStateSession(
        local: LocalRepository(harness.storage),
        queue: SyncQueue(),
      ),
    );
    expect(await reloaded.cloudParsingEnabled(), isFalse);
  });

  test('network failure degrades to one local card without retrying', () async {
    final remote = _FakeRemote(
        (body) => throw const ApiFailure(ApiFailureKind.network, 'offline'));
    final harness = _build(remote: remote);

    final parsed = await harness.store.createBatch(_text);
    expect(parsed, isTrue);
    expect(remote.calls, 1);
    expect(harness.store.batch!.mode, QuickEntryParseMode.local);
    expect(harness.store.batch!.notices.first.code, 'cloud_unavailable');
    expect(harness.store.message, contains('暂时无法连接云端'));
    expect(harness.store.batch!.candidates.single.isInferred, isFalse);
  });

  test('an invalid cloud response degrades instead of showing suspect cards',
      () async {
    final remote = _FakeRemote((body) => {
          'schema_version': 2,
          'request_id': body['request_id'],
          'status': 'ok',
          'engine': 'llm',
          'requires_confirmation': true,
          'drafts': [_explicitDraft(body)],
          'notices': const [],
        });
    final harness = _build(remote: remote);

    expect(await harness.store.createBatch(_text), isTrue);
    expect(harness.store.batch!.mode, QuickEntryParseMode.local);
    expect(harness.store.message, contains('未通过校验'));
  });

  test('batch confirmation writes transactions, operations and memories at once',
      () async {
    final remote = _FakeRemote((body) => _ok(
          body,
          drafts: [_explicitDraft(body), _inferredDraft(body)],
        ));
    final harness = _build(remote: remote);
    await harness.store.createBatch(_text, now: DateTime(2026, 10, 28, 10));
    final mutations = <String>[];
    harness.store.onLocalMutation = mutations.add;

    expect(await harness.store.confirmBatch(now: DateTime(2026, 10, 28, 11)),
        isTrue);

    expect(mutations, ['quick_entry.batch.confirm']);
    expect(harness.store.state.transactions, hasLength(1));
    final operation = harness.store.state.transactions.single;
    expect(operation.clientOpId, operation.id);
    expect(operation.categoryId, 'food');
    expect(await harness.session.pendingOperations(), hasLength(1));
    expect(harness.store.state.quickMemories.single.key,
        FinanceRules.quickMemoryKey('吃饭32元'));
    expect(harness.store.batch, isNull);

    expect(await harness.store.confirmBatch(), isFalse);
    expect(harness.store.state.transactions, hasLength(1));
  });

  test('a failure on the third card leaves zero transactions and zero learning',
      () async {
    final remote = _FakeRemote((body) => _ok(body, drafts: [
          _explicitDraft(body, id: 'd1'),
          _explicitDraft(body, id: 'd2'),
          _explicitDraft(body, id: 'd3', categoryId: 'transport'),
        ]));
    final harness = _build(remote: remote);
    await harness.store.createBatch(_text, now: DateTime(2026, 10, 28, 10));
    expect(harness.store.selectedCandidates, hasLength(3));
    // The third card's category is re-typed between parsing and confirmation,
    // so the first two conversions succeed in memory and the third one fails.
    harness.store.adoptState(_stateWithTransportAsIncome());
    harness.storage.values.clear();

    expect(await harness.store.confirmBatch(now: DateTime(2026, 10, 28, 11)),
        isFalse);
    expect(harness.store.message, contains('分类与收支类型不一致'));
    expect(harness.store.state.transactions, isEmpty);
    expect(harness.store.state.quickMemories, isEmpty);
    expect(await harness.session.pendingOperations(), isEmpty);
    expect(harness.storage.values, isEmpty);
    expect(harness.store.candidates, hasLength(3), reason: '失败后草稿仍可重试');
  });

  test('a storage failure keeps the batch retryable and writes nothing',
      () async {
    final remote = _FakeRemote((body) => _ok(body, drafts: [
          _explicitDraft(body, id: 'd1'),
          _explicitDraft(body, id: 'd2'),
        ]));
    final harness = _build(remote: remote);
    await harness.store.createBatch(_text, now: DateTime(2026, 10, 28, 10));
    harness.storage.failWrites = true;

    await expectLater(
        harness.store.confirmBatch(now: DateTime(2026, 10, 28, 11)),
        throwsStateError);
    expect(harness.storage.values, isEmpty);
    expect(harness.store.state.transactions, isEmpty);
    expect(await harness.session.pendingOperations(), isEmpty);
    expect(harness.store.candidates, hasLength(2));
  });

  test('inferred cards never learn a QuickMemory even after editing', () async {
    final remote = _FakeRemote((body) => _ok(
          body,
          drafts: [_explicitDraft(body), _inferredDraft(body)],
        ));
    final harness = _build(remote: remote);
    await harness.store.createBatch(_text, now: DateTime(2026, 10, 28, 10));

    final inferred = harness.store.candidates.last;
    harness.store.updateCandidate(
        inferred.id, inferred.draft.copyWith(categoryId: 'food', accountId: 'alipay'));
    harness.store.toggleCandidate(inferred.id, true);
    expect(harness.store.selectedCandidates, hasLength(2));

    expect(await harness.store.confirmBatch(now: DateTime(2026, 10, 28, 11)),
        isTrue);
    expect(harness.store.state.transactions, hasLength(2));
    expect(harness.store.state.quickMemories, hasLength(1));
    expect(harness.store.state.quickMemories.single.key,
        FinanceRules.quickMemoryKey('吃饭32元'));
  });

  test('stale inferences cannot be confirmed after the ledger changes',
      () async {
    final remote = _FakeRemote((body) => _ok(
          body,
          drafts: [_explicitDraft(body), _inferredDraft(body)],
        ));
    final harness = _build(remote: remote);
    await harness.store.createBatch(_text, now: DateTime(2026, 10, 28, 10));
    final inferred = harness.store.candidates.last;
    harness.store.toggleCandidate(inferred.id, true);
    expect(harness.store.selectedCandidates, hasLength(2));

    harness.store.adoptState(_state(transactions: const [
      FinanceTransaction(
          id: 'yesterday',
          date: '2026-10-27',
          type: TransactionType.expense,
          amount: 20,
          categoryId: 'food'),
    ]));
    final baseline = harness.store.state.transactions.length;

    harness.store.toggleCandidate(harness.store.candidates.first.id, false);
    expect(harness.store.selectedCandidates.single.isInferred, isTrue);

    expect(await harness.store.confirmBatch(now: DateTime(2026, 10, 28, 11)),
        isFalse);
    expect(harness.store.state.transactions, hasLength(baseline));
    expect(harness.store.candidates.last.stale, isTrue);
    expect(harness.store.candidates.last.selected, isFalse);
    expect(harness.store.message, contains('勾选'));

    harness.store.toggleCandidate(harness.store.candidates.first.id, true);
    expect(await harness.store.confirmBatch(now: DateTime(2026, 10, 28, 11)),
        isTrue);
    expect(harness.store.state.transactions, hasLength(baseline + 1),
        reason: '只有明确卡入账');
    expect(
        harness.store.state.transactions.where((item) => item.amount == 87.5),
        isEmpty);
  });

  test('a non-atomic store disables batch parsing and confirmation', () async {
    final remote = _FakeRemote((body) => _ok(body, drafts: [_explicitDraft(body)]));
    final session = LocalStateSession(
      local: LocalRepository(_NonAtomicStore()),
      queue: SyncQueue(),
    );
    final store = QuickEntryStore(
      repository: QuickEntryRepository(session: session, remote: remote),
      initialState: _state(),
    );

    expect(store.batchSupported, isFalse);
    expect(await store.createBatch(_text), isFalse);
    expect(remote.calls, 0);
    expect(store.message, contains('不支持事务批量确认'));
  });
}
