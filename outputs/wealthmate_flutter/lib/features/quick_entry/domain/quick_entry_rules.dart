import '../../../domain/finance_rules.dart';
import '../../../domain/models.dart';

class QuickEntryRules {
  static AgentDraft mergeRemoteDraft(
      AgentDraft localDraft, AgentDraft remoteDraft) {
    return localDraft.copyWith(
      amount: remoteDraft.amount > 0 ? remoteDraft.amount : localDraft.amount,
      type: remoteDraft.type,
      date: remoteDraft.date.isEmpty ? localDraft.date : remoteDraft.date,
      note: remoteDraft.note.isEmpty ? localDraft.note : remoteDraft.note,
      currency: FinanceRules.currencyFromText(localDraft.note) ??
          (remoteDraft.currency != 'CNY'
              ? remoteDraft.currency
              : localDraft.currency),
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
