import 'dart:math';

import '../../../core/database/local_state_session.dart';
import '../../../core/network/api_session.dart';
import '../../../core/network/api_transport.dart';
import '../../../data/sync_queue.dart';
import '../../../domain/finance_rules.dart';
import '../../../domain/models.dart';
import '../../ledger/domain/ledger_rules.dart';
import '../domain/quick_entry_batch.dart';
import '../domain/quick_entry_context.dart';
import '../domain/quick_entry_response_validator.dart';
import '../domain/quick_entry_rules.dart';
import '../domain/quick_entry_stream.dart';
import 'quick_entry_remote_data_source.dart';

typedef QuickMemoriesUpdater = Future<void> Function(
    List<QuickMemory> memories);

class QuickEntryRepository {
  QuickEntryRepository({
    required this.session,
    this.remote,
    this.onQuickMemoriesChanged,
  });

  static const cloudParsingEnabledKey =
      'suixiangji-quick-entry-cloud-enabled-v1';

  final LocalStateSession session;
  final QuickEntryRemoteDataSource? remote;
  final QuickMemoriesUpdater? onQuickMemoriesChanged;
  bool remoteFallbackUsed = false;

  /// Why the last cloud batch parse degraded to local rules, if it did.
  String? lastBatchDegradation;

  ApiSession? get api => remote?.api;

  /// Streaming is available only with a real session-backed data source.
  bool get canStream => remote?.supportsStreaming ?? false;

  /// Batch confirmation needs one atomic state+queue commit.
  bool get supportsAtomicBatch => session.supportsAtomicWrites;

  Future<bool> cloudParsingEnabled() async {
    final raw = await session.local.readMetadata(cloudParsingEnabledKey);
    return raw == null || raw.trim().toLowerCase() != 'false';
  }

  Future<void> setCloudParsingEnabled(bool enabled) => session.local
      .writeMetadata(cloudParsingEnabledKey, enabled ? 'true' : 'false');

