import '../../../domain/models.dart';

/// Session-level multi-card session for 随口记. Nothing here is persisted:
/// unconfirmed candidates are dropped when the session ends.
enum QuickEntryParseMode { cloud, local }

enum QuickEntryBatchStatus { ok, needsSplit, noActionableItems }

class QuickEntryNotice {
  const QuickEntryNotice({required this.code, required this.message});

  final String code;
  final String message;
}

class QuickEntryCandidate {
  const QuickEntryCandidate({
    required this.id,
    required this.draft,
    this.selected = false,
    this.userEdited = false,
    this.stale = false,
  });

  /// Stable within one batch only. Never used as a transaction id.
  final String id;
  final AgentDraft draft;
  final bool selected;
  final bool userEdited;

  /// Set when the ledger aggregate changed after the inference was produced.
  final bool stale;

  bool get isInferred => draft.isInferred;

  QuickEntryCandidate copyWith({
    String? id,
    AgentDraft? draft,
    bool? selected,
    bool? userEdited,
    bool? stale,
  }) =>
      QuickEntryCandidate(
        id: id ?? this.id,
        draft: draft ?? this.draft,
        selected: selected ?? this.selected,
        userEdited: userEdited ?? this.userEdited,
        stale: stale ?? this.stale,
      );
}

class QuickEntryBatch {
  const QuickEntryBatch({
    required this.id,
    required this.sourceText,
    required this.mode,
    this.status = QuickEntryBatchStatus.ok,
    this.notices = const <QuickEntryNotice>[],
    this.contextFingerprint,
    this.targetDate,
    this.referenceDate,
    this.candidates = const <QuickEntryCandidate>[],
  });

  final String id;
  final String sourceText;
  final QuickEntryParseMode mode;
  final QuickEntryBatchStatus status;
  final List<QuickEntryNotice> notices;

  /// Present only for cloud batches; used to detect a stale inference.
  final String? contextFingerprint;
  final String? targetDate;
  final String? referenceDate;
  final List<QuickEntryCandidate> candidates;

  bool get isCloud => mode == QuickEntryParseMode.cloud;

  QuickEntryBatch copyWith({
    String? id,
    String? sourceText,
    QuickEntryParseMode? mode,
    QuickEntryBatchStatus? status,
    List<QuickEntryNotice>? notices,
    String? contextFingerprint,
    String? targetDate,
    String? referenceDate,
    List<QuickEntryCandidate>? candidates,
  }) =>
      QuickEntryBatch(
        id: id ?? this.id,
        sourceText: sourceText ?? this.sourceText,
        mode: mode ?? this.mode,
        status: status ?? this.status,
        notices: notices ?? this.notices,
        contextFingerprint: contextFingerprint ?? this.contextFingerprint,
        targetDate: targetDate ?? this.targetDate,
        referenceDate: referenceDate ?? this.referenceDate,
        candidates: candidates ?? this.candidates,
      );
}

/// The cloud response failed the client whitelist. The whole response is
/// discarded; the caller degrades to local explicit cards.
class QuickEntryResponseInvalid implements Exception {
  const QuickEntryResponseInvalid(this.reason);

  final String reason;

  @override
  String toString() => 'QuickEntryResponseInvalid($reason)';
}

/// A confirmation-time validation failure. Carries the offending card so the
/// UI can point the user at it instead of silently skipping.
class QuickEntryCommitException implements Exception {
  const QuickEntryCommitException(this.message, {this.candidateId});

  final String message;
  final String? candidateId;

  @override
  String toString() => message;
}

/// The local store cannot commit a batch as one transaction, so the batch
/// feature stays off on that platform (design §8.1.5).
class QuickEntryStorageUnsupported implements Exception {
  const QuickEntryStorageUnsupported();

  @override
  String toString() => '当前本地存储不支持事务批量确认';
}
