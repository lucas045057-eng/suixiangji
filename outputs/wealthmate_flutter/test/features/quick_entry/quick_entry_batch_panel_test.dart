import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wealthmate_flutter/core/database/local_state_session.dart';
import 'package:wealthmate_flutter/data/local_repository.dart';
import 'package:wealthmate_flutter/data/sync_queue.dart';
import 'package:wealthmate_flutter/domain/models.dart';
import 'package:wealthmate_flutter/features/quick_entry/data/quick_entry_remote_data_source.dart';
import 'package:wealthmate_flutter/features/quick_entry/data/quick_entry_repository.dart';
import 'package:wealthmate_flutter/features/quick_entry/state/quick_entry_store.dart';
import 'package:wealthmate_flutter/ui/theme.dart';
import 'package:wealthmate_flutter/ui/widgets/quick_entry_batch_panel.dart';

const _text = '跟昨天差不多，吃饭32元';

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

class _FakeRemote extends QuickEntryRemoteDataSource {
  _FakeRemote(this.draftsFor);

  final List<Map<String, Object?>> Function(Map<String, Object?> request)
      draftsFor;

  @override
  Future<Map<String, Object?>> createDrafts(Map<String, Object?> body) async =>
      {
        'schema_version': 1,
        'request_id': body['request_id'],
        'status': 'ok',
        'engine': 'llm',
        'requires_confirmation': true,
        'drafts': draftsFor(body),
        'notices': const [],
      };
}

Map<String, Object?> _sourceEvidence(String quote, int start, int end) => {
      'kind': 'source_text',
      'quote': quote,
      'start': start,
      'end': end,
    };

Map<String, Object?> _explicit(Map<String, Object?> request) => {
      'client_draft_id': 'd1',
      'source': 'explicit',
      'type': 'expense',
      'amount': '32.00',
      'amount_range': null,
      'is_approximate': false,
      'currency': 'CNY',
      'category_hint': null,
      'category_id': 'food',
      'account_hint': null,
      'account_id': 'alipay',
      'date': request['local_today'],
      'note': '吃饭',
      'confidence': 0.96,
      'missing_facts': const [],
      'selected_by_default': true,
      'evidence': [_sourceEvidence('吃饭32元', 7, 12)],
      'derivation': null,
    };

Map<String, Object?> _inferred(Map<String, Object?> request) {
  final context = (request['ledger_context'] as Map).cast<String, Object?>();
  return {
    'client_draft_id': 'd2',
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

FinanceState _state() => const FinanceState(
      currentMonth: '2026-10',
      preferredCurrency: 'CNY',
      defaultAccountId: 'alipay',
      accounts: [
        Account(id: 'alipay', name: '支付宝', type: AccountType.asset),
      ],
      categories: [Category(id: 'food', name: '餐饮')],
    );

QuickEntryStore _store(List<Map<String, Object?>> Function(
        Map<String, Object?> request) draftsFor) {
  final session = LocalStateSession(
    local: LocalRepository(_AtomicStore()),
    queue: SyncQueue(),
  );
  return QuickEntryStore(
    repository: QuickEntryRepository(
      session: session,
      remote: _FakeRemote(draftsFor),
    ),
    initialState: _state(),
  );
}

void main() {
  testWidgets('batch panel shows provenance and confirms selected cards',
      (tester) async {
    final store = _store((request) => [_explicit(request), _inferred(request)]);
    final state = _state();
    await store.createBatch(_text, now: DateTime(2026, 10, 28, 10));

    await tester.pumpWidget(MaterialApp(
      theme: wealthMateTheme(),
      home: Scaffold(
        body: SingleChildScrollView(
          child: QuickEntryBatchPanel(store: store, state: state),
        ),
      ),
    ));

    expect(find.text('已整理成待确认草稿'), findsOneWidget);
    expect(find.text('云端 AI'), findsOneWidget);
    expect(find.text('明确'), findsOneWidget);
    expect(find.text('推算'), findsOneWidget);
    expect(find.text('确认入账'), findsOneWidget);
    expect(store.selectedCandidates, hasLength(1));

    await tester.tap(find.byTooltip('查看依据').last);
    await tester.pumpAndSettle();
    expect(find.textContaining('昨日已记消费'), findsWidgets);
    expect(find.textContaining('推算卡默认不勾选'), findsOneWidget);

    await tester.tap(find.text('确认入账'));
    await tester.pumpAndSettle();

    expect(store.state.transactions, hasLength(1));
    expect(store.state.transactions.single.amount, 32);
  });

  testWidgets('an incomplete selected card keeps the batch button disabled',
      (tester) async {
    final store = _store((request) => [
          {
            ..._explicit(request),
            'amount': null,
            'missing_facts': const ['请输入金额'],
          }
        ]);
    final state = _state();
    await store.createBatch(_text, now: DateTime(2026, 10, 28, 10));

    await tester.pumpWidget(MaterialApp(
      theme: wealthMateTheme(),
      home: Scaffold(
        body: SingleChildScrollView(
          child: QuickEntryBatchPanel(store: store, state: state),
        ),
      ),
    ));

    expect(find.text('第1张卡待补全'), findsOneWidget);
    final button = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(button.onPressed, isNull);
    expect(find.text('待补全：缺金额'), findsOneWidget);

    await tester.tap(find.byTooltip('修改'));
    await tester.pumpAndSettle();
    expect(find.text('修改快捷记'), findsOneWidget);
  });
}
