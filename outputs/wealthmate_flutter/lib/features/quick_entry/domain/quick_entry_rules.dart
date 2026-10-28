import '../../../domain/finance_rules.dart';
import '../../../domain/models.dart';
import 'quick_entry_batch.dart';
import 'quick_entry_wire.dart';

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

  /// Fills a validated cloud draft with local categories, accounts and
  /// learned choices. The remote ids are only accepted when they exist
  /// locally with a matching type; the local default account only fills a gap.
  static AgentDraft completeCloudDraft(
    AgentDraft draft,
    FinanceState state, {
    required DateTime now,
    required String sourceText,
  }) {
    final quote = draft.primaryQuote ?? sourceText;
    final local =
        FinanceRules.completeNaturalLanguageDraft(quote, now: now, state: state);
    final categoryId = _remoteCategory(draft, state) ?? local.categoryId;
    final accountId = _remoteAccount(draft, state) ?? local.accountId;
    return withCompleteness(draft.copyWith(
      categoryId: categoryId,
      clearCategoryId: categoryId == null,
      accountId: accountId,
      clearAccountId: accountId == null,
    ));
  }

  static AgentDraft withCompleteness(AgentDraft draft) {
    final missingFacts = <String>[];
    if (draft.amount <= 0) missingFacts.add('请输入金额');
    if (draft.categoryId == null) missingFacts.add('请选择分类');
    if (draft.accountId == null) missingFacts.add('请选择支付账户');
    return draft.copyWith(
      // Inferred cards keep the server's diagnostic confidence; it is never a
      // gate for confirmation.
      confidence:
          draft.isInferred ? draft.confidence : (missingFacts.isEmpty ? .98 : .55),
      missingFacts: missingFacts,
    );
  }

  /// A user edit keeps the card's provenance: evidence and推导 are never lost.
  /// Changing the amount turns the value into the user's exact number, so the
  /// spoken range and the "约" marker are dropped.
  static AgentDraft applyUserEdit(AgentDraft previous, AgentDraft edited) {
    final amountChanged = edited.amount != previous.amount;
    final evidence =
        edited.evidence.isEmpty ? previous.evidence : edited.evidence;
    final merged = edited.copyWith(
      source: previous.source,
      evidence: evidence,
      derivation: previous.derivation,
      isApproximate: amountChanged ? false : previous.isApproximate,
      amountRange: amountChanged ? null : previous.amountRange,
      clearAmountRange: amountChanged,
    );
    return withCompleteness(merged);
  }

  static bool isComplete(AgentDraft draft) =>
      draft.amount > 0 &&
      draft.categoryId != null &&
      draft.accountId != null &&
      draft.type != TransactionType.transfer &&
      isIsoDate(draft.date) &&
      RegExp(r'^[A-Z]{3}$').hasMatch(draft.currency);

  static String? incompleteReason(AgentDraft draft) {
    if (draft.amount <= 0) return '缺金额';
    if (draft.categoryId == null) return '缺分类';
    if (draft.accountId == null) return '缺支付账户';
    if (!isIsoDate(draft.date)) return '日期不正确';
    if (!RegExp(r'^[A-Z]{3}$').hasMatch(draft.currency)) return '币种不正确';
    if (draft.type == TransactionType.transfer) return '转账请走手动流程';
    return null;
  }

  /// QuickMemory learning boundary: only confirmed explicit cards with a
  /// stable source quote are learned. Inferred cards never are, and a key that
  /// maps to conflicting choices inside one batch is dropped entirely.
  static List<QuickMemory> learnedMemories({
    required List<QuickEntryCandidate> confirmed,
    required DateTime now,
  }) {
    final mappings = <String, Set<(String?, String?)>>{};
    for (final candidate in confirmed) {
      if (candidate.isInferred) continue;
      final quote = candidate.draft.primaryQuote;
      if (quote == null) continue;
      final key = FinanceRules.quickMemoryKey(quote);
      if (key.isEmpty) continue;
      final categoryId = candidate.draft.categoryId;
      final accountId = candidate.draft.accountId;
      if (categoryId == null && accountId == null) continue;
      (mappings[key] ??= <(String?, String?)>{})
          .add((categoryId, accountId));
    }
    final updatedAt = now.toIso8601String();
    return [
      for (final entry in mappings.entries)
        if (entry.value.length == 1)
          QuickMemory(
            key: entry.key,
            categoryId: entry.value.single.$1,
            accountId: entry.value.single.$2,
            updatedAt: updatedAt,
          ),
    ];
  }

  static List<QuickMemory> mergeMemories(
      List<QuickMemory> existing, List<QuickMemory> learned) {
    if (learned.isEmpty) return existing;
    final keys = {for (final memory in learned) memory.key};
    return [
      ...existing.where((memory) => !keys.contains(memory.key)),
      ...learned,
    ];
  }

  /// Local fallback: one explicit card from the deterministic rules, with the
  /// user's own words as its evidence. Local mode never infers amounts.
  static QuickEntryBatch localBatch(
    String text,
    FinanceState state, {
    required DateTime now,
    required String batchId,
    String? reason,
  }) {
    final trimmed = text.trim();
    final draft =
        FinanceRules.completeNaturalLanguageDraft(trimmed, now: now, state: state);
    final candidateDraft = withCompleteness(draft.copyWith(
      source: AgentDraftSource.explicit,
      evidence: [
        DraftEvidence(
          kind: DraftEvidenceKind.sourceText,
          quote: trimmed,
          start: 0,
          end: codePointLength(trimmed),
        ),
      ],
    ));
    return QuickEntryBatch(
      id: batchId,
      sourceText: trimmed,
      mode: QuickEntryParseMode.local,
      targetDate: dateKey(now),
      referenceDate: dateKey(now.subtract(const Duration(days: 1))),
      notices: [
        if (reason != null)
          QuickEntryNotice(code: 'cloud_unavailable', message: reason),
        if (_mentionsPreviousDayReference(trimmed))
          const QuickEntryNotice(
            code: 'reference_not_converted',
            message: '「跟昨天比」这类参照需要云端解析，本次未折算。',
          ),
      ],
      candidates: [
        QuickEntryCandidate(
          id: 'local-1',
          draft: candidateDraft,
          selected: true,
        ),
      ],
    );
  }

  static bool _mentionsPreviousDayReference(String text) =>
      RegExp(r'跟昨天|和昨天|与昨天|同昨天|跟昨日|比昨天|差不多').hasMatch(text);

  static String? _remoteCategory(AgentDraft draft, FinanceState state) {
    final categoryId = draft.categoryId;
    if (categoryId == null) return null;
    for (final category in state.categories) {
      if (category.id != categoryId) continue;
      if (!category.active) return null;
      return category.type == draft.type ? categoryId : null;
    }
    return null;
  }

  static String? _remoteAccount(AgentDraft draft, FinanceState state) {
    final accountId = draft.accountId;
    if (accountId == null) return null;
    for (final account in state.accounts) {
      if (account.id != accountId) continue;
      if (!account.isActive) return null;
      return account.currency.toUpperCase() == draft.currency.toUpperCase()
          ? accountId
          : null;
    }
    return null;
  }
}
