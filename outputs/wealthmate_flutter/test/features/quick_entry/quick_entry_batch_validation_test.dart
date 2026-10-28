import 'package:flutter_test/flutter_test.dart';
import 'package:wealthmate_flutter/domain/finance_rules.dart';
import 'package:wealthmate_flutter/domain/models.dart';
import 'package:wealthmate_flutter/features/quick_entry/domain/quick_entry_batch.dart';
import 'package:wealthmate_flutter/features/quick_entry/domain/quick_entry_context.dart';
import 'package:wealthmate_flutter/features/quick_entry/domain/quick_entry_response_validator.dart';
import 'package:wealthmate_flutter/features/quick_entry/domain/quick_entry_rules.dart';

const _text = '跟昨天差不多，吃饭32元';
const _fingerprint = 'fnv1a64:0123456789abcdef';
const _target = '2026-10-28';
const _reference = '2026-10-27';

Map<String, Object?> _sourceEvidence(
        {String text = _text,
        String quote = '吃饭32元',
        int start = 7,
        int end = 12}) =>
    {
      'kind': 'source_text',
      'quote': quote,
      'start': start,
      'end': end,
    };

Map<String, Object?> _draftJson({
  String id = 'd1',
  String source = 'explicit',
  String type = 'expense',
  Object? amount = '32.00',
  Map<String, Object?>? range,
  bool approximate = false,
  String currency = 'CNY',
  String date = _target,
  String note = '午饭',
  double confidence = 0.96,
  List<String> missing = const <String>[],
  bool selected = true,
  List<Map<String, Object?>>? evidence,
  Map<String, Object?>? derivation,
  String? categoryId,
  String? accountId,
}) =>
    {
      'client_draft_id': id,
      'source': source,
      'type': type,
      'amount': amount,
      'amount_range': range,
      'is_approximate': approximate,
      'currency': currency,
      'category_hint': null,
      'category_id': categoryId,
      'account_hint': null,
      'account_id': accountId,
      'date': date,
      'note': note,
      'confidence': confidence,
      'missing_facts': missing,
      'selected_by_default': selected,
      'evidence': evidence ?? [_sourceEvidence()],
      'derivation': derivation,
    };

Map<String, Object?> _inferredJson({String? fingerprint = _fingerprint}) => {
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
      'date': _target,
      'note': '其他支出（按昨日推算）',
      'confidence': 0.6,
      'missing_facts': const ['请选择分类'],
      'selected_by_default': false,
      'evidence': [
        _sourceEvidence(quote: '跟昨天差不多', start: 0, end: 6),
        {
          'kind': 'ledger_context',
          'context_path': 'currencies.CNY.reference_day',
          'reference_date': _reference,
        },
      ],
      'derivation': {
        'kind': 'previous_day_expense_residual',
        'reference_date': _reference,
        'target_date': _target,
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
        'context_fingerprint': fingerprint ?? _fingerprint,
      },
    };

Map<String, Object?> _response({
  List<Map<String, Object?>>? drafts,
  List<Map<String, Object?>> notices = const [],
  String status = 'ok',
  Object? requestId = 'req-1',
}) =>
    {
      'schema_version': 1,
      'request_id': requestId,
      'status': status,
      'engine': 'llm',
      'requires_confirmation': true,
      'drafts': drafts ?? [_draftJson()],
      'notices': notices,
    };

QuickEntryValidatedResponse _validate(
  Map<String, Object?> json, {
  String text = _text,
  String? fingerprint = _fingerprint,
  String target = _target,
  String reference = _reference,
}) =>
    QuickEntryResponseValidator.validate(
      json,
      requestId: 'req-1',
      sourceText: text,
      contextFingerprint: fingerprint,
      targetDate: target,
      referenceDate: reference,
    );

void _expectInvalid(
  Map<String, Object?> json, {
  String text = _text,
  String? fingerprint = _fingerprint,
}) {
  expect(
    () => _validate(json, text: text, fingerprint: fingerprint),
    throwsA(isA<QuickEntryResponseInvalid>()),
  );
}

FinanceState _state() => const FinanceState(
      preferredCurrency: 'CNY',
      defaultAccountId: 'alipay',
      accounts: [
        Account(id: 'alipay', name: '支付宝', type: AccountType.asset),
        Account(
            id: 'usd-wallet',
            name: '美元钱包',
            type: AccountType.asset,
            currency: 'USD'),
      ],
      categories: [
        Category(id: 'food', name: '餐饮'),
        Category(id: 'transport', name: '交通'),
        Category(id: 'salary', name: '工资', type: TransactionType.income),
      ],
    );

