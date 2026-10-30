import 'dart:convert';

import '../../../core/network/sse_parser.dart';
import 'quick_entry_batch.dart';
import 'quick_entry_wire.dart';

/// Read-only preview of one完整事项 from `POST /agent/drafts/stream`.
///
/// Never converted into a candidate card: only `completed.result` may do that.
class QuickEntryPreviewItem {
  const QuickEntryPreviewItem({
    required this.previewId,
    required this.ordinal,
    required this.type,
    required this.note,
    required this.quote,
    required this.quoteStart,
    required this.quoteEnd,
    required this.amountKind,
    required this.amount,
    required this.rangeLower,
    required this.rangeUpper,
    required this.isApproximate,
    required this.currency,
    required this.date,
    required this.categoryHint,
    required this.accountHint,
  });

  final String previewId;

  /// 0-based position within the current attempt; display uses ordinal + 1.
  final int ordinal;
  final String type;
  final String note;
  final String quote;
  final int quoteStart;
  final int quoteEnd;
  final String amountKind;
  final double? amount;
  final double? rangeLower;
  final double? rangeUpper;
  final bool isApproximate;
  final String currency;
  final String date;
  final String? categoryHint;
  final String? accountHint;

  bool get isIncome => type == 'income';

  /// A missing amount stays missing: previews never invent a number.
  bool get amountMissing => amount == null;

  static const Set<String> amountKinds = {'exact', 'bounded_range', 'missing'};
  static final RegExp _previewId = RegExp(r'^a([0-9]{1,3})-i([0-9]{1,2})$');
  static final RegExp _currency = RegExp(r'^[A-Z]{3}$');

  factory QuickEntryPreviewItem.parse(
    Object? raw, {
    required int attempt,
    required String sourceText,
  }) {
    final data = _map(raw, 'item.preview');
    final previewId = _string(data['preview_id'], 'preview_id', maxLength: 32);
    final match = _previewId.firstMatch(previewId);
    if (match == null) throw const QuickEntryStreamProtocolError('preview_id');
    if (int.parse(match.group(1)!) != attempt) {
      throw const QuickEntryStreamProtocolError('preview_id.attempt');
    }
    final ordinal = _int(data['ordinal'], 'ordinal');
    if (ordinal < 0 || ordinal > 7 || int.parse(match.group(2)!) != ordinal) {
      throw const QuickEntryStreamProtocolError('ordinal');
    }
    final type = _string(data['type'], 'type', maxLength: 16);
    if (type != 'expense' && type != 'income') {
      throw const QuickEntryStreamProtocolError('type');
    }
    final quote = _map(data['source_quote'], 'source_quote');
    final quoteText = _string(quote['quote'], 'quote', maxLength: 1000);
    final start = _int(quote['start'], 'start');
    final end = _int(quote['end'], 'end');
    if (start < 0 || end <= start) {
      throw const QuickEntryStreamProtocolError('source_quote.range');
    }
    if (codePointSlice(sourceText, start, end) != quoteText) {
      throw const QuickEntryStreamProtocolError('source_quote.slice');
    }
    final amountKind = _string(data['amount_kind'], 'amount_kind', maxLength: 16);
    if (!amountKinds.contains(amountKind)) {
      throw const QuickEntryStreamProtocolError('amount_kind');
    }
    final amount = parseMoneyText(data['amount']);
    if ((data['amount'] != null) && amount == null) {
      throw const QuickEntryStreamProtocolError('amount');
    }
    final range = data['amount_range'];
    double? rangeLower, rangeUpper;
    if (range != null) {
      final bounds = _map(range, 'amount_range');
      rangeLower = parseMoneyText(bounds['lower']);
      rangeUpper = parseMoneyText(bounds['upper']);
      if (rangeLower == null || rangeUpper == null) {
        throw const QuickEntryStreamProtocolError('amount_range');
      }
    }
    if (amountKind == 'missing') {
      if (amount != null || range != null) {
        throw const QuickEntryStreamProtocolError('amount_kind.missing');
      }
    } else if (amount == null) {
      throw const QuickEntryStreamProtocolError('amount_kind.amount');
    }
    if (data['is_approximate'] is! bool) {
      throw const QuickEntryStreamProtocolError('is_approximate');
    }
    final currency = _string(data['currency'], 'currency', maxLength: 3);
    if (!_currency.hasMatch(currency)) {
      throw const QuickEntryStreamProtocolError('currency');
    }
    if (!isIsoDate(data['date'])) {
      throw const QuickEntryStreamProtocolError('date');
    }
    return QuickEntryPreviewItem(
      previewId: previewId,
      ordinal: ordinal,
      type: type,
      note: _string(data['note'], 'note', maxLength: 256, allowEmpty: true),
      quote: quoteText,
      quoteStart: start,
      quoteEnd: end,
      amountKind: amountKind,
      amount: amount,
      rangeLower: rangeLower,
      rangeUpper: rangeUpper,
      isApproximate: data['is_approximate'] as bool,
      currency: currency,
      date: data['date'] as String,
      categoryHint: _hint(data['category_hint'], 'category_hint'),
      accountHint: _hint(data['account_hint'], 'account_hint'),
    );
  }
}

