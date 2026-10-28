import 'package:flutter/foundation.dart' show ChangeNotifier;

import '../../../domain/finance_rules.dart';
import '../../../domain/models.dart';
import '../data/quick_entry_repository.dart';
import '../domain/quick_entry_batch.dart';
import '../domain/quick_entry_context.dart';
import '../domain/quick_entry_rules.dart';
import '../domain/quick_entry_wire.dart';

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
  QuickEntryBatch? _batch;
  String? _sourceText;
  String? _message;
  bool _confirming = false;
  bool _parsing = false;
  String? _lastConfirmedFingerprint;
  String? _lastConfirmedBatchFingerprint;
  int _parseGeneration = 0;
  bool _cloudEnabled = true;
  bool _cloudPreferenceLoaded = false;

  /// The local partition a batch belongs to. A rebind or user switch replaces
  /// this object, so identity comparison invalidates the session.
  Object? _sessionLocal;

  void Function(FinanceState state)? onStateChanged;

  /// Called after a batch is persisted so the app can schedule one sync.
  void Function(String reason)? onLocalMutation;

  FinanceState get state => _state;
  AgentDraft? get draft => _draft;
  QuickEntryBatch? get batch => _batch;
  List<QuickEntryCandidate> get candidates =>
      _batch?.candidates ?? const <QuickEntryCandidate>[];
  List<QuickEntryCandidate> get selectedCandidates =>
      candidates.where((item) => item.selected).toList(growable: false);
  String? get sourceText => _sourceText;
  String? get message => _message;
  bool get isParsing => _parsing;
  bool get isConfirming => _confirming;
  bool get cloudParsingEnabled => _cloudEnabled;
  bool get batchSupported => repository.supportsAtomicBatch;
  int get parseGeneration => _parseGeneration;

  bool get canConfirmBatch {
    if (_confirming || _parsing) return false;
    final selected = selectedCandidates;
    return selected.isNotEmpty &&
        selected.every((item) => QuickEntryRules.isComplete(item.draft));
  }

  /// Index of the first selected card that still needs a field, if any.
  int? get firstIncompleteSelectedIndex {
    for (var index = 0; index < candidates.length; index += 1) {
      final candidate = candidates[index];
      if (!candidate.selected) continue;
      if (!QuickEntryRules.isComplete(candidate.draft)) return index;
    }
    return null;
  }

  void adoptState(FinanceState state, {bool notify = false}) {
    _state = state;
    if (_batch != null &&
        !identical(_sessionLocal, repository.session.local)) {
      _invalidateSession('登录身份已切换，候选卡已作废');
    }
    if (notify) {
      onStateChanged?.call(state);
      notifyListeners();
    }
  }

  Future<void> loadCloudPreference() async {
    if (_cloudPreferenceLoaded) return;
    try {
      _cloudEnabled = await repository.cloudParsingEnabled();
    } on Object {
      _cloudEnabled = true;
    }
    _cloudPreferenceLoaded = true;
    notifyListeners();
  }

  Future<void> setCloudParsingEnabled(bool enabled) async {
    if (_cloudEnabled == enabled) return;
    _cloudEnabled = enabled;
    _cloudPreferenceLoaded = true;
    _parseGeneration += 1;
    _parsing = false;
    _batch = null;
    _draft = null;
    _sourceText = null;
    _message = enabled ? '已切换为云端解析' : '已切换为本地解析';
    notifyListeners();
    try {
      await repository.setCloudParsingEnabled(enabled);
    } on Object {
      // The choice still applies to this session; persistence can retry next time.
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

  /// 随口记: one utterance becomes a reviewed batch of candidate cards.
  Future<bool> createBatch(String text, {DateTime? now}) async {
    final input = text.trim();
    if (input.isEmpty) {
      _message = '请先说说发生了什么';
      notifyListeners();
      return false;
    }
    final generation = _parseGeneration + 1;
    _parseGeneration = generation;
    _sessionLocal = repository.session.local;
    _sourceText = input;
    _draft = null;
    _batch = null;
    _message = null;
    _parsing = true;
    _lastConfirmedBatchFingerprint = null;
    notifyListeners();
    if (!_cloudPreferenceLoaded) await loadCloudPreference();
    if (generation != _parseGeneration) return false;
    if (!batchSupported) {
      _parsing = false;
      _message = '当前本地存储不支持事务批量确认';
      notifyListeners();
      return false;
    }
    try {
      final batch = await repository.createBatch(input, _state,
          now: now, allowCloud: _cloudEnabled);
      if (generation != _parseGeneration) return false;
      if (!identical(_sessionLocal, repository.session.local)) return false;
      if (batch.isCloud && !_cloudEnabled) return false;
      _adoptBatch(batch);
      return true;
    } on Object {
      if (generation == _parseGeneration) _message = '解析失败，请稍后重试';
      return false;
    } finally {
      if (generation == _parseGeneration) {
        _parsing = false;
        notifyListeners();
      }
    }
  }

  void _adoptBatch(QuickEntryBatch batch) {
    _batch = batch.copyWith(candidates: [
      for (final candidate in batch.candidates)
        candidate.copyWith(
            selected: candidate.isInferred ? false : candidate.selected),
    ]);
    final degradation = repository.lastBatchDegradation;
    _message = batch.mode == QuickEntryParseMode.local && degradation != null
        ? degradation
        : null;
    notifyListeners();
  }

  void toggleCandidate(String id, bool selected) {
    final batch = _batch;
    if (batch == null) return;
    var staleBlocked = false;
    final updated = <QuickEntryCandidate>[];
    for (final candidate in batch.candidates) {
      if (candidate.id != id) {
        updated.add(candidate);
        continue;
      }
      if (selected && candidate.stale) staleBlocked = true;
      updated.add(
          candidate.copyWith(selected: selected && !candidate.stale));
    }
    _batch = batch.copyWith(candidates: updated);
    _message = staleBlocked ? '这张推算卡已失效，请重新解析' : null;
    notifyListeners();
  }

  void selectAllExplicit() {
    final batch = _batch;
    if (batch == null) return;
    _batch = batch.copyWith(candidates: [
      for (final candidate in batch.candidates)
        if (candidate.isInferred || candidate.stale)
          candidate
        else
          candidate.copyWith(selected: true),
    ]);
    _message = null;
    notifyListeners();
  }

  void removeCandidate(String id) {
    final batch = _batch;
    if (batch == null) return;
    _batch = batch.copyWith(candidates: [
      for (final candidate in batch.candidates)
        if (candidate.id != id) candidate,
    ]);
    _message = null;
    notifyListeners();
  }

  void updateCandidate(String id, AgentDraft draft) {
    final batch = _batch;
    if (batch == null) return;
    final updated = <QuickEntryCandidate>[];
    for (final candidate in batch.candidates) {
      if (candidate.id != id) {
        updated.add(candidate);
        continue;
      }
      final normalized =
          QuickEntryRules.applyUserEdit(candidate.draft, draft);
      updated.add(candidate.copyWith(
        draft: normalized,
        userEdited:
            candidate.userEdited || _differs(candidate.draft, normalized),
      ));
    }
    _batch = batch.copyWith(candidates: updated);
    _message = null;
    notifyListeners();
  }

  /// "手输今日总额" entry offered when the reference cannot be folded in.
  void addManualCandidate(double amount, {String? note}) {
    if (amount <= 0) return;
    final now = DateTime.now();
    final batch = _batch ??
        QuickEntryBatch(
          id: 'manual-${now.microsecondsSinceEpoch}',
          sourceText: _sourceText ?? '',
          mode: QuickEntryParseMode.local,
          targetDate: dateKey(now),
          referenceDate: dateKey(now.subtract(const Duration(days: 1))),
        );
    final preferred = _state.preferredCurrency.trim().toUpperCase();
    final draft = QuickEntryRules.withCompleteness(AgentDraft(
      amount: amount,
      type: TransactionType.expense,
      categoryId: null,
      accountId: null,
      date: batch.targetDate ?? dateKey(now),
      note: note ?? '今日总额（手输）',
      confidence: .5,
      currency: RegExp(r'^[A-Z]{3}$').hasMatch(preferred) ? preferred : 'CNY',
    ));
    _batch = batch.copyWith(candidates: [
      ...batch.candidates,
      QuickEntryCandidate(
        id: 'manual-${now.microsecondsSinceEpoch}',
        draft: draft,
        selected: true,
        userEdited: true,
      ),
    ]);
    _message = null;
    notifyListeners();
  }

  Future<bool> confirmBatch({DateTime? now}) async {
    final batch = _batch;
    if (batch == null || _confirming) return false;
    if (!identical(_sessionLocal, repository.session.local)) {
      _invalidateSession('登录身份已切换，候选卡已作废');
      return false;
    }
    final clock = now ?? DateTime.now();
    _refreshStaleCandidates(clock);
    final selected = selectedCandidates;
    if (selected.isEmpty) {
      _message = '请先勾选要入账的卡片';
      notifyListeners();
      return false;
    }
    for (var index = 0; index < candidates.length; index += 1) {
      final candidate = candidates[index];
      if (!candidate.selected) continue;
      final reason = QuickEntryRules.incompleteReason(candidate.draft);
      if (reason != null) {
        _message = '第${index + 1}张卡$reason';
        notifyListeners();
        return false;
      }
    }
    final fingerprint = _batchFingerprint(batch, selected);
    if (_lastConfirmedBatchFingerprint == fingerprint) return false;
    _confirming = true;
    _message = null;
    notifyListeners();
    try {
      final next = await repository.commitBatch(
        selected,
        initialState: _state,
        now: clock,
      );
      _lastConfirmedBatchFingerprint = fingerprint;
      _state = next;
      onStateChanged?.call(next);
      _batch = null;
      _sourceText = null;
      _message = '已保存 ${selected.length} 笔到本地';
      onLocalMutation?.call('quick_entry.batch.confirm');
      await postConfirm?.call();
      return true;
    } on QuickEntryCommitException catch (error) {
      _message = error.message;
      return false;
    } on QuickEntryStorageUnsupported {
      _message = '当前本地存储不支持事务批量确认';
      return false;
    } finally {
      _confirming = false;
      notifyListeners();
    }
  }

  void _refreshStaleCandidates(DateTime now) {
    final batch = _batch;
    if (batch == null) return;
    final fingerprint = batch.contextFingerprint;
    if (fingerprint == null) return;
    final current = QuickEntryContextBuilder.build(
      state: _state,
      now: now,
    ).fingerprint;
    if (current == fingerprint) return;
    _batch = batch.copyWith(candidates: [
      for (final candidate in batch.candidates)
        if (candidate.isInferred)
          candidate.copyWith(stale: true, selected: false)
        else
          candidate,
    ]);
    _message = '账本已变化，推算卡已失效，请重新解析';
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
    if (!FinanceRules.canPostDraft(draft)) {
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
    _parseGeneration += 1;
    _draft = null;
    _sourceText = null;
    _message = null;
    _batch = null;
    _parsing = false;
    notifyListeners();
  }

  void _invalidateSession(String message) {
    _parseGeneration += 1;
    _batch = null;
    _draft = null;
    _sourceText = null;
    _parsing = false;
    _message = message;
    notifyListeners();
  }

  static bool _differs(AgentDraft before, AgentDraft after) =>
      before.amount != after.amount ||
      before.categoryId != after.categoryId ||
      before.accountId != after.accountId ||
      before.type != after.type ||
      before.date != after.date ||
      before.note != after.note ||
      before.currency != after.currency;

  String _batchFingerprint(
      QuickEntryBatch batch, List<QuickEntryCandidate> selected) {
    final parts = <String>[batch.id];
    for (final candidate in selected) {
      final draft = candidate.draft;
      parts.add([
        candidate.id,
        draft.amount,
        draft.type.name,
        draft.categoryId,
        draft.accountId,
        draft.date,
        draft.note,
        draft.currency,
      ].join('|'));
    }
    return parts.join('||');
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
