import 'package:flutter_test/flutter_test.dart';
import 'package:wealthmate_flutter/domain/models.dart';
import 'package:wealthmate_flutter/features/quick_entry/domain/quick_entry_rules.dart';

void main() {
  test('remote draft fills unresolved selections and metadata', () {
    const local = AgentDraft(
      amount: 30,
      type: TransactionType.expense,
      categoryId: null,
      accountId: null,
      date: '2026-09-04',
      note: 'local note',
      currency: 'CNY',
      confidence: .55,
      missingFacts: ['local selection missing'],
    );
    const remote = AgentDraft(
      amount: 31,
      type: TransactionType.income,
      categoryId: 'remote-category',
      accountId: 'remote-account',
      date: '2026-09-05',
      note: 'remote note',
      currency: 'USD',
      confidence: .98,
      missingFacts: const <String>[],
    );

    final merged = QuickEntryRules.mergeRemoteDraft(local, remote);

    expect(merged.amount, 31);
    expect(merged.type, TransactionType.income);
    expect(merged.date, '2026-09-05');
    expect(merged.note, 'remote note');
    expect(merged.currency, 'USD');
    expect(merged.categoryId, 'remote-category');
    expect(merged.accountId, 'remote-account');
    expect(merged.confidence, .98);
    expect(merged.missingFacts, isEmpty);
  });

  test('local selections and metadata remain authoritative when resolved', () {
    const local = AgentDraft(
      amount: 30,
      type: TransactionType.expense,
      categoryId: 'local-category',
      accountId: 'local-account',
      date: '2026-09-04',
      note: 'local note',
      confidence: .91,
      missingFacts: const <String>[],
    );
    const remote = AgentDraft(
      amount: 31,
      type: TransactionType.income,
      categoryId: 'remote-category',
      accountId: 'remote-account',
      date: '2026-09-05',
      note: 'remote note',
      confidence: .2,
      missingFacts: ['remote selection missing'],
    );

    final merged = QuickEntryRules.mergeRemoteDraft(local, remote);

    expect(merged.categoryId, 'local-category');
    expect(merged.accountId, 'local-account');
    expect(merged.confidence, .91);
    expect(merged.missingFacts, isEmpty);
  });

  test('remote missing facts pass through while local selections are unresolved',
      () {
    const local = AgentDraft(
      amount: 0,
      type: TransactionType.expense,
      categoryId: null,
      accountId: null,
      date: '2026-09-04',
      note: 'local note',
      confidence: .35,
      missingFacts: ['local amount missing'],
    );
    const remote = AgentDraft(
      amount: 0,
      type: TransactionType.expense,
      categoryId: null,
      accountId: null,
      date: '',
      note: '',
      confidence: .72,
      missingFacts: ['remote account missing'],
    );

    final merged = QuickEntryRules.mergeRemoteDraft(local, remote);

    expect(merged.confidence, .72);
    expect(merged.missingFacts, ['remote account missing']);
  });
}