/// “检测到昨日参照，等待核算” — display only, never an amount.
class QuickEntryPreviewReference {
  const QuickEntryPreviewReference({
    required this.quote,
    required this.kind,
    required this.categoryHint,
  });

  final String quote;
  final String kind;
  final String? categoryHint;

  static const Set<String> kinds = {
    'previous_day_total_expense',
    'previous_day_category_expense',
  };

  factory QuickEntryPreviewReference.parse(
    Object? raw, {
    required String sourceText,
  }) {
    final data = _map(raw, 'reference.preview');
    final quote = _string(data['quote'], 'quote', maxLength: 1000);
    final start = _int(data['start'], 'start');
    final end = _int(data['end'], 'end');
    if (start < 0 || end <= start) {
      throw const QuickEntryStreamProtocolError('reference.range');
    }
    if (codePointSlice(sourceText, start, end) != quote) {
      throw const QuickEntryStreamProtocolError('reference.slice');
    }
    final kind = _string(data['kind'], 'kind', maxLength: 48);
    if (!kinds.contains(kind)) {
      throw const QuickEntryStreamProtocolError('reference.kind');
    }
    return QuickEntryPreviewReference(
      quote: quote,
      kind: kind,
      categoryHint: _hint(data['category_hint'], 'category_hint'),
    );
  }
}

/// In-memory preview of the current generation. Never persisted, never used to
/// build candidates; the formal batch stays null until `completed` validates.
class QuickEntryPreviewSession {
  const QuickEntryPreviewSession({
    required this.requestId,
    required this.sourceText,
    this.attempt = 1,
    this.items = const <QuickEntryPreviewItem>[],
    this.reference,
  });

  final String requestId;
  final String sourceText;
  final int attempt;
  final List<QuickEntryPreviewItem> items;
  final QuickEntryPreviewReference? reference;

  bool get isEmpty => items.isEmpty && reference == null;

  QuickEntryPreviewSession copyWith({
    int? attempt,
    List<QuickEntryPreviewItem>? items,
    QuickEntryPreviewReference? reference,
    bool clearReference = false,
  }) =>
      QuickEntryPreviewSession(
        requestId: requestId,
        sourceText: sourceText,
        attempt: attempt ?? this.attempt,
        items: items ?? this.items,
        reference: clearReference ? null : (reference ?? this.reference),
      );
}

enum QuickEntryStreamPhase {
  idle,
  submitting,
  streaming,
  retrying,
  finalizing,
  ready,
  cancelled,
  failed,
}

extension QuickEntryStreamPhaseX on QuickEntryStreamPhase {
  /// §7: these phases are read-only — editing, deleting, selecting and
  /// confirming are all disabled, including direct method calls.
  bool get isLocked =>
      this == QuickEntryStreamPhase.submitting ||
      this == QuickEntryStreamPhase.streaming ||
      this == QuickEntryStreamPhase.retrying ||
      this == QuickEntryStreamPhase.finalizing;

  String get label => switch (this) {
        QuickEntryStreamPhase.idle => '',
        QuickEntryStreamPhase.submitting => '正在提交',
        QuickEntryStreamPhase.streaming => '正在整理事项',
        QuickEntryStreamPhase.retrying => '正在重新整理',
        QuickEntryStreamPhase.finalizing => '正在核对',
        QuickEntryStreamPhase.ready => '整理完成',
        QuickEntryStreamPhase.cancelled => '已取消这次整理',
        QuickEntryStreamPhase.failed => '整理未完成',
      };
}

/// One validated envelope from the stream.
class QuickEntryStreamEvent {
  const QuickEntryStreamEvent({
    required this.seq,
    required this.attempt,
    required this.type,
    required this.data,
  });

  final int seq;
  final int attempt;
  final String type;
  final Map<String, Object?> data;

  bool get isTerminal => type == 'completed' || type == 'error';
}

/// Envelope/sequence gate from streaming design §5.2. Any violation is a
/// protocol failure for the current generation; nothing after it is applied.
class QuickEntryStreamEnvelopeGuard {
  QuickEntryStreamEnvelopeGuard({required this.requestId});

  static const int streamVersion = 1;
  static const Set<String> types = {
    'session.started',
    'provider.connected',
    'generation.started',
    'item.preview',
    'reference.preview',
    'provider.completed',
    'attempt.restarted',
    'plan.validated',
    'completed',
    'error',
  };

  final String requestId;
  int _seq = 0;
  int _attempt = 1;
  bool _terminal = false;

  int get attempt => _attempt;
  bool get sawTerminal => _terminal;

