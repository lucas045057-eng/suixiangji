import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:wealthmate_flutter/core/database/local_state_session.dart';
import 'package:wealthmate_flutter/core/network/api_transport.dart';
import 'package:wealthmate_flutter/data/local_repository.dart';
import 'package:wealthmate_flutter/data/sync_queue.dart';
import 'package:wealthmate_flutter/domain/models.dart';
import 'package:wealthmate_flutter/features/quick_entry/data/quick_entry_remote_data_source.dart';
import 'package:wealthmate_flutter/features/quick_entry/data/quick_entry_repository.dart';
import 'package:wealthmate_flutter/features/quick_entry/domain/quick_entry_batch.dart';
import 'package:wealthmate_flutter/features/quick_entry/domain/quick_entry_stream.dart';
import 'package:wealthmate_flutter/features/quick_entry/state/quick_entry_store.dart';

const _text = '中午吃饭32元，打车20元';

class _CountingStore implements AtomicKeyValueStore {
  final Map<String, String> values = <String, String>{};
  int writes = 0;

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    writes += 1;
    values[key] = value;
  }

  @override
  Future<void> writeBatch(Map<String, String> batch) async {
    writes += 1;
    values.addAll(batch);
  }
}

/// A stream source the test drives event by event.
class _FakeStreamRemote extends QuickEntryRemoteDataSource {
  final List<StreamController<QuickEntryStreamEvent>> streams =
      <StreamController<QuickEntryStreamEvent>>[];
  final List<String> requestIds = <String>[];
  final List<Map<String, Object?>> bodies = <Map<String, Object?>>[];
  int legacyCalls = 0;
  bool closeOnAbort = true;
  Object? connectError;
  Map<String, Object?> Function(Map<String, Object?> body)? legacyHandler;

  @override
  bool get supportsStreaming => true;

  @override
  Stream<QuickEntryStreamEvent> createDraftsStream(
    Map<String, Object?> body, {
    required String requestId,
    required Future<void> abortTrigger,
  }) {
    requestIds.add(requestId);
    bodies.add(body);
    if (connectError != null) return Stream<QuickEntryStreamEvent>.error(connectError!);
    final controller = StreamController<QuickEntryStreamEvent>();
    streams.add(controller);
    // Cancelling aborts the connection: the fake stream ends like a real one.
    abortTrigger.then((_) {
      if (closeOnAbort && !controller.isClosed) controller.close();
    });
    return controller.stream;
  }

  @override
  Future<Map<String, Object?>> createDrafts(Map<String, Object?> body) async {
    legacyCalls += 1;
    return legacyHandler!(body);
  }

  void emit(int index, QuickEntryStreamEvent event) => streams[index].add(event);

  void closeStream(int index) => streams[index].close();
}

QuickEntryStreamEvent _event(
  int seq,
  String type, {
  Map<String, Object?> data = const <String, Object?>{},
  int attempt = 1,
}) =>
    QuickEntryStreamEvent(seq: seq, attempt: attempt, type: type, data: data);

Map<String, Object?> _quote(String text, int start, int end) => {
      'quote': text,
      'start': start,
      'end': end,
    };

Map<String, Object?> _previewPayload({
  String previewId = 'a1-i0',
  int ordinal = 0,
  String note = '午饭',
  String quote = '中午吃饭32元',
  int start = 0,
  int end = 7,
  String? amount = '32.00',
  String amountKind = 'exact',
  String type = 'expense',
  String? categoryHint = '餐饮',
  String? accountHint,
}) =>
    {
      'preview_id': previewId,
      'ordinal': ordinal,
      'type': type,
      'note': note,
      'source_quote': _quote(quote, start, end),
      'amount_kind': amountKind,
      'amount': amount,
      'amount_range': null,
      'is_approximate': false,
      'currency': 'CNY',
      'date': '2026-10-30',
      'category_hint': categoryHint,
      'account_hint': accountHint,
    };

