import '../../../domain/finance_rules.dart';
import '../../../domain/models.dart';

class QuickEntryRules {
  static AgentDraft mergeRemoteDraft(
      AgentDraft localDraft, AgentDraft remoteDraft) {
    // The local parser is the user's first choice: keep its category/account
    // whenever it already resolved them. The remote response only fills gaps
    // left by the offline draft, and its confidence/missing-facts metadata is
    // used when those selections were still incomplete.
    final localSelectionsComplete =
        localDraft.categoryId != null && localDraft.accountId != null;
    final categoryId = localDraft.categoryId ?? remoteDraft.categoryId;
    final accountId = localDraft.accountId ?? remoteDraft.accountId;

    return localDraft.copyWith(
      amount: remoteDraft.amount > 0 ? remoteDraft.amount : localDraft.amount,
      type: remoteDraft.type,
      categoryId: categoryId,
      accountId: accountId,
      date: remoteDraft.date.isEmpty ? localDraft.date : remoteDraft.date,
      note: remoteDraft.note.isEmpty ? localDraft.note : remoteDraft.note,
      currency: FinanceRules.currencyFromText(localDraft.note) ??
          (remoteDraft.currency != 'CNY'
              ? remoteDraft.currency
              : localDraft.currency),
      confidence: localSelectionsComplete
          ? localDraft.confidence
          : (remoteDraft.confidence > 0
              ? remoteDraft.confidence
              : localDraft.confidence),
      missingFacts: localSelectionsComplete
          ? localDraft.missingFacts
          : remoteDraft.missingFacts,
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

}
