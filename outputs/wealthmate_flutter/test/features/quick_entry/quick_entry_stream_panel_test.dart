import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wealthmate_flutter/core/database/local_state_session.dart';
import 'package:wealthmate_flutter/data/local_repository.dart';
import 'package:wealthmate_flutter/data/sync_queue.dart';
import 'package:wealthmate_flutter/domain/models.dart';
import 'package:wealthmate_flutter/features/quick_entry/data/quick_entry_remote_data_source.dart';
import 'package:wealthmate_flutter/features/quick_entry/data/quick_entry_repository.dart';
import 'package:wealthmate_flutter/features/quick_entry/domain/quick_entry_stream.dart';
import 'package:wealthmate_flutter/features/quick_entry/state/quick_entry_store.dart';
import 'package:wealthmate_flutter/ui/theme.dart';
import 'package:wealthmate_flutter/ui/widgets/quick_entry_batch_panel.dart';

const _text = '中午吃饭32元，打车20元';

class _AtomicStore implements AtomicKeyValueStore {
  final Map<String, String> values = <String, String>{};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;

  @override
  Future<void> writeBatch(Map<String, String> batch) async =>
      values.addAll(batch);
}

class _FakeStreamRemote extends QuickEntryRemoteDataSource {
  final List<StreamController<QuickEntryStreamEvent>> streams =
      <StreamController<QuickEntryStreamEvent>>[];
  final List<String> requestIds = <String>[];

  @override
  bool get supportsStreaming => true;

  @override
  Stream<QuickEntryStreamEvent> createDraftsStream(
    Map<String, Object?> body, {
    required String requestId,
    required Future<void> abortTrigger,
  }) {
    requestIds.add(requestId);
    final controller = StreamController<QuickEntryStreamEvent>();
    streams.add(controller);
    abortTrigger.then((_) {
      if (!controller.isClosed) controller.close();
    });
    return controller.stream;
  }

  void emit(int index, QuickEntryStreamEvent event) => streams[index].add(event);
}

QuickEntryStreamEvent _event(int seq, String type,
        {Map<String, Object?> data = const <String, Object?> {}, int attempt = 1}) =>
    QuickEntryStreamEvent(seq: seq, attempt: attempt, type: type, data: data);

Map<String, Object?> _preview({
  String previewId = 'a1-i0',
  int ordinal = 0,
  String note = '午饭',
  String quote = '中午吃饭32元',
  int start = 0,
  int end = 7,
  String? amount = '32.00',
  String amountKind = 'exact',
  String? categoryHint = '餐饮',
}) =>
    {
      'preview_id': previewId,
      'ordinal': ordinal,
      'type': 'expense',
      'note': note,
      'source_quote': {'quote': quote, 'start': start, 'end': end},
      'amount_kind': amountKind,
      'amount': amount,
      'amount_range': null,
      'is_approximate': false,
      'currency': 'CNY',
      'date': '2026-10-30',
      'category_hint': categoryHint,
      'account_hint': null,
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

Map<String, Object?> _completed(String requestId) => {
      'result': {
        'schema_version': 1,
        'request_id': requestId,
        'status': 'ok',
        'engine': 'llm',
        'requires_confirmation': true,
        'drafts': [
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

({QuickEntryStore store, _FakeStreamRemote remote}) _build() {
  final session = LocalStateSession(
    local: LocalRepository(_AtomicStore()),
    queue: SyncQueue(),
  );
  final remote = _FakeStreamRemote();
  final store = QuickEntryStore(
    repository: QuickEntryRepository(session: session, remote: remote),
    initialState: _state(),
  );
  return (store: store, remote: remote);
}

Widget _app(QuickEntryStore store) => MaterialApp(
      theme: wealthMateTheme(),
      home: Scaffold(
        body: SingleChildScrollView(
          child: QuickEntryBatchPanel(store: store, state: _state()),
        ),
      ),
    );

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i += 1) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

void main() {
  testWidgets('only real events add preview rows', (tester) async {
    final harness = _build();
    final future = harness.store.createBatch(_text,
        now: DateTime(2026, 10, 30, 9));
    await tester.pumpWidget(_app(harness.store));
    await _settle(tester);

    expect(find.text('识别中 · 预览'), findsOneWidget);
    expect(find.text('正在从原话里整理事项…'), findsOneWidget);
    expect(find.text('取消'), findsOneWidget);

    // Time alone must never invent a card.
    await tester.pump(const Duration(seconds: 3));
    expect(find.text('午饭'), findsNothing);

    harness.remote.emit(0, _event(1, 'session.started'));
    harness.remote.emit(0, _event(2, 'generation.started'));
    harness.remote.emit(
      0,
      _event(3, 'item.preview',
          data: _preview(amount: null, amountKind: 'missing')),
    );
    await _settle(tester);

    expect(find.text('午饭'), findsOneWidget);
    expect(find.text('金额待补'), findsOneWidget);
    expect(find.text('餐饮 · 2026-10-30'), findsOneWidget);
    expect(find.text('「中午吃饭32元」'), findsOneWidget);
    // Read-only: no checkbox, no confirm button, no edit affordance.
    expect(find.byType(Checkbox), findsNothing);
    expect(find.textContaining('确认入账'), findsNothing);
    expect(find.byTooltip('修改'), findsNothing);
    expect(await harness.store.confirmBatch(), isFalse);

    harness.store.cancelStream();
    await _settle(tester);
    expect(find.text('识别中 · 预览'), findsNothing);
    await future;
  });

  testWidgets('completed replaces previews with editable cards in one frame',
      (tester) async {
    final harness = _build();
    final future = harness.store.createBatch(_text,
        now: DateTime(2026, 10, 30, 9));
    await tester.pumpWidget(_app(harness.store));
    await _settle(tester);

    harness.remote.emit(0, _event(1, 'session.started'));
    harness.remote.emit(0, _event(2, 'item.preview', data: _preview()));
    await _settle(tester);
    expect(find.text('识别中 · 预览'), findsOneWidget);

    harness.remote.emit(0,
        _event(3, 'completed', data: _completed(harness.remote.requestIds.single)));
    await _settle(tester);
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('识别中 · 预览'), findsNothing);
    expect(find.textContaining('午饭'), findsOneWidget);
    expect(find.byType(Checkbox), findsNWidgets(2));
    expect(find.textContaining('确认入账'), findsOneWidget);
    expect(find.byTooltip('修改'), findsNWidgets(2));
    expect(harness.store.isStreamLocked, isFalse);
    // Subscription cancellation needs the real event loop, not the fake clock.
    expect(await tester.runAsync(() => future), isTrue);
  });

  testWidgets('a second preview does not pull the user back to the bottom',
      (tester) async {
    final harness = _build();
    final future = harness.store.createBatch(_text,
        now: DateTime(2026, 10, 30, 9));
    await tester.pumpWidget(_app(harness.store));
    await _settle(tester);

    for (var index = 0; index < 3; index += 1) {
      harness.remote.emit(
        0,
        _event(index + 1, 'item.preview',
            data: _preview(previewId: 'a1-i$index', ordinal: index)),
      );
      await _settle(tester);
    }
    expect(find.text('午饭'), findsWidgets);

    harness.store.cancelStream();
    await _settle(tester);
    await future;
  });
}
