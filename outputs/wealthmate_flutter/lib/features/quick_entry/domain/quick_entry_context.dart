import 'dart:convert';

import '../../../domain/models.dart';
import 'quick_entry_wire.dart';

class QuickEntryCategoryTotal {
  const QuickEntryCategoryTotal({
    required this.categoryId,
    required this.categoryName,
    required this.cents,
  });

  final String categoryId;
  final String categoryName;
  final int cents;

  Map<String, Object?> toJson() => {
        'category_id': categoryId,
        'category_name': categoryName,
        'expense_total': moneyText(cents / 100),
      };
}

class QuickEntryDayAggregate {
  const QuickEntryDayAggregate({
    required this.cents,
    required this.count,
    this.categoryTotals = const <QuickEntryCategoryTotal>[],
  });

  final int cents;
  final int count;
  final List<QuickEntryCategoryTotal> categoryTotals;

  Map<String, Object?> toJson({bool withCategories = false}) => {
        'expense_total': moneyText(cents / 100),
        'expense_count': count,
        if (withCategories)
          'category_totals': [
            for (final total in categoryTotals) total.toJson(),
          ],
      };
}

class QuickEntryCurrencyContext {
  const QuickEntryCurrencyContext({
    required this.currency,
    required this.referenceDay,
    required this.targetDay,
  });

  final String currency;
  final QuickEntryDayAggregate referenceDay;
  final QuickEntryDayAggregate targetDay;

  Map<String, Object?> toJson() => {
        'currency': currency,
        'reference_day': referenceDay.toJson(withCategories: true),
        'target_day': targetDay.toJson(),
      };
}

/// The privacy-bounded aggregate snapshot sent with every cloud parse: totals,
/// counts, category ids/names and dates only — never transactions, notes,
/// merchants, accounts or balances.
class QuickEntryLedgerContext {
  QuickEntryLedgerContext({
    required this.targetDate,
    required this.referenceDate,
    required this.currencies,
  }) : fingerprint = aggregateFingerprint(
            jsonEncode(_canonicalJson(targetDate, referenceDate, currencies)));

  final String targetDate;
  final String referenceDate;
  final List<QuickEntryCurrencyContext> currencies;
  final String fingerprint;

  static Map<String, Object?> _canonicalJson(
          String targetDate,
          String referenceDate,
          List<QuickEntryCurrencyContext> currencies) =>
      {
        'target_date': targetDate,
        'reference_date': referenceDate,
        'currencies': [for (final item in currencies) item.toJson()],
      };

  Map<String, Object?> toRequestJson() => {
        'status': 'ready',
        'target_date': targetDate,
        'reference_date': referenceDate,
        'fingerprint': fingerprint,
        'currencies': [for (final item in currencies) item.toJson()],
      };

  QuickEntryCurrencyContext? currency(String code) {
    for (final item in currencies) {
      if (item.currency == code) return item;
    }
    return null;
  }
}

class QuickEntryContextBuilder {
  /// Builds the aggregate snapshot for "today" and its previous calendar day.
  /// Deleted transactions and transfers are excluded; not-yet-synced local
  /// transactions are included because the local state is the source of truth.
  static QuickEntryLedgerContext build({
    required FinanceState state,
    required DateTime now,
  }) {
    final target = dateKey(now);
    final reference = dateKey(now.subtract(const Duration(days: 1)));
    final preferred = state.preferredCurrency.trim().toUpperCase();
    final accumulators = <String, _CurrencyAccumulator>{};
    _CurrencyAccumulator accumulator(String currency) =>
        accumulators.putIfAbsent(
            currency, () => _CurrencyAccumulator(currency));
    if (preferred.isNotEmpty) accumulator(preferred);

    for (final transaction in state.transactions) {
      if (transaction.deletedAt != null) continue;
      if (transaction.type != TransactionType.expense) continue;
      if (!transaction.amount.isFinite || transaction.amount <= 0) continue;
      final currency = transaction.currency.trim().toUpperCase();
      if (currency.isEmpty) continue;
      final cents = (transaction.amount * 100).round();
      final entry = accumulator(currency);
      if (transaction.date == target) {
        entry.targetCents += cents;
        entry.targetCount += 1;
      } else if (transaction.date == reference) {
        entry.referenceCents += cents;
        entry.referenceCount += 1;
        final categoryId = transaction.categoryId;
        if (categoryId != null && categoryId.isNotEmpty) {
          entry.categoryCents[categoryId] =
              (entry.categoryCents[categoryId] ?? 0) + cents;
        }
      }
    }

    final codes = accumulators.keys.toList()..sort();
    final currencyContexts = <QuickEntryCurrencyContext>[];
    for (final code in codes) {
      final entry = accumulators[code]!;
      final categoryIds = entry.categoryCents.keys.toList()..sort();
      currencyContexts.add(QuickEntryCurrencyContext(
        currency: code,
        referenceDay: QuickEntryDayAggregate(
          cents: entry.referenceCents,
          count: entry.referenceCount,
          categoryTotals: [
            for (final categoryId in categoryIds)
              QuickEntryCategoryTotal(
                categoryId: categoryId,
                categoryName: _categoryName(state, categoryId),
                cents: entry.categoryCents[categoryId]!,
              ),
          ],
        ),
        targetDay: QuickEntryDayAggregate(
          cents: entry.targetCents,
          count: entry.targetCount,
        ),
      ));
    }

    return QuickEntryLedgerContext(
      targetDate: target,
      referenceDate: reference,
      currencies: currencyContexts,
    );
  }

  static String _categoryName(FinanceState state, String categoryId) {
    for (final category in state.categories) {
      if (category.id != categoryId) continue;
      final name = category.name.trim();
      if (name.isEmpty) break;
      return name.length <= 128 ? name : name.substring(0, 128);
    }
    return categoryId.length <= 128 ? categoryId : categoryId.substring(0, 128);
  }
}

class _CurrencyAccumulator {
  _CurrencyAccumulator(this.currency);

  final String currency;
  int referenceCents = 0;
  int referenceCount = 0;
  int targetCents = 0;
  int targetCount = 0;
  final Map<String, int> categoryCents = <String, int>{};
}

class QuickEntryDraftRequest {
  const QuickEntryDraftRequest({
    required this.requestId,
    required this.text,
    required this.localToday,
    required this.utcOffsetMinutes,
    required this.preferredCurrency,
    required this.context,
  });

  final String requestId;
  final String text;
  final String localToday;
  final int utcOffsetMinutes;
  final String preferredCurrency;
  final QuickEntryLedgerContext context;

  Map<String, Object?> toJson() => {
        'schema_version': 1,
        'request_id': requestId,
        'text': text,
        'local_today': localToday,
        'utc_offset_minutes': utcOffsetMinutes,
        'preferred_currency': preferredCurrency,
        'ledger_context': context.toRequestJson(),
      };
}