  Future<AgentDraft> createDraft(
    String text,
    FinanceState context, {
    DateTime? now,
  }) async {
    remoteFallbackUsed = false;
    final localDraft = FinanceRules.completeNaturalLanguageDraft(
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

  /// Parses one utterance into a candidate batch. Cloud failures degrade to a
  /// single local explicit card; the client never builds its own inference.
  Future<QuickEntryBatch> createBatch(
    String text,
    FinanceState state, {
    DateTime? now,
    bool allowCloud = true,
  }) async {
    final clock = now ?? DateTime.now();
    lastBatchDegradation = null;
    final trimmed = text.trim();
    final source = remote;
    if (!allowCloud) {
      lastBatchDegradation = '云端 AI 解析已关闭，只使用本地规则';
      return _localBatch(trimmed, state, clock, lastBatchDegradation);
    }
    if (source == null) {
      lastBatchDegradation = '未配置云端解析，已使用本地规则';
      return _localBatch(trimmed, state, clock, lastBatchDegradation);
    }
    final context = QuickEntryContextBuilder.build(state: state, now: clock);
    final requestId = _requestId(clock);
    final request = QuickEntryDraftRequest(
      requestId: requestId,
      text: trimmed,
      localToday: context.targetDate,
      utcOffsetMinutes: clock.timeZoneOffset.inMinutes,
      preferredCurrency: _currencyOf(state),
      context: context,
    );
    try {
      final json = await source.createDrafts(request.toJson());
      return _buildBatch(
        json,
        requestId: requestId,
        sourceText: trimmed,
        context: context,
        state: state,
        clock: clock,
      );
    } on ApiFailure catch (failure) {
      lastBatchDegradation = _degradationFor(failure);
      return _localBatch(trimmed, state, clock, lastBatchDegradation);
    } on QuickEntryResponseInvalid {
      lastBatchDegradation = 'AI 返回内容未通过校验，已改用本地解析';
      return _localBatch(trimmed, state, clock, lastBatchDegradation);
    }
  }

  /// Streaming generation (design v2 §4/§5). Emits read-only preview updates
  /// while the model works, then exactly one final batch — the same batch the
  /// non-streaming endpoint would produce. Previews never enter `_batch`.
  ///
  /// The caller owns cancellation: complete [abortTrigger] to stop this
  /// generation. The shared HTTP client is never closed here.
  Stream<QuickEntryStreamMessage> streamBatch(
    String text,
    FinanceState state, {
    DateTime? now,
    bool allowCloud = true,
    required Future<void> abortTrigger,
  }) async* {
    final clock = now ?? DateTime.now();
    lastBatchDegradation = null;
    final trimmed = text.trim();
    final source = remote;
    if (!allowCloud) {
      lastBatchDegradation = '云端 AI 解析已关闭，只使用本地规则';
      yield QuickEntryStreamBatchMessage(
          _localBatch(trimmed, state, clock, lastBatchDegradation));
      return;
    }
    if (source == null || !source.supportsStreaming) {
      lastBatchDegradation = '未配置云端解析，已使用本地规则';
      yield QuickEntryStreamBatchMessage(
          _localBatch(trimmed, state, clock, lastBatchDegradation));
      return;
    }
    final context = QuickEntryContextBuilder.build(state: state, now: clock);
    final requestId = _requestId(clock);
    final request = QuickEntryDraftRequest(
      requestId: requestId,
      text: trimmed,
      localToday: context.targetDate,
      utcOffsetMinutes: clock.timeZoneOffset.inMinutes,
      preferredCurrency: _currencyOf(state),
      context: context,
    );
    yield const QuickEntryStreamPhaseMessage(QuickEntryStreamPhase.submitting);
    var preview = QuickEntryPreviewSession(
      requestId: requestId,
      sourceText: trimmed,
    );
    try {
      final events = source.createDraftsStream(
        request.toJson(),
        requestId: requestId,
        abortTrigger: abortTrigger,
      );
      await for (final event in events) {
        switch (event.type) {
          case 'session.started':
          case 'generation.started':
            yield const QuickEntryStreamPhaseMessage(
                QuickEntryStreamPhase.streaming);
          case 'provider.connected':
            break;
          case 'item.preview':
            final item = QuickEntryPreviewItem.parse(
              event.data,
              attempt: event.attempt,
              sourceText: trimmed,
            );
            if (preview.items.any((row) => row.previewId == item.previewId)) {
              throw const QuickEntryStreamProtocolError('preview.duplicate');
            }
            preview = preview.copyWith(
              attempt: event.attempt,
              items: [...preview.items, item],
            );
            yield QuickEntryStreamPreviewMessage(preview);
          case 'reference.preview':
            preview = preview.copyWith(
              attempt: event.attempt,
              reference: QuickEntryPreviewReference.parse(event.data,
                  sourceText: trimmed),
            );
            yield QuickEntryStreamPreviewMessage(preview);
          case 'attempt.restarted':
            // The retry starts from scratch: every earlier preview is void.
            preview = QuickEntryPreviewSession(
              requestId: requestId,
              sourceText: trimmed,
              attempt: event.attempt,
            );
            yield const QuickEntryStreamPhaseMessage(
                QuickEntryStreamPhase.retrying);
            yield QuickEntryStreamPreviewMessage(preview);
          case 'provider.completed':
          case 'plan.validated':
            yield const QuickEntryStreamPhaseMessage(
                QuickEntryStreamPhase.finalizing);
          case 'completed':
            final result = event.data['result'];
            if (result is! Map) {
              throw const QuickEntryStreamProtocolError('completed.result');
            }
            yield QuickEntryStreamBatchMessage(_buildBatch(
              result.cast<String, Object?>(),
              requestId: requestId,
              sourceText: trimmed,
              context: context,
              state: state,
              clock: clock,
            ));
            return;
          case 'error':
            final code = event.data['code'];
            throw QuickEntryStreamFailure(
                code is String ? code : 'stream_interrupted');
        }
      }
      // EOF without a legal terminal event.
      throw const QuickEntryStreamFailure('stream_interrupted');
    } on QuickEntryStreamCancelled {
      rethrow;
    } on ApiFailure catch (failure) {
      // A missing endpoint means an old server: one legacy call is allowed.
      final batch = failure.statusCode == 404
          ? await createBatch(trimmed, state, now: clock)
          : null;
      if (batch != null) {
        yield QuickEntryStreamBatchMessage(batch);
        return;
      }
      lastBatchDegradation = _degradationFor(failure);
      yield QuickEntryStreamBatchMessage(
          _localBatch(trimmed, state, clock, lastBatchDegradation));
    } on QuickEntryStreamFailure catch (failure) {
      if (failure.allowsLegacyFallback) {
        yield QuickEntryStreamBatchMessage(
            await createBatch(trimmed, state, now: clock));
        return;
      }
      lastBatchDegradation = '${failure.message}（本次已改用本地解析）';
      yield QuickEntryStreamBatchMessage(
          _localBatch(trimmed, state, clock, lastBatchDegradation));
    } on QuickEntryStreamProtocolError {
      lastBatchDegradation = '生成数据无效，本次已改用本地解析';
      yield QuickEntryStreamBatchMessage(
          _localBatch(trimmed, state, clock, lastBatchDegradation));
    }
  }

  QuickEntryBatch _buildBatch(
    Map<String, Object?> json, {
    required String requestId,
    required String sourceText,
    required QuickEntryLedgerContext context,
    required FinanceState state,
    required DateTime clock,
  }) {
    final validated = QuickEntryResponseValidator.validate(
      json,
      requestId: requestId,
      sourceText: sourceText,
      contextFingerprint: context.fingerprint,
      targetDate: context.targetDate,
      referenceDate: context.referenceDate,
    );
    final candidates = <QuickEntryCandidate>[];
    for (final item in validated.drafts) {
      final draft = QuickEntryRules.completeCloudDraft(
        item.draft,
        state,
        now: clock,
        sourceText: sourceText,
      );
      candidates.add(QuickEntryCandidate(
        id: item.id,
        draft: draft,
        selected: !draft.isInferred && item.selectedByDefault,
      ));
    }
    return QuickEntryBatch(
      id: requestId,
      sourceText: sourceText,
      mode: QuickEntryParseMode.cloud,
      status: validated.status,
      notices: validated.notices,
      contextFingerprint: context.fingerprint,
      targetDate: context.targetDate,
      referenceDate: context.referenceDate,
      candidates: candidates,
    );
  }


  /// Commits every selected card in one `LocalStateSession.write`: transactions,
  /// their sync operations and the learned QuickMemory all land together.
  Future<FinanceState> commitBatch(
    List<QuickEntryCandidate> candidates, {
    FinanceState? initialState,
    DateTime? now,
  }) async {
    if (candidates.isEmpty) {
      throw const QuickEntryCommitException('没有勾选任何卡片');
    }
    if (!supportsAtomicBatch) throw const QuickEntryStorageUnsupported();
    final clock = now ?? DateTime.now();
    final transactions = <FinanceTransaction>[];
    for (var index = 0; index < candidates.length; index += 1) {
      final draft = candidates[index].draft;
      final reason = QuickEntryRules.incompleteReason(draft);
      if (reason != null) {
        throw QuickEntryCommitException(
          '第${index + 1}张卡$reason',
          candidateId: candidates[index].id,
        );
      }
      final id = _transactionId(clock, index);
      transactions.add(FinanceTransaction(
        id: id,
        date: draft.date,
        occurredAt: LedgerRules.occurredAtFor(draft.date, clock),
        type: draft.type,
        amount: draft.amount,
        currency: draft.currency,
        categoryId: draft.categoryId,
        accountId: draft.accountId,
        note: draft.note,
        clientOpId: id,
      ));
    }
    final learned = QuickEntryRules.learnedMemories(
      confirmed: candidates,
      now: clock,
    );
    final next = await session.write(
      (current) {
        var state = current;
        final converted = <FinanceTransaction>[];
        for (var index = 0; index < candidates.length; index += 1) {
          _validateAgainstState(candidates[index], state);
          converted.add(LedgerRules.prepareConversion(state, transactions[index]));
        }
        for (final transaction in converted) {
          state = LedgerRules.upsertTransaction(state, transaction);
        }
        if (learned.isNotEmpty) {
          state = state.copyWith(
              quickMemories:
                  QuickEntryRules.mergeMemories(state.quickMemories, learned));
        }
        return state;
      },
      deriveOperations: (current, next) => [
        for (final transaction in transactions)
          SyncOperation(
            clientOpId: transaction.clientOpId,
            entity: 'transactions',
            entityId: transaction.id,
            type: SyncOperationType.upsert,
            payload: next.transactions
                .firstWhere((row) => row.id == transaction.id)
                .toJson(),
            createdAt: clock.toIso8601String(),
          ),
      ],
      initialState: initialState,
    );
    try {
      await onQuickMemoriesChanged?.call(next.quickMemories);
    } on ApiFailure {
      // The confirmed transactions remain safe locally and will sync later.
    }
    return next;
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
    final key = FinanceRules.quickMemoryKey(sourceText);
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

  void _validateAgainstState(QuickEntryCandidate candidate, FinanceState state) {
    final draft = candidate.draft;
    final categoryId = draft.categoryId;
    if (categoryId != null) {
      final matches =
          state.categories.where((item) => item.id == categoryId).toList();
      if (matches.isEmpty) {
        throw QuickEntryCommitException('分类已不存在，请重新选择',
            candidateId: candidate.id);
      }
      if (matches.first.type != draft.type) {
        throw QuickEntryCommitException('分类与收支类型不一致',
            candidateId: candidate.id);
      }
    }
    final accountId = draft.accountId;
    if (accountId != null) {
      final matches =
          state.accounts.where((item) => item.id == accountId).toList();
      if (matches.isEmpty || !matches.first.isActive) {
        throw QuickEntryCommitException('支付账户不可用，请重新选择',
            candidateId: candidate.id);
      }
    }
  }

  QuickEntryBatch _localBatch(
    String text,
    FinanceState state,
    DateTime clock,
    String? reason,
  ) =>
      QuickEntryRules.localBatch(
        text,
        state,
        now: clock,
        batchId: 'local-${clock.microsecondsSinceEpoch}',
        reason: reason,
      );

  static String _requestId(DateTime clock) =>
      'sxj-${clock.microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 32).toRadixString(16)}';

  static String _transactionId(DateTime clock, int index) =>
      'tx-${clock.microsecondsSinceEpoch + index}-${Random.secure().nextInt(1 << 32).toRadixString(16)}';

  static String _currencyOf(FinanceState state) {
    final preferred = state.preferredCurrency.trim().toUpperCase();
    return RegExp(r'^[A-Z]{3}$').hasMatch(preferred) ? preferred : 'CNY';
  }

  /// §5.4: the error contract's machine code decides what the user is told.
  /// Every branch still degrades to a local explicit card and never retries.
  static String _degradationFor(ApiFailure failure) {
    const local = '本次已改用本地解析';
    const tooLarge = '文本过长，请缩短后重试';
    const rateLimited = '请求过于频繁，请稍后再试';
    switch (failure.code) {
      case 'text_too_large':
        return '$tooLarge（$local）';
      case 'rate_limited':
        return '${_rateLimitedText(rateLimited, failure.retryAfter)}（$local）';
      case 'invalid_context':
        return '解析上下文有误，修正后请主动重试（$local）';
      case 'validation_error':
        return '提交内容未通过云端校验（$local）';
      case 'llm_bad_response':
        return '云端返回内容不可信（$local）';
      case 'llm_unavailable':
        return '云端解析暂时不可用（$local）';
      case 'llm_timeout':
        return '云端解析超时（$local）';
      case 'internal_error':
        return '云端解析出现未预期错误（$local）';
    }
    if (failure.statusCode == 413) return '$tooLarge（$local）';
    if (failure.statusCode == 429) {
      return '${_rateLimitedText(rateLimited, failure.retryAfter)}（$local）';
    }
    final fallback = switch (failure.kind) {
      ApiFailureKind.network => '暂时无法连接云端解析，已使用本地解析',
      ApiFailureKind.unauthorized => '登录状态已失效，已使用本地解析',
      ApiFailureKind.configuration => '未配置云端解析，已使用本地解析',
      ApiFailureKind.validation =>
        '云端暂不可用（${failure.message}），已使用本地解析',
      ApiFailureKind.conflict ||
      ApiFailureKind.server =>
        '云端解析暂时不可用，已使用本地解析',
      ApiFailureKind.cancelled => '云端解析已取消，已使用本地解析',
    };
    final detail = failure.detail;
    if (failure.code != null || detail == null) return fallback;
    return '$fallback（$detail）';
  }

  static String _rateLimitedText(String base, Duration? retryAfter) {
    final seconds = retryAfter?.inSeconds;
    if (seconds == null || seconds <= 0) return base;
    return '$base（约 $seconds 秒）';
  }
}
