import '../../../domain/models.dart';
import 'quick_entry_batch.dart';
import 'quick_entry_wire.dart';

class QuickEntryValidatedDraft {
  const QuickEntryValidatedDraft({
    required this.id,
    required this.draft,
    required this.selectedByDefault,
  });

  final String id;
  final AgentDraft draft;
  final bool selectedByDefault;
}

class QuickEntryValidatedResponse {
  const QuickEntryValidatedResponse({
    required this.status,
    required this.notices,
    required this.drafts,
  });

  final QuickEntryBatchStatus status;
  final List<QuickEntryNotice> notices;
  final List<QuickEntryValidatedDraft> drafts;
}

/// Client-side whitelist for `POST /agent/drafts` responses. Any violation
/// discards the whole response: a partially trusted batch is never shown.
class QuickEntryResponseValidator {
  static const int maxDrafts = 8;
  static const int maxEvidence = 16;

  /// §6.4 fixes one residual formula for this version; a different formula is
  /// a different computation, not a formatting variant.
  static const String derivationFormula =
      'reference_expense - target_recorded - explicit_candidates';
  static const Set<String> derivationOperandKeys = {
    'reference_expense',
    'target_recorded',
    'explicit_candidates',
  };

  static QuickEntryValidatedResponse validate(
    Map<String, Object?> json, {
    required String requestId,
    required String sourceText,
    required String? contextFingerprint,
    required String targetDate,
    required String referenceDate,
  }) {
    _check(json['schema_version'] == 1, 'schema_version');
    _check(json['request_id'] == requestId, 'request_id');
    final status = switch (json['status']) {
      'ok' => QuickEntryBatchStatus.ok,
      'needs_split' => QuickEntryBatchStatus.needsSplit,
      'no_actionable_items' => QuickEntryBatchStatus.noActionableItems,
      _ => throw const QuickEntryResponseInvalid('status'),
    };
    _check(json['engine'] == 'llm', 'engine');
    _check(json['requires_confirmation'] == true, 'requires_confirmation');

    final notices = <QuickEntryNotice>[];
    for (final item in _list(json['notices'], 'notices')) {
      final map = _map(item, 'notice');
      notices.add(QuickEntryNotice(
        code: _string(map['code'], 'notice.code', maxLength: 64),
        message: _string(map['message'], 'notice.message', maxLength: 512),
      ));
    }

    final draftsJson = _list(json['drafts'], 'drafts');
    _check(draftsJson.length <= maxDrafts, 'drafts>8');
    if (status == QuickEntryBatchStatus.ok) {
      _check(draftsJson.isNotEmpty, 'ok without drafts');
    } else {
      _check(draftsJson.isEmpty, 'non-ok with drafts');
    }

    final drafts = <QuickEntryValidatedDraft>[];
    final ids = <String>{};
    for (final item in draftsJson) {
      final parsed = _draft(
        item,
        sourceText: sourceText,
        contextFingerprint: contextFingerprint,
        targetDate: targetDate,
        referenceDate: referenceDate,
      );
      _check(ids.add(parsed.id), 'duplicate client_draft_id');
      drafts.add(parsed);
    }
    return QuickEntryValidatedResponse(
        status: status, notices: notices, drafts: drafts);
  }