Map<String, Object?> _draft(
  String requestId, {
  required String id,
  required String amount,
  required String quote,
  required int start,
  required int end,
  required String note,
}) =>
    {
      'client_draft_id': id,
      'source': 'explicit',
      'type': 'expense',
      'amount': amount,
      'amount_range': null,
      'is_approximate': false,
      'currency': 'CNY',
      'category_hint': null,
      'category_id': 'food',
      'account_hint': null,
      'account_id': 'alipay',
      'date': '2026-10-30',
      'note': note,
      'confidence': 0.96,
      'missing_facts': const <String>[],
      'selected_by_default': true,
      'evidence': [
        {'kind': 'source_text', 'quote': quote, 'start': start, 'end': end},
      ],
      'derivation': null,
    };

Map<String, Object?> _completed(
  String requestId, {
  String status = 'ok',
  List<Map<String, Object?>>? drafts,
}) =>
    {
      'result': {
        'schema_version': 1,
        'request_id': requestId,
        'status': status,
        'engine': 'llm',
        'requires_confirmation': true,
        'drafts': drafts ??
            [
              _draft(requestId,
                  id: 'd1', amount: '32.00', quote: '中午吃饭32元', start: 0, end: 7, note: '午饭'),
              _draft(requestId,
                  id: 'd2', amount: '20.00', quote: '打车20元', start: 8, end: 13, note: '打车'),
            ],
        'notices': const <Map<String, Object?>>[],
      },
    };

FinanceState _state() => const FinanceState(
      currentMonth: '2026-10',
      preferredCurrency: 'CNY',
      defaultAccountId: 'alipay',
      accounts: [Account(id: 'alipay', name: '支付宝', type: AccountType.asset)],
      categories: [
        Category(id: 'food', name: '餐饮'),
        Category(id: 'transport', name: '交通'),
      ],
    );

({QuickEntryStore store, _CountingStore storage, _FakeStreamRemote remote})
    _build({Map<String, Object?> Function(Map<String, Object?>)? legacyHandler}) {
  final storage = _CountingStore();
  final session = LocalStateSession(
    local: LocalRepository(storage),
    queue: SyncQueue(),
  );
  final remote = _FakeStreamRemote();
  remote.legacyHandler = legacyHandler ??
      (body) => {
            'schema_version': 1,
            'request_id': body['request_id'],
            'status': 'ok',
            'engine': 'llm',
            'requires_confirmation': true,
            'drafts': [
              _draft('${body['request_id']}',
                  id: 'd1', amount: '32.00', quote: '中午吃饭32元', start: 0, end: 7, note: '午饭'),
            ],
            'notices': const <Map<String, Object?>>[],
          };
  final store = QuickEntryStore(
    repository: QuickEntryRepository(session: session, remote: remote),
    initialState: _state(),
  );
  return (store: store, storage: storage, remote: remote);
}

