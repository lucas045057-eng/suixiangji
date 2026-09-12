import '../../../domain/finance_rules.dart';
import '../../../domain/models.dart';

class QuickEntryRules {
  static const double confirmationThreshold =
      FinanceRules.confirmationThreshold;

  static AgentDraft completeNaturalLanguageDraft(
    String text, {
    required DateTime now,
    required FinanceState state,
  }) {
    return FinanceRules.completeNaturalLanguageDraft(
      text,
      now: now,
      state: state,
    );
  }

  static AgentDraft mergeRemoteDraft(
      AgentDraft localDraft, AgentDraft remoteDraft) {
    return localDraft.copyWith(
      amount: remoteDraft.amount > 0 ? remoteDraft.amount : localDraft.amount,
      type: remoteDraft.type,
      date: remoteDraft.date.isEmpty ? localDraft.date : remoteDraft.date,
      note: remoteDraft.note.isEmpty ? localDraft.note : remoteDraft.note,
      currency: remoteDraft.currency,
    );
  }

  static AgentDraft validateEditedDraft(AgentDraft draft) {
    final missingFacts = <String>[];
    if (draft.amount <= 0) missingFacts.add('请输入金额');
    if (draft.categoryId == null) missingFacts.add('请选择分类');
    if (draft.accountId == null) missingFacts.add('请选择支付账户');
    return draft.copyWith(
      confidence: missingFacts.isEmpty ? .98 : .55,
      missingFacts: missingFacts,
    );
  }

  static bool canPost(AgentDraft draft) => FinanceRules.canPostDraft(draft);

  static String quickMemoryKey(String text) =>
      FinanceRules.quickMemoryKey(text);
}
