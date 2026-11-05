import 'package:flutter_test/flutter_test.dart';
import 'package:wealthmate_flutter/core/database/local_state_session.dart';
import 'package:wealthmate_flutter/data/local_repository.dart';
import 'package:wealthmate_flutter/data/sync_queue.dart';
import 'package:wealthmate_flutter/domain/date_text.dart';
import 'package:wealthmate_flutter/domain/finance_rules.dart';
import 'package:wealthmate_flutter/domain/models.dart';
import 'package:wealthmate_flutter/features/quick_entry/data/quick_entry_repository.dart';

class _Atomic implements AtomicKeyValueStore {
  final Map<String, String> values = <String, String>{};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;

  @override
  Future<void> writeBatch(Map<String, String> batch) async {
    values.addAll(batch);
  }
}

AgentDraft _draft(String date) => AgentDraft(
      amount: 19.8,
      type: TransactionType.expense,
      categoryId: 'lunch',
      accountId: 'wechat',
      date: date,
      note: '中午',
      currency: 'CNY',
      confidence: .98,
    );

void main() {
  test('the single-draft gate rejects non-ISO date text', () {
    expect(isIsoDate('2026-11-04'), isTrue);
    expect(isIsoDate('2026年11月4日'), isFalse);
    expect(FinanceRules.canPostDraft(_draft('2026年11月4日')), isFalse);
    expect(FinanceRules.canPostDraft(_draft('2026/11/04')), isFalse);
    expect(FinanceRules.canPostDraft(_draft('2026-11-04')), isTrue);
  });

  test('transactionFromDraft stamps occurredAt for the single-draft path', () {
    final session = LocalStateSession(
      local: LocalRepository(_Atomic()),
      queue: SyncQueue(),
    );
    final repository = QuickEntryRepository(session: session);
    final transaction = repository.transactionFromDraft(_draft('2026-11-04'));

    expect(transaction.date, '2026-11-04');
    expect(transaction.occurredAt, isNotNull);
    expect(transaction.occurredAt, startsWith('2026-11-04T'));
  });
}