void main() {
  test('streams real previews, then adopts only the completed batch',
      () async {
    final harness = _build();
    final future = harness.store.createBatch(_text, now: DateTime(2026, 10, 30, 9));
    await pumpEventQueue();
    expect(harness.store.isStreamLocked, isTrue);
    expect(harness.store.streamPhase, QuickEntryStreamPhase.submitting);

    final remote = harness.remote;
    remote.emit(0, _event(1, 'session.started'));
    remote.emit(0, _event(2, 'generation.started'));
    remote.emit(0, _event(3, 'item.preview', data: _previewPayload()));
    await pumpEventQueue();
    expect(harness.store.preview!.items, hasLength(1));
    expect(harness.store.batch, isNull, reason: '预览期间绝不构建正式批次');
    expect(harness.storage.writes, 0);

    remote.emit(
      0,
      _event(4, 'item.preview',
          data: _previewPayload(
              previewId: 'a1-i1',
              ordinal: 1,
              note: '打车',
              quote: '打车20元',
              start: 8,
              end: 13,
              amount: '20.00',
              categoryHint: null)),
    );
    await pumpEventQueue();
    expect(harness.store.preview!.items, hasLength(2));

    remote.emit(0, _event(5, 'provider.completed'));
    remote.emit(0, _event(6, 'plan.validated'));
    await pumpEventQueue();
    expect(harness.store.streamPhase, QuickEntryStreamPhase.finalizing);

    remote.emit(0,
        _event(7, 'completed', data: _completed(remote.requestIds.single)));
    expect(await future, isTrue);
    expect(harness.store.preview, isNull);
    expect(harness.store.streamPhase, QuickEntryStreamPhase.ready);
    expect(harness.store.batch!.mode, QuickEntryParseMode.cloud);
    expect(harness.store.candidates, hasLength(2));
    expect(harness.store.candidates.first.selected, isTrue);
    expect(harness.store.isStreamLocked, isFalse);
    expect(harness.storage.writes, 0, reason: '解析不写本地');
  });

  test('a missing amount stays missing in the preview', () async {
    final harness = _build();
    final future = harness.store.createBatch(_text, now: DateTime(2026, 10, 30, 9));
    await pumpEventQueue();
    harness.remote.emit(
      0,
      _event(1, 'item.preview',
          data: _previewPayload(amount: null, amountKind: 'missing')),
    );
    await pumpEventQueue();
    final item = harness.store.preview!.items.single;
    expect(item.amountMissing, isTrue);
    expect(item.amount, isNull);
    harness.remote.closeStream(0);
    await future;
  });

  test('attempt.restarted voids every earlier preview', () async {
    final harness = _build();
    final future = harness.store.createBatch(_text, now: DateTime(2026, 10, 30, 9));
    await pumpEventQueue();
    final remote = harness.remote;
    remote.emit(0, _event(1, 'item.preview', data: _previewPayload()));
    await pumpEventQueue();
    expect(harness.store.preview!.items, hasLength(1));

    remote.emit(0, _event(2, 'attempt.restarted', attempt: 2));
    await pumpEventQueue();
    expect(harness.store.streamPhase, QuickEntryStreamPhase.retrying);
    expect(harness.store.preview!.items, isEmpty);
    expect(harness.store.preview!.attempt, 2);

    remote.emit(
      0,
      _event(3, 'item.preview',
          attempt: 2, data: _previewPayload(previewId: 'a2-i0')),
    );
    await pumpEventQueue();
    expect(harness.store.preview!.items.single.previewId, 'a2-i0');
    remote.closeStream(0);
    await future;
  });

  test('a payload that does not match the source text falls back locally',
      () async {
    final harness = _build();
    final future = harness.store.createBatch(_text, now: DateTime(2026, 10, 30, 9));
    await pumpEventQueue();
    harness.remote.emit(
      0,
      _event(1, 'item.preview',
          data: _previewPayload(start: 0, end: 3, quote: '完全不在原话里')),
    );
    await future;
    expect(harness.store.preview, isNull);
    expect(harness.store.batch!.mode, QuickEntryParseMode.local);
    expect(harness.store.batch!.candidates, hasLength(1));
    expect(harness.store.message, contains('生成数据无效'));
    expect(harness.storage.writes, 0);
  });

  test('EOF without a terminal event falls back locally', () async {
    final harness = _build();
    final future = harness.store.createBatch(_text, now: DateTime(2026, 10, 30, 9));
    await pumpEventQueue();
    harness.remote.emit(0, _event(1, 'item.preview', data: _previewPayload()));
    await pumpEventQueue();
    harness.remote.closeStream(0);
    await future;
    expect(harness.store.preview, isNull);
    expect(harness.store.batch!.mode, QuickEntryParseMode.local);
    expect(harness.store.message, contains('生成连接中断'));
  });

  test('an error event degrades with its fixed message', () async {
    final harness = _build();
    final future = harness.store.createBatch(_text, now: DateTime(2026, 10, 30, 9));
    await pumpEventQueue();
    harness.remote.emit(0,
        _event(1, 'error', data: {'code': 'llm_timeout', 'message': 'x'}));
    await future;
    expect(harness.store.batch!.mode, QuickEntryParseMode.local);
    expect(harness.store.message, contains('超时'));
  });

  test('needs_split is a valid completion, not a local degrade', () async {
    final harness = _build();
    final future = harness.store.createBatch(_text, now: DateTime(2026, 10, 30, 9));
    await pumpEventQueue();
    final requestId = harness.remote.requestIds.single;
    harness.remote.emit(
      0,
      _event(1, 'completed',
          data: _completed(requestId, status: 'needs_split', drafts: const [])),
    );
    expect(await future, isTrue);
    expect(harness.store.batch!.mode, QuickEntryParseMode.cloud);
    expect(harness.store.batch!.status, QuickEntryBatchStatus.needsSplit);
    expect(harness.store.batch!.candidates, isEmpty);
    expect(harness.store.message, isNull);
  });

  test('404 from the stream endpoint falls back to /agent/drafts once',
      () async {
    final harness = _build();
    harness.remote.connectError =
        const ApiFailure(ApiFailureKind.server, '未找到', statusCode: 404);
    final done = await harness.store.createBatch(_text,
        now: DateTime(2026, 10, 30, 9));
    expect(done, isTrue);
    expect(harness.remote.legacyCalls, 1);
    expect(harness.store.batch!.mode, QuickEntryParseMode.cloud);
    expect(harness.store.batch!.candidates, hasLength(1));
  });

  test('cancelling mid-stream clears everything and adopts nothing', () async {
    final harness = _build();
    final future = harness.store.createBatch(_text, now: DateTime(2026, 10, 30, 9));
    await pumpEventQueue();
    harness.remote.emit(0, _event(1, 'item.preview', data: _previewPayload()));
    await pumpEventQueue();
    expect(harness.store.preview!.items, hasLength(1));

    harness.store.cancelStream();
    expect(harness.store.streamPhase, QuickEntryStreamPhase.cancelled);
    expect(harness.store.preview, isNull);
    expect(harness.store.message, '已取消这次整理');

    await future;
    await pumpEventQueue();
    expect(harness.store.batch, isNull, reason: '取消不得降级成本地卡');
    expect(harness.store.isStreamLocked, isFalse);
    expect(harness.storage.writes, 0);
  });

  test('cancelling before the first frame behaves the same', () async {
    final harness = _build();
    final future = harness.store.createBatch(_text, now: DateTime(2026, 10, 30, 9));
    await pumpEventQueue();
    harness.store.cancelStream();
    expect(harness.store.streamPhase, QuickEntryStreamPhase.cancelled);
    await future;
    expect(harness.store.batch, isNull);
  });

  test('a new input makes the previous generation inert', () async {
    final harness = _build();
    // Keep the old connection open so its late frames can be injected.
    harness.remote.closeOnAbort = false;
    final first = harness.store.createBatch(_text, now: DateTime(2026, 10, 30, 9));
    await pumpEventQueue();
    harness.remote.emit(0, _event(1, 'item.preview', data: _previewPayload()));
    await pumpEventQueue();

    final second = harness.store.createBatch('买咖啡15元',
        now: DateTime(2026, 10, 30, 9));
    await pumpEventQueue();
    expect(harness.remote.streams, hasLength(2));

    // The superseded generation completes late: it must not be adopted.
    harness.remote.emit(
        0, _event(2, 'completed', data: _completed(harness.remote.requestIds[0])));
    await first;
    expect(harness.store.batch, isNull);
    expect(harness.store.preview!.sourceText, '买咖啡15元');

    harness.remote.closeOnAbort = true;
    harness.store.cancelStream();
    await second;
  });

  test('closing cloud parsing never opens a stream', () async {
    final harness = _build();
    await harness.store.setCloudParsingEnabled(false);
    final done = await harness.store.createBatch(_text,
        now: DateTime(2026, 10, 30, 9));
    expect(done, isTrue);
    expect(harness.remote.streams, isEmpty);
    expect(harness.remote.legacyCalls, 0);
    expect(harness.store.batch!.mode, QuickEntryParseMode.local);
  });

  test('editing, selecting and confirming are refused while streaming',
      () async {
    final harness = _build();
    final future = harness.store.createBatch(_text, now: DateTime(2026, 10, 30, 9));
    await pumpEventQueue();
    harness.remote.emit(0, _event(1, 'item.preview', data: _previewPayload()));
    await pumpEventQueue();

    harness.store.toggleCandidate('a1-i0', true);
    harness.store.selectAllExplicit();
    harness.store.removeCandidate('a1-i0');
    harness.store.updateCandidate(
        'a1-i0',
        const AgentDraft(
            amount: 1,
            type: TransactionType.expense,
            categoryId: null,
            accountId: null,
            date: '2026-10-30',
            note: '',
            confidence: .5));
    harness.store.addManualCandidate(9);
    expect(await harness.store.confirmBatch(), isFalse);
    expect(harness.store.canConfirmBatch, isFalse);
    expect(harness.store.batch, isNull);
    expect(harness.store.preview!.items, hasLength(1));

    harness.store.cancelStream();
    await future;
  });
}