  static QuickEntryValidatedDraft _draft(
    Object? value, {
    required String sourceText,
    required String? contextFingerprint,
    required String targetDate,
    required String referenceDate,
  }) {
    final map = _map(value, 'draft');
    final id = _string(map['client_draft_id'], 'client_draft_id', maxLength: 64);
    final sourceValue = map['source'];
    _check(sourceValue == 'explicit' || sourceValue == 'inferred', 'source');
    final source = agentDraftSourceFromJson(sourceValue);
    final typeValue = map['type'];
    _check(typeValue == 'expense' || typeValue == 'income', 'type');
    final type =
        typeValue == 'income' ? TransactionType.income : TransactionType.expense;

    final amount = _optionalMoney(map['amount'], 'amount');
    if (source == AgentDraftSource.inferred) {
      _check(amount != null && amount > 0, 'inferred amount');
    } else if (amount != null) {
      _check(amount > 0, 'explicit amount');
    }

    final range = _range(map['amount_range']);
    final isApproximate = _bool(map['is_approximate'], 'is_approximate');
    if (range != null) {
      _check(isApproximate, 'range without approximate');
      if (amount != null) {
        _check(
            range.contains(amount) ||
                amount == range.lower ||
                amount == range.upper,
            'amount outside range');
      }
    }

    final currency = _string(map['currency'], 'currency', maxLength: 3);
    _check(RegExp(r'^[A-Z]{3}$').hasMatch(currency), 'currency');
    _optionalString(map['category_hint'], 'category_hint', maxLength: 128);
    _optionalString(map['account_hint'], 'account_hint', maxLength: 128);
    final categoryId =
        _optionalString(map['category_id'], 'category_id', maxLength: 64);
    final accountId =
        _optionalString(map['account_id'], 'account_id', maxLength: 64);
    final date = _string(map['date'], 'date', maxLength: 10);
    _check(isIsoDate(date), 'date');
    final note = _optionalString(map['note'], 'note', maxLength: 256) ?? '';
    final confidence = _number(map['confidence'], 'confidence');
    _check(confidence >= 0 && confidence <= 1, 'confidence');

    final missingFacts = <String>[];
    for (final fact in _list(map['missing_facts'], 'missing_facts')) {
      missingFacts
          .add(_string(fact, 'missing_facts[]', maxLength: 64));
    }
    final selectedByDefault =
        _bool(map['selected_by_default'], 'selected_by_default');

    final evidence = <DraftEvidence>[];
    var hasSourceQuote = false;
    var hasLedgerContext = false;
    final rawEvidence = _list(map['evidence'], 'evidence');
    _check(rawEvidence.length <= maxEvidence, 'evidence>16');
    for (final item in rawEvidence) {
      final entry = _map(item, 'evidence');
      final kindValue = entry['kind'];
      _check(kindValue == 'source_text' || kindValue == 'ledger_context',
          'evidence.kind');
      if (kindValue == 'source_text') {
        final quote = _string(entry['quote'], 'evidence.quote',
            maxLength: sourceText.length + 1);
        final start = _integer(entry['start'], 'evidence.start');
        final end = _integer(entry['end'], 'evidence.end');
        _check(start >= 0, 'evidence.start<0');
        _check(end > start, 'evidence.end<=start');
        _check(end <= codePointLength(sourceText), 'evidence.end>text');
        _check(codePointSlice(sourceText, start, end) == quote,
            'evidence.quote mismatch');
        hasSourceQuote = true;
        evidence.add(DraftEvidence(
          kind: DraftEvidenceKind.sourceText,
          quote: quote,
          start: start,
          end: end,
        ));
      } else {
        final path =
            _string(entry['context_path'], 'evidence.context_path', maxLength: 256);
        final reference = _optionalString(
            entry['reference_date'], 'evidence.reference_date', maxLength: 10);
        if (reference != null) _check(isIsoDate(reference), 'evidence.reference_date');
        hasLedgerContext = true;
        evidence.add(DraftEvidence(
          kind: DraftEvidenceKind.ledgerContext,
          contextPath: path,
          referenceDate: reference,
        ));
      }
    }

    final derivation = _derivation(
      map['derivation'],
      source: source,
      amount: amount,
      contextFingerprint: contextFingerprint,
      targetDate: targetDate,
      referenceDate: referenceDate,
    );

    if (source == AgentDraftSource.explicit) {
      _check(hasSourceQuote, 'explicit without quote');
      _check(derivation == null, 'explicit with derivation');
    } else {
      _check(hasSourceQuote, 'inferred without quote');
      _check(hasLedgerContext, 'inferred without ledger evidence');
      _check(derivation != null, 'inferred without derivation');
      _check(date == targetDate, 'inferred date');
    }

    return QuickEntryValidatedDraft(
      id: id,
      selectedByDefault: selectedByDefault,
      draft: AgentDraft(
        amount: amount ?? 0,
        type: type,
        categoryId: categoryId,
        accountId: accountId,
        date: date,
        note: note,
        confidence: confidence.toDouble(),
        currency: currency,
        missingFacts: missingFacts,
        source: source,
        isApproximate: isApproximate,
        amountRange: range,
        evidence: evidence,
        derivation: derivation,
      ),
    );
  }