QuickEntryCandidate _candidate({
  required String id,
  required AgentDraft draft,
  bool selected = true,
}) =>
    QuickEntryCandidate(id: id, draft: draft, selected: selected);

AgentDraft _draft({
  double amount = 32,
  String? categoryId = 'food',
  String? accountId = 'alipay',
  String quote = '吃饭32元',
  AgentDraftSource source = AgentDraftSource.explicit,
  bool isApproximate = false,
  DraftAmountRange? range,
  DraftDerivation? derivation,
}) =>
    AgentDraft(
      amount: amount,
      type: TransactionType.expense,
      categoryId: categoryId,
      accountId: accountId,
      date: _target,
      note: '午饭',
      confidence: .96,
      source: source,
      isApproximate: isApproximate,
      amountRange: range,
      derivation: derivation,
      evidence: [
        DraftEvidence(
            kind: DraftEvidenceKind.sourceText,
            quote: quote,
            start: 0,
            end: quote.length),
      ],
    );

void main() {
  group('response validator', () {
    test('accepts code point offsets around a surrogate pair', () {
      const text = '😀吃饭40元';
      final result = _validate(
        _response(drafts: [
          _draftJson(
            amount: '40.00',
            note: '吃饭',
            evidence: [
              _sourceEvidence(text: text, quote: '吃饭40元', start: 1, end: 6),
            ],
          ),
        ]),
        text: text,
      );

      expect(result.drafts, hasLength(1));
      expect(result.drafts.single.draft.amount, 40);
      expect(result.drafts.single.draft.evidence.single.quote, '吃饭40元');
    });

    test('rejects UTF-16 offsets that only look right for ASCII', () {
      const text = '😀吃饭40元';
      _expectInvalid(
        _response(drafts: [
          _draftJson(
            amount: '40.00',
            evidence: [
              _sourceEvidence(text: text, quote: '吃饭40元', start: 2, end: 7),
            ],
          ),
        ]),
        text: text,
      );
    });

    test('accepts an inferred card with evidence and derivation', () {
      final result = _validate(_response(drafts: [
        _draftJson(amount: null, missing: const ['请输入金额']),
        _inferredJson(),
      ]));

      expect(result.drafts, hasLength(2));
      final inferred = result.drafts.last.draft;
      expect(inferred.isInferred, isTrue);
      expect(inferred.derivation?.result, 87.5);
      expect(inferred.derivation?.operands, hasLength(3));
      expect(inferred.amountRange, isNull);
      expect(result.drafts.first.draft.amount, 0);
    });

    test('rejects an inferred card without derivation', () {
      final draft = _inferredJson()
        ..['derivation'] = null
        ..['client_draft_id'] = 'd3';
      _expectInvalid(_response(drafts: [_inferredJson(), draft]));
    });

    test('rejects a derivation whose fingerprint does not match', () {
      _expectInvalid(_response(drafts: [
        _draftJson(),
        _inferredJson(fingerprint: 'fnv1a64:ffffffffffffffff'),
      ]));
    });

    test('rejects an explicit card carrying a derivation', () {
      final draft = _draftJson()..['derivation'] = _inferredJson()['derivation'];
      _expectInvalid(_response(drafts: [draft]));
    });

    test('rejects more than eight cards', () {
      _expectInvalid(_response(drafts: [
        for (var index = 0; index < 9; index += 1)
          _draftJson(id: 'd$index'),
      ]));
    });

    test('rejects an amount outside its declared range', () {
      _expectInvalid(_response(drafts: [
        _draftJson(
          amount: '60.00',
          approximate: true,
          range: {
            'lower': '40.00',
            'upper': '50.00',
            'lower_inclusive': true,
            'upper_inclusive': false,
          },
        ),
      ]));
    });

    test('rejects a range that is not marked approximate', () {
      _expectInvalid(_response(drafts: [
        _draftJson(
          amount: '45.00',
          range: {
            'lower': '40.00',
            'upper': '50.00',
            'lower_inclusive': true,
            'upper_inclusive': false,
          },
        ),
      ]));
    });

    test('rejects needs_split responses that still carry drafts', () {
      _expectInvalid(_response(status: 'needs_split'));
    });

    test('accepts needs_split with a notice and no drafts', () {
      final result = _validate(_response(
        drafts: const [],
        status: 'needs_split',
        notices: const [
          {'code': 'needs_split', 'message': '内容超过8个独立事项，请分次说。'}
        ],
      ));
      expect(result.status, QuickEntryBatchStatus.needsSplit);
      expect(result.notices.single.code, 'needs_split');
    });

    test('rejects a mismatched request id and unknown engine', () {
      _expectInvalid(_response(requestId: 'other'));
      final wrongEngine = _response()..['engine'] = 'rules';
      _expectInvalid(wrongEngine);
    });
  });

  group('ledger context builder', () {
    FinanceState contextState() => FinanceState(
          preferredCurrency: 'CNY',
          accounts: const [
            Account(id: 'alipay', name: '支付宝', type: AccountType.asset),
          ],
          categories: const [
            Category(id: 'food', name: '餐饮'),
            Category(id: 'transport', name: '交通'),
          ],
          transactions: const [
            FinanceTransaction(
                id: 'r1',
                date: '2026-10-27',
                type: TransactionType.expense,
                amount: 45,
                categoryId: 'food'),
            FinanceTransaction(
                id: 'r2',
                date: '2026-10-27',
                type: TransactionType.expense,
                amount: 87.5,
                categoryId: 'transport'),
            FinanceTransaction(
                id: 'deleted',
                date: '2026-10-27',
                type: TransactionType.expense,
                amount: 100,
                categoryId: 'food',
                deletedAt: '2026-10-27T20:00:00'),
            FinanceTransaction(
                id: 'transfer',
                date: '2026-10-27',
                type: TransactionType.transfer,
                amount: 200,
                fromAccountId: 'alipay',
                toAccountId: 'other'),
            FinanceTransaction(
                id: 'usd',
                date: '2026-10-27',
                type: TransactionType.expense,
                amount: 10,
                currency: 'USD',
                categoryId: 'food'),
            FinanceTransaction(
                id: 'today',
                date: '2026-10-28',
                type: TransactionType.expense,
                amount: 12,
                categoryId: 'food'),
          ],
        );

    test('aggregates only live expenses for the target and previous day', () {
      final context = QuickEntryContextBuilder.build(
          state: contextState(), now: DateTime(2026, 10, 28, 10));
      expect(context.targetDate, '2026-10-28');
      expect(context.referenceDate, '2026-10-27');
      final cny = context.currency('CNY')!;
      expect(cny.referenceDay.count, 2);
      expect(cny.referenceDay.cents, 13250);
      expect(cny.targetDay.cents, 1200);
      expect(cny.targetDay.count, 1);
      expect(cny.referenceDay.categoryTotals.map((item) => item.categoryId),
          ['food', 'transport']);
      expect(cny.referenceDay.categoryTotals.first.categoryName, '餐饮');
      final usd = context.currency('USD')!;
      expect(usd.referenceDay.cents, 1000);
      expect(context.currencies.map((item) => item.currency), ['CNY', 'USD']);
      expect(context.toRequestJson()['status'], 'ready');
    });

    test('fingerprint is stable and changes when the aggregate changes', () {
      final first = QuickEntryContextBuilder.build(
          state: contextState(), now: DateTime(2026, 10, 28, 10));
      final second = QuickEntryContextBuilder.build(
          state: contextState(), now: DateTime(2026, 10, 28, 22));
      expect(first.fingerprint, second.fingerprint);
      final mutated = contextState().copyWith(transactions: [
        ...contextState().transactions.where((item) => item.id != 'today'),
        const FinanceTransaction(
            id: 'today2',
            date: '2026-10-28',
            type: TransactionType.expense,
            amount: 99,
            categoryId: 'food'),
      ]);
      final third = QuickEntryContextBuilder.build(
          state: mutated, now: DateTime(2026, 10, 28, 10));
      expect(third.fingerprint, isNot(first.fingerprint));
    });

    test('crosses month boundaries for the reference day', () {
      final context = QuickEntryContextBuilder.build(
          state: _state(), now: DateTime(2026, 10, 1, 8));
      expect(context.targetDate, '2026-10-01');
      expect(context.referenceDate, '2026-09-30');
    });
  });

  group('local completion', () {
    test('keeps a remote category only when it exists locally and matches',
        () {
      final base = _draft(categoryId: 'salary');
      final completed = QuickEntryRules.completeCloudDraft(
        base,
        _state(),
        now: DateTime(2026, 10, 28),
        sourceText: _text,
      );
      expect(completed.categoryId, 'food');
      expect(completed.accountId, 'alipay');
      expect(completed.missingFacts, isEmpty);
    });

    test('uses the remote account when it exists with the same currency', () {
      final base = _draft(accountId: 'usd-wallet').copyWith(currency: 'USD');
      final completed = QuickEntryRules.completeCloudDraft(
        base,
        _state(),
        now: DateTime(2026, 10, 28),
        sourceText: _text,
      );
      expect(completed.accountId, 'usd-wallet');
    });

    test('drops an unknown remote account and lets the default fill the gap',
        () {
      final completed = QuickEntryRules.completeCloudDraft(
        _draft(accountId: 'ghost'),
        _state(),
        now: DateTime(2026, 10, 28),
        sourceText: _text,
      );
      expect(completed.accountId, 'alipay');
    });

    test('user edits keep provenance but drop the spoken range', () {
      const range = DraftAmountRange(lower: 40, upper: 50);
      final previous = _draft(amount: 45, isApproximate: true, range: range)
          .copyWith(
        derivation: const DraftDerivation(
          kind: 'previous_day_expense_residual',
          referenceDate: _reference,
          targetDate: _target,
          operands: [
            DraftOperand(
                key: 'reference_expense', label: '昨日已记消费', amount: 132.5)
          ],
          formula: 'reference_expense - target_recorded - explicit_candidates',
          result: 87.5,
          contextFingerprint: _fingerprint,
        ),
      );

      final edited = QuickEntryRules.applyUserEdit(
          previous, previous.copyWith(amount: 50));
      expect(edited.amount, 50);
      expect(edited.isApproximate, isFalse);
      expect(edited.amountRange, isNull);
      expect(edited.evidence, isNotEmpty);
      expect(edited.derivation?.result, 87.5);

      final untouched =
          QuickEntryRules.applyUserEdit(previous, previous.copyWith(note: '改'));
      expect(untouched.isApproximate, isTrue);
      expect(untouched.amountRange, range);
    });
  });

  group('QuickMemory boundary', () {
    test('learns only explicit cards, keyed by their own evidence phrase', () {
      final memories = QuickEntryRules.learnedMemories(
        confirmed: [
          _candidate(id: 'd1', draft: _draft()),
          _candidate(
            id: 'd2',
            draft: _draft(
              amount: 87.5,
              categoryId: null,
              quote: '跟昨天差不多',
              source: AgentDraftSource.inferred,
            ),
          ),
        ],
        now: DateTime(2026, 10, 28),
      );
      expect(memories, hasLength(1));
      expect(memories.single.key, FinanceRules.quickMemoryKey('吃饭32元'));
      expect(memories.single.categoryId, 'food');
      expect(memories.single.accountId, 'alipay');
    });

    test('conflicting mappings for one key are dropped', () {
      final memories = QuickEntryRules.learnedMemories(
        confirmed: [
          _candidate(id: 'd1', draft: _draft(categoryId: 'food')),
          _candidate(id: 'd2', draft: _draft(categoryId: 'transport')),
        ],
        now: DateTime(2026, 10, 28),
      );
      expect(memories, isEmpty);
    });

    test('mergeMemories replaces the same key and keeps the rest', () {
      final existing = [
        const QuickMemory(key: 'old', categoryId: 'food'),
        QuickMemory(
            key: FinanceRules.quickMemoryKey('吃饭32元'), categoryId: 'food'),
      ];
      final merged = QuickEntryRules.mergeMemories(existing, [
        QuickMemory(
            key: FinanceRules.quickMemoryKey('吃饭32元'),
            categoryId: 'transport',
            accountId: 'alipay'),
      ]);
      expect(merged, hasLength(2));
      expect(
          merged
              .firstWhere((item) => item.key == existing.last.key)
              .categoryId,
          'transport');
      expect(merged.first.key, 'old');
    });
  });

  test('local fallback produces one explicit card and marks references', () {
    final batch = QuickEntryRules.localBatch(
      '今天跟昨天差不多，吃饭32元',
      _state(),
      now: DateTime(2026, 10, 28, 10),
      batchId: 'local-1',
      reason: '云端 AI 解析已关闭，只使用本地规则',
    );

    expect(batch.mode, QuickEntryParseMode.local);
    expect(batch.candidates, hasLength(1));
    expect(batch.candidates.single.selected, isTrue);
    expect(batch.candidates.single.draft.isInferred, isFalse);
    expect(batch.candidates.single.draft.evidence.single.quote,
        '今天跟昨天差不多，吃饭32元');
    expect(batch.candidates.single.draft.amount, 32);
    expect(batch.notices.map((item) => item.code),
        containsAll(['cloud_unavailable', 'reference_not_converted']));
    expect(batch.contextFingerprint, isNull);
  });
}