  /// Returns null when the event must be ignored (arrived after a terminal).
  QuickEntryStreamEvent? accept(SseFrame frame) {
    if (_terminal) return null;
    final data = _decode(frame);
    if (data['stream_version'] != streamVersion) {
      throw const QuickEntryStreamProtocolError('stream_version');
    }
    if (data['request_id'] != requestId) {
      throw const QuickEntryStreamProtocolError('request_id');
    }
    final type = data['type'];
    if (type is! String || !types.contains(type)) {
      throw const QuickEntryStreamProtocolError('type');
    }
    if (frame.event != type) {
      throw const QuickEntryStreamProtocolError('event');
    }
    final seq = data['seq'];
    if (seq is! int || seq != _seq + 1) {
      throw const QuickEntryStreamProtocolError('seq');
    }
    final attempt = data['attempt'];
    if (attempt is! int) {
      throw const QuickEntryStreamProtocolError('attempt');
    }
    if (attempt == _attempt + 1) {
      if (type != 'attempt.restarted') {
        throw const QuickEntryStreamProtocolError('attempt.jump');
      }
    } else if (attempt != _attempt) {
      throw const QuickEntryStreamProtocolError('attempt');
    }
    final payload = data['data'];
    if (payload is! Map) {
      throw const QuickEntryStreamProtocolError('data');
    }
    _seq = seq;
    _attempt = attempt;
    if (type == 'error' || type == 'completed') _terminal = true;
    return QuickEntryStreamEvent(
      seq: seq,
      attempt: attempt,
      type: type,
      data: payload.cast<String, Object?>(),
    );
  }

  Map<String, Object?> _decode(SseFrame frame) {
    final decoded = _tryJson(frame.data);
    if (decoded is! Map) {
      throw const QuickEntryStreamProtocolError('envelope');
    }
    return decoded.cast<String, Object?>();
  }
}

/// The stream broke the contract. The current generation fails as a whole;
/// nothing shown so far is kept.
class QuickEntryStreamProtocolError implements Exception {
  const QuickEntryStreamProtocolError(this.field);

  final String field;

  @override
  String toString() => 'QuickEntryStreamProtocolError($field)';
}

/// Terminal failure reported by the server (`error` event) or the transport.
class QuickEntryStreamFailure implements Exception {
  const QuickEntryStreamFailure(this.code);

  final String code;

  static const Map<String, String> messages = {
    'llm_bad_response': 'AI 没能整理出可用结果，请重试或手动记录',
    'llm_timeout': '云端解析超时，请重试或手动记录',
    'llm_unavailable': '云端解析暂时不可用，请稍后再试',
    'llm_rate_limited': 'AI 服务繁忙，请稍后再试',
    'context_changed': '登录或账本信息已变化，请重新整理',
    'stream_interrupted': '生成连接中断，请重试或手动记录',
    'stream_protocol_error': '生成数据无效，请重试或手动记录',
  };

  String get message =>
      messages[code] ?? '这次整理中断了，请重试或手动记录';

  /// Old server without the stream endpoint: one fallback is allowed.
  bool get allowsLegacyFallback => code == 'stream_unavailable';

  @override
  String toString() => 'QuickEntryStreamFailure($code)';
}

/// The user cancelled, or a newer generation replaced this one.
class QuickEntryStreamCancelled implements Exception {
  const QuickEntryStreamCancelled();

  @override
  String toString() => 'QuickEntryStreamCancelled';
}

/// Updates emitted while one streaming generation runs.
sealed class QuickEntryStreamMessage {
  const QuickEntryStreamMessage();
}

class QuickEntryStreamPhaseMessage extends QuickEntryStreamMessage {
  const QuickEntryStreamPhaseMessage(this.phase);

  final QuickEntryStreamPhase phase;
}

class QuickEntryStreamPreviewMessage extends QuickEntryStreamMessage {
  const QuickEntryStreamPreviewMessage(this.preview);

  final QuickEntryPreviewSession preview;
}

class QuickEntryStreamBatchMessage extends QuickEntryStreamMessage {
  const QuickEntryStreamBatchMessage(this.batch);

  final QuickEntryBatch batch;
}

Object? _tryJson(String text) {
  try {
    return jsonDecode(text);
  } on FormatException {
    return null;
  }
}

Map<String, Object?> _map(Object? value, String field) {
  if (value is! Map) throw QuickEntryStreamProtocolError(field);
  return value.cast<String, Object?>();
}

String _string(Object? value, String field,
    {required int maxLength, bool allowEmpty = false}) {
  if (value is! String) throw QuickEntryStreamProtocolError(field);
  if (value.length > maxLength) throw QuickEntryStreamProtocolError(field);
  if (!allowEmpty && value.isEmpty) throw QuickEntryStreamProtocolError(field);
  return value;
}

int _int(Object? value, String field) {
  if (value is! int) throw QuickEntryStreamProtocolError(field);
  return value;
}

String? _hint(Object? value, String field) {
  if (value == null) return null;
  if (value is! String || value.isEmpty || value.length > 128) {
    throw QuickEntryStreamProtocolError(field);
  }
  return value;
}
