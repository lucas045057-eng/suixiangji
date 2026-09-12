import 'package:flutter/foundation.dart' show ChangeNotifier;

import '../../../domain/models.dart';
import '../data/quick_entry_repository.dart';
import '../domain/quick_entry_rules.dart';

class QuickEntryStore extends ChangeNotifier {
  QuickEntryStore({
    required this.repository,
    FinanceState? initialState,
    this.postConfirm,
  }) : _state = initialState ?? const FinanceState();

  final QuickEntryRepository repository;
  final Future<void> Function()? postConfirm;
  FinanceState _state;
  AgentDraft? _draft;
  String? _sourceText;
  String? _message;
  bool _confirming = false;
  String? _lastConfirmedFingerprint;

  void Function(FinanceState state)? onStateChanged;

  FinanceState get state => _state;
  AgentDraft? get draft => _draft;
  String? get sourceText => _sourceText;
  String? get message => _message;

  void adoptState(FinanceState state, {bool notify = false}) {
    _state = state;
    if (notify) {
      onStateChanged?.call(state);
      notifyListeners();
    }
  }

  Future<void> createDraft(String text, {DateTime? now}) async {
    final next = await repository.createDraft(text, _state, now: now);
    _draft = next;
    _sourceText = text;
    _lastConfirmedFingerprint = null;
    _message = repository.remoteFallbackUsed
        ? '同步服务暂不可用，已使用本地规则草稿'
        : repository.api == null
            ? null
            : '已从同步服务生成待确认草稿';
    notifyListeners();
  }

  void updateDraft(AgentDraft draft) {
    _draft = QuickEntryRules.validateEditedDraft(draft);
    _message = null;
    notifyListeners();
  }

  Future<void> rememberDraftChoice(String sourceText, AgentDraft draft) async {
    await repository.rememberChoice(sourceText, draft, initialState: _state);
    final saved = await repository.load();
    if (saved != null) {
      _state = saved;
      onStateChanged?.call(saved);
    }
  }

  Future<bool> confirmDraft(
    AgentDraft draft,
    String? sourceText,
    Future<void> Function(FinanceTransaction) postTransaction,
  ) async {
    if (_confirming || _lastConfirmedFingerprint == _fingerprint(draft)) {
      return false;
    }
    if (!QuickEntryRules.canPost(draft)) {
      _message = draft.missingFacts.isEmpty
          ? '这笔记录仍需确认关键字段'
          : draft.missingFacts.join('、');
      notifyListeners();
      return false;
    }
    _confirming = true;
    try {
      final fingerprint = _fingerprint(draft);
      await postTransaction(repository.transactionFromDraft(draft));
      _lastConfirmedFingerprint = fingerprint;
      clearDraft();
      if (sourceText != null) await rememberDraftChoice(sourceText, draft);
      await postConfirm?.call();
      return true;
    } finally {
      _confirming = false;
    }
  }

  void clearDraft() {
    _draft = null;
    _sourceText = null;
    _message = null;
    notifyListeners();
  }

  String _fingerprint(AgentDraft draft) => [
        draft.amount,
        draft.type.name,
        draft.categoryId,
        draft.accountId,
        draft.date,
        draft.note,
        draft.currency,
        draft.fromAccountId,
        draft.toAccountId,
      ].join('|');
}