  static DraftDerivation? _derivation(
    Object? value, {
    required AgentDraftSource source,
    required double? amount,
    required String? contextFingerprint,
    required String targetDate,
    required String referenceDate,
  }) {
    if (value == null) return null;
    _check(source == AgentDraftSource.inferred, 'derivation on explicit');
    final map = _map(value, 'derivation');
    final kind = _string(map['kind'], 'derivation.kind', maxLength: 64);
    _check(map['reference_date'] == referenceDate, 'derivation.reference_date');
    _check(map['target_date'] == targetDate, 'derivation.target_date');
    final formula =
        _string(map['formula'], 'derivation.formula', maxLength: 256);
    _check(formula == derivationFormula, 'derivation.formula');
    final rawResult = map['result'];
    final parsedResult = _optionalMoney(rawResult, 'derivation.result');
    _check(parsedResult != null, 'derivation.result');
    _check(amount != null && parsedResult == amount,
        'derivation.result!=amount');
    final result = parsedResult!;
    final fingerprint = _string(
        map['context_fingerprint'], 'derivation.context_fingerprint',
        maxLength: 256);
    _check(contextFingerprint != null && fingerprint == contextFingerprint,
        'derivation fingerprint mismatch');
    final operands = <DraftOperand>[];
    final rawOperands = <String, Object?>{};
    for (final item in _list(map['operands'], 'derivation.operands')) {
      final entry = _map(item, 'operand');
      final key = _string(entry['key'], 'operand.key', maxLength: 64);
      _check(derivationOperandKeys.contains(key), 'operand.key');
      _check(!rawOperands.containsKey(key), 'duplicate operand key');
      final operandAmount = _optionalMoney(entry['amount'], 'operand.amount');
      _check(operandAmount != null, 'operand.amount');
      rawOperands[key] = entry['amount'];
      operands.add(DraftOperand(
        key: key,
        label: _string(entry['label'], 'operand.label', maxLength: 64),
        amount: operandAmount!,
        isApproximate: _bool(entry['is_approximate'], 'operand.is_approximate'),
      ));
    }
    _check(operands.length == derivationOperandKeys.length, 'operand keys');
    // §6.4/§8.1.2/§10.3: the client recomputes the residual itself. Exact
    // decimal comparison only — a tolerance must never accept a different
    // formula's result.
    final referenceUnits = moneyUnits(rawOperands['reference_expense']);
    final recordedUnits = moneyUnits(rawOperands['target_recorded']);
    final explicitUnits = moneyUnits(rawOperands['explicit_candidates']);
    final resultUnits = moneyUnits(rawResult);
    _check(
        referenceUnits != null &&
            recordedUnits != null &&
            explicitUnits != null &&
            resultUnits != null,
        'derivation arithmetic');
    _check(
        referenceUnits! - recordedUnits! - explicitUnits! == resultUnits,
        'derivation arithmetic');
    return DraftDerivation(
      kind: kind,
      referenceDate: referenceDate,
      targetDate: targetDate,
      operands: operands,
      formula: formula,
      result: result,
      contextFingerprint: fingerprint,
    );
  }

  static DraftAmountRange? _range(Object? value) {
    if (value == null) return null;
    final map = _map(value, 'amount_range');
    final lower = _optionalMoney(map['lower'], 'amount_range.lower');
    final upper = _optionalMoney(map['upper'], 'amount_range.upper');
    _check(lower != null && upper != null, 'amount_range.bounds');
    final range = DraftAmountRange(
      lower: lower!,
      upper: upper!,
      lowerInclusive: _bool(map['lower_inclusive'], 'lower_inclusive'),
      upperInclusive: _bool(map['upper_inclusive'], 'upper_inclusive'),
    );
    _check(range.isOrdered, 'amount_range.order');
    return range;
  }

  static double? _optionalMoney(Object? value, String field) {
    if (value == null) return null;
    final parsed = parseMoneyText(value);
    _check(parsed != null, field);
    return parsed;
  }

  static String _string(Object? value, String field,
      {int maxLength = 512, int minLength = 1}) {
    _check(value is String, field);
    final text = value as String;
    _check(text.length >= minLength && text.length <= maxLength, field);
    return text;
  }

  static String? _optionalString(Object? value, String field,
      {required int maxLength}) {
    if (value == null) return null;
    return _string(value, field, maxLength: maxLength);
  }

  static bool _bool(Object? value, String field) {
    _check(value is bool, field);
    return value as bool;
  }

  static int _integer(Object? value, String field) {
    _check(value is int, field);
    return value as int;
  }

  static num _number(Object? value, String field) {
    _check(value is num, field);
    return value as num;
  }

  static List<Object?> _list(Object? value, String field) {
    _check(value is List, field);
    return (value as List).cast<Object?>();
  }

  static Map<String, Object?> _map(Object? value, String field) {
    _check(value is Map, field);
    final result = <String, Object?>{};
    for (final entry in (value as Map).entries) {
      _check(entry.key is String, '$field.key');
      result[entry.key as String] = entry.value;
    }
    return result;
  }

  static void _check(bool condition, String reason) {
    if (!condition) throw QuickEntryResponseInvalid(reason);
  }
}
