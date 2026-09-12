import '../../../core/database/local_state_session.dart';
import '../../../data/api_client.dart';
import '../../../domain/models.dart';
import '../domain/quick_entry_rules.dart';
import 'quick_entry_remote_data_source.dart';

typedef QuickMemoriesUpdater = Future<void> Function(
    List<QuickMemory> memories);

class QuickEntryRepository {
  QuickEntryRepository({
    required this.session,
    this.remote,
    this.onQuickMemoriesChanged,
  });

  final LocalStateSession session;
  final QuickEntryRemoteDataSource? remote;
  final QuickMemoriesUpdater? onQuickMemoriesChanged;
  bool remoteFallbackUsed = false;

  ApiClient? get api => remote?.api;

  Future<AgentDraft> createDraft(
    String text,
    FinanceState context, {
    DateTime? now,
  }) async {
    remoteFallbackUsed = false;
    final localDraft = QuickEntryRules.completeNaturalLanguageDraft(
      text,
      now: now ?? DateTime.now(),
      state: context,
    );
    final source = remote;
    if (source == null) return localDraft;
    try {
      final remoteDraft = await source.createDraft(text);
      return QuickEntryRules.mergeRemoteDraft(localDraft, remoteDraft);
    } on ApiFailure {
      remoteFallbackUsed = true;
      return localDraft;
    }
  }

  FinanceTransaction transactionFromDraft(AgentDraft draft) {
    final id = 'tx-${DateTime.now().microsecondsSinceEpoch}';
    return FinanceTransaction(
      id: id,
      date: draft.date,
      type: draft.type,
      amount: draft.amount,
      currency: draft.currency,
      categoryId: draft.categoryId,
      accountId: draft.accountId,
      fromAccountId: draft.fromAccountId,
      toAccountId: draft.toAccountId,
      note: draft.note,
      clientOpId: id,
    );
  }

  Future<FinanceState?> load() => session.load();

  Future<void> rememberChoice(
    String sourceText,
    AgentDraft draft, {
    FinanceState? initialState,
  }) async {
    final key = QuickEntryRules.quickMemoryKey(sourceText);
    if (key.isEmpty || draft.categoryId == null || draft.accountId == null) {
      return;
    }
    final memory = QuickMemory(
      key: key,
      categoryId: draft.categoryId,
      accountId: draft.accountId,
      updatedAt: DateTime.now().toIso8601String(),
    );
    final next = await session.write(
      (current) => current.copyWith(
        quickMemories: [
          ...current.quickMemories.where((item) => item.key != key),
          memory,
        ],
      ),
      initialState: initialState,
    );
    try {
      await onQuickMemoriesChanged?.call(next.quickMemories);
    } on ApiFailure {
      // The confirmed transaction remains safe locally and will sync later.
    }
  }
}
