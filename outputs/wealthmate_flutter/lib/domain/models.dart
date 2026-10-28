enum AccountType { asset, liability }

enum AccountKind {
  cash,
  bankCard,
  wechat,
  alipay,
  foreign,
  fundInvestment,
  creditCard,
  loan,
  other
}

enum TransactionType { income, expense, transfer }

enum BudgetStatus { healthy, warning, over }

AccountType accountTypeFromJson(Object? value) =>
    value == 'liability' ? AccountType.liability : AccountType.asset;

String accountTypeToJson(AccountType value) => value.name;

AccountKind accountKindFromJson(Object? value) {
  return AccountKind.values.firstWhere(
    (item) =>
        item.name == value ||
        (item == AccountKind.bankCard && value == 'bank_card') ||
        (item == AccountKind.fundInvestment && value == 'fund_investment') ||
        (item == AccountKind.creditCard && value == 'credit_card'),
    orElse: () => AccountKind.other,
  );
}

String accountKindToJson(AccountKind value) {
  switch (value) {
    case AccountKind.bankCard:
      return 'bank_card';
    case AccountKind.fundInvestment:
      return 'fund_investment';
    case AccountKind.creditCard:
      return 'credit_card';
    default:
      return value.name;
  }
}

TransactionType transactionTypeFromJson(Object? value) {
  return TransactionType.values.firstWhere(
    (item) => item.name == value,
    orElse: () => TransactionType.expense,
  );
}

String transactionTypeToJson(TransactionType value) => value.name;

class Account {
  const Account({
    required this.id,
    required this.name,
    required this.type,
    this.accountKind = AccountKind.other,
    this.openingBalance = 0,
    this.currency = 'CNY',
    this.openingCnyAmount,
    this.exchangeRate,
    this.exchangeRateDate,
    this.exchangeRateSource,
    this.isLiquid = false,
    this.isDefaultPayment = false,
    this.note = '',
    this.archivedAt,
    this.deletedAt,
    this.serverVersion,
    this.updatedAt,
  });

  final String id;
  final String name;
  final AccountType type;
  final AccountKind accountKind;
  final double openingBalance;
  final String currency;
  final double? openingCnyAmount;
  final double? exchangeRate;
  final String? exchangeRateDate;
  final String? exchangeRateSource;
  final bool isLiquid;
  final bool isDefaultPayment;
  final String note;
  final String? archivedAt;
  bool get isActive => deletedAt == null && archivedAt == null;
  final String? deletedAt;
  final int? serverVersion;
  final String? updatedAt;

  Account copyWith({
    String? id,
    String? name,
    AccountType? type,
    AccountKind? accountKind,
    double? openingBalance,
    String? currency,
    double? openingCnyAmount,
    double? exchangeRate,
    String? exchangeRateDate,
    String? exchangeRateSource,
    bool? isLiquid,
    bool? isDefaultPayment,
    String? note,
    String? archivedAt,
    bool clearArchivedAt = false,
    String? deletedAt,
    int? serverVersion,
    String? updatedAt,
  }) {
    return Account(
      id: id ?? this.id,
      name: name ?? this.name,
      type: type ?? this.type,
      accountKind: accountKind ?? this.accountKind,
      openingBalance: openingBalance ?? this.openingBalance,
      currency: currency ?? this.currency,
      openingCnyAmount: openingCnyAmount ?? this.openingCnyAmount,
      exchangeRate: exchangeRate ?? this.exchangeRate,
      exchangeRateDate: exchangeRateDate ?? this.exchangeRateDate,
      exchangeRateSource: exchangeRateSource ?? this.exchangeRateSource,
      isLiquid: isLiquid ?? this.isLiquid,
      isDefaultPayment: isDefaultPayment ?? this.isDefaultPayment,
      note: note ?? this.note,
      archivedAt: clearArchivedAt ? null : archivedAt ?? this.archivedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      serverVersion: serverVersion ?? this.serverVersion,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'type': accountTypeToJson(type),
        'account_kind': accountKindToJson(accountKind),
        'opening_balance': openingBalance,
        'currency': currency,
        'opening_cny_amount': openingCnyAmount,
        'opening_exchange_rate': exchangeRate,
        'opening_rate_date': exchangeRateDate,
        'opening_rate_source': exchangeRateSource,
        'is_liquid': isLiquid,
        'is_default_payment': isDefaultPayment,
        'note': note,
        'archived_at': archivedAt,
        'deleted_at': deletedAt,
        'server_version': serverVersion,
        'updated_at': updatedAt,
      };

  factory Account.fromJson(Map<String, Object?> json) => Account(
        id: json['id']! as String,
        name: json['name']! as String,
        type: accountTypeFromJson(json['type']),
        accountKind: accountKindFromJson(json['account_kind']),
        openingBalance: (json['opening_balance'] as num?)?.toDouble() ?? 0,
        currency: json['currency'] as String? ?? 'CNY',
        openingCnyAmount: (json['opening_cny_amount'] as num?)?.toDouble(),
        exchangeRate: (json['opening_exchange_rate'] as num?)?.toDouble(),
        exchangeRateDate: json['opening_rate_date'] as String?,
        exchangeRateSource: json['opening_rate_source'] as String?,
        isLiquid: json['is_liquid'] as bool? ?? false,
        isDefaultPayment: json['is_default_payment'] as bool? ?? false,
        note: json['note'] as String? ?? '',
        archivedAt: json['archived_at'] as String?,
        deletedAt: json['deleted_at'] as String?,
        serverVersion: (json['server_version'] as num?)?.toInt(),
        updatedAt: json['updated_at'] as String?,
      );
}

class Category {
  const Category(
      {required this.id,
      required this.name,
      this.active = true,
      this.type = TransactionType.expense});

  final String id;
  final String name;
  final bool active;
  final TransactionType type;

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'active': active,
        'type': transactionTypeToJson(type)
      };

  factory Category.fromJson(Map<String, Object?> json) => Category(
        id: json['id']! as String,
        name: json['name']! as String,
        active: json['active'] as bool? ?? true,
        type: transactionTypeFromJson(json['type'] ?? json['kind']),
      );
}

class FinanceTransaction {
  const FinanceTransaction({
    required this.id,
    required this.date,
    this.occurredAt,
    required this.type,
    required this.amount,
    this.categoryId,
    this.accountId,
    this.fromAccountId,
    this.toAccountId,
    this.note = '',
    this.currency = 'CNY',
    this.cnyAmount,
    this.exchangeRate,
    this.exchangeRateDate,
    this.exchangeRateSource,
    this.conversionStatus = 'ready',
    String? clientOpId,
    this.serverVersion,
    this.updatedAt,
    this.deletedAt,
  }) : clientOpId = clientOpId ?? id;

  final String id;
  final String date;
  final String? occurredAt;
  final TransactionType type;
  final double amount;
  final String? categoryId;
  final String? accountId;
  final String? fromAccountId;
  final String? toAccountId;
  final String note;
  final String currency;
  final double? cnyAmount;
  final double? exchangeRate;
  final String? exchangeRateDate;
  final String? exchangeRateSource;
  final String conversionStatus;
  final String clientOpId;
  final int? serverVersion;
  final String? updatedAt;
  final String? deletedAt;

  FinanceTransaction copyWith({
    String? id,
    String? date,
    String? occurredAt,
    TransactionType? type,
    double? amount,
    String? categoryId,
    String? accountId,
    String? fromAccountId,
    String? toAccountId,
    String? note,
    String? currency,
    double? cnyAmount,
    double? exchangeRate,
    String? exchangeRateDate,
    String? exchangeRateSource,
    String? conversionStatus,
    String? clientOpId,
    int? serverVersion,
    String? updatedAt,
    String? deletedAt,
  }) {
    return FinanceTransaction(
      id: id ?? this.id,
      date: date ?? this.date,
      occurredAt: occurredAt ?? this.occurredAt,
      type: type ?? this.type,
      amount: amount ?? this.amount,
      categoryId: categoryId ?? this.categoryId,
      accountId: accountId ?? this.accountId,
      fromAccountId: fromAccountId ?? this.fromAccountId,
      toAccountId: toAccountId ?? this.toAccountId,
      note: note ?? this.note,
      currency: currency ?? this.currency,
      cnyAmount: cnyAmount ?? this.cnyAmount,
      exchangeRate: exchangeRate ?? this.exchangeRate,
      exchangeRateDate: exchangeRateDate ?? this.exchangeRateDate,
      exchangeRateSource: exchangeRateSource ?? this.exchangeRateSource,
      conversionStatus: conversionStatus ?? this.conversionStatus,
      clientOpId: clientOpId ?? this.clientOpId,
      serverVersion: serverVersion ?? this.serverVersion,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
    );
  }

  Map<String, Object?> toJson() => {
        'id': id,
        'date': date,
        'occurred_at': occurredAt,
        'type': transactionTypeToJson(type),
        'amount': amount,
        'currency': currency,
        'original_amount': amount,
        'original_currency': currency,
        'cny_amount': cnyAmount,
        'exchange_rate': exchangeRate,
        'exchange_rate_date': exchangeRateDate,
        'exchange_rate_source': exchangeRateSource,
        'conversion_status': conversionStatus,
        'category_id': categoryId,
        'account_id': accountId,
        'from_account_id': fromAccountId,
        'to_account_id': toAccountId,
        'note': note,
        'client_op_id': clientOpId,
        'server_version': serverVersion,
        'updated_at': updatedAt,
        'deleted_at': deletedAt,
      };

  factory FinanceTransaction.fromJson(Map<String, Object?> json) =>
      FinanceTransaction(
        id: json['id']! as String,
        date: json['date']! as String,
        occurredAt: json['occurred_at'] as String?,
        type: transactionTypeFromJson(json['type']),
        amount: (json['amount'] as num?)?.toDouble() ?? 0,
        currency: json['currency'] as String? ??
            (json['original_currency'] as String? ?? 'CNY'),
        cnyAmount: (json['cny_amount'] as num?)?.toDouble(),
        exchangeRate: (json['exchange_rate'] as num?)?.toDouble(),
        exchangeRateDate: json['exchange_rate_date'] as String?,
        exchangeRateSource: json['exchange_rate_source'] as String?,
        conversionStatus: json['conversion_status'] as String? ?? 'ready',
        categoryId: json['category_id'] as String?,
        accountId: json['account_id'] as String?,
        fromAccountId: json['from_account_id'] as String?,
        toAccountId: json['to_account_id'] as String?,
        note: json['note'] as String? ?? '',
        clientOpId: json['client_op_id'] as String?,
        serverVersion: (json['server_version'] as num?)?.toInt(),
        updatedAt: json['updated_at'] as String?,
        deletedAt: json['deleted_at'] as String?,
      );
}

class Budget {
  const Budget({
    required this.id,
    required this.month,
    required this.categoryId,
    required this.limit,
    this.active = true,
    this.serverVersion,
    this.updatedAt,
    this.deletedAt,
  });

  final String id;
  final String month;
  final String categoryId;
  final double limit;
  final bool active;
  final int? serverVersion;
  final String? updatedAt;
  final String? deletedAt;

  Map<String, Object?> toJson() => {
        'id': id,
        'month': month,
        'category_id': categoryId,
        'limit': limit,
        'active': active,
        'server_version': serverVersion,
        'updated_at': updatedAt,
        'deleted_at': deletedAt,
      };

  factory Budget.fromJson(Map<String, Object?> json) => Budget(
        id: json['id']! as String,
        month: json['month']! as String,
        categoryId: json['category_id']! as String,
        limit: (json['limit'] as num?)?.toDouble() ?? 0,
        active: json['active'] as bool? ?? true,
        serverVersion: (json['server_version'] as num?)?.toInt(),
        updatedAt: json['updated_at'] as String?,
        deletedAt: json['deleted_at'] as String?,
      );
}

class ExchangeRateSnapshot {
  const ExchangeRateSnapshot(
      {required this.baseCurrency,
      this.quoteCurrency = 'CNY',
      required this.rate,
      required this.rateDate,
      required this.source,
      this.updatedAt});

  final String baseCurrency;
  final String quoteCurrency;
  final double rate;
  final String rateDate;
  final String source;
  final String? updatedAt;

  Map<String, Object?> toJson() => {
        'base_currency': baseCurrency,
        'quote_currency': quoteCurrency,
        'rate': rate,
        'rate_date': rateDate,
        'source': source,
        'updated_at': updatedAt
      };

  factory ExchangeRateSnapshot.fromJson(Map<String, Object?> json) =>
      ExchangeRateSnapshot(
          baseCurrency: json['base_currency']! as String,
          quoteCurrency: json['quote_currency'] as String? ?? 'CNY',
          rate: (json['rate'] as num?)?.toDouble() ?? 0,
          rateDate: json['rate_date']! as String,
          source: json['source']! as String,
          updatedAt: json['updated_at'] as String?);
}

class Report {
  const Report(
      {required this.id,
      required this.month,
      required this.title,
      required this.summary,
      required this.generatedAt});

  final String id;
  final String month;
  final String title;
  final String summary;
  final String generatedAt;

  Map<String, Object?> toJson() => {
        'id': id,
        'month': month,
        'title': title,
        'summary': summary,
        'generated_at': generatedAt
      };

  factory Report.fromJson(Map<String, Object?> json) => Report(
        id: json['id']! as String,
        month: json['month']! as String,
        title: json['title']! as String,
        summary: json['summary']! as String,
        generatedAt: json['generated_at']! as String,
      );
}

class SyncState {
  const SyncState(
      {this.serverVersion = 0,
      this.lastSyncedAt,
      this.isSyncing = false,
      this.error});

  final int serverVersion;
  final String? lastSyncedAt;
  final bool isSyncing;
  final String? error;

  SyncState copyWith(
          {int? serverVersion,
          String? lastSyncedAt,
          bool? isSyncing,
          String? error}) =>
      SyncState(
        serverVersion: serverVersion ?? this.serverVersion,
        lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
        isSyncing: isSyncing ?? this.isSyncing,
        error: error,
      );
}

class QuickMemory {
  const QuickMemory({
    required this.key,
    this.categoryId,
    this.accountId,
    this.updatedAt,
  });

  final String key;
  final String? categoryId;
  final String? accountId;
  final String? updatedAt;

  QuickMemory copyWith({
    String? key,
    String? categoryId,
    String? accountId,
    String? updatedAt,
  }) {
    return QuickMemory(
      key: key ?? this.key,
      categoryId: categoryId ?? this.categoryId,
      accountId: accountId ?? this.accountId,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, Object?> toJson() => {
        'key': key,
        'category_id': categoryId,
        'account_id': accountId,
        'updated_at': updatedAt,
      };

  factory QuickMemory.fromJson(Map<String, Object?> json) => QuickMemory(
        key: json['key']! as String,
        categoryId: json['category_id'] as String?,
        accountId: json['account_id'] as String?,
        updatedAt: json['updated_at'] as String?,
      );
}

class FinanceState {
  const FinanceState({
    this.schemaVersion = 1,
    this.currentMonth = '',
    this.preferredCurrency = 'CNY',
    this.commonCurrencies = const ['CNY', 'HKD', 'USD', 'EUR', 'JPY', 'GBP'],
    this.accounts = const <Account>[],
    this.categories = const <Category>[],
    this.transactions = const <FinanceTransaction>[],
    this.budgets = const <Budget>[],
    this.exchangeRates = const <ExchangeRateSnapshot>[],
    this.reports = const <Report>[],
    this.conflicts = const <String>[],
    this.quickMemories = const <QuickMemory>[],
    this.defaultAccountId,
    this.syncState = const SyncState(),
  });

  final int schemaVersion;
  final String currentMonth;
  final String preferredCurrency;
  final List<String> commonCurrencies;
  final List<Account> accounts;
  final List<Category> categories;
  final List<FinanceTransaction> transactions;
  final List<Budget> budgets;
  final List<ExchangeRateSnapshot> exchangeRates;
  final List<Report> reports;
  final List<String> conflicts;
  final List<QuickMemory> quickMemories;
  final String? defaultAccountId;
  final SyncState syncState;

  FinanceState copyWith({
    int? schemaVersion,
    String? currentMonth,
    String? preferredCurrency,
    List<String>? commonCurrencies,
    List<Account>? accounts,
    List<Category>? categories,
    List<FinanceTransaction>? transactions,
    List<Budget>? budgets,
    List<ExchangeRateSnapshot>? exchangeRates,
    List<Report>? reports,
    List<String>? conflicts,
    List<QuickMemory>? quickMemories,
    String? defaultAccountId,
    SyncState? syncState,
  }) {
    return FinanceState(
      schemaVersion: schemaVersion ?? this.schemaVersion,
      currentMonth: currentMonth ?? this.currentMonth,
      preferredCurrency: preferredCurrency ?? this.preferredCurrency,
      commonCurrencies: commonCurrencies ?? this.commonCurrencies,
      accounts: accounts ?? this.accounts,
      categories: categories ?? this.categories,
      transactions: transactions ?? this.transactions,
      budgets: budgets ?? this.budgets,
      exchangeRates: exchangeRates ?? this.exchangeRates,
      reports: reports ?? this.reports,
      conflicts: conflicts ?? this.conflicts,
      quickMemories: quickMemories ?? this.quickMemories,
      defaultAccountId: defaultAccountId ?? this.defaultAccountId,
      syncState: syncState ?? this.syncState,
    );
  }

  Map<String, Object?> toJson() => {
        'schema_version': schemaVersion,
        'current_month': currentMonth,
        'preferred_currency': preferredCurrency,
        'common_currencies': commonCurrencies,
        'accounts': accounts.map((item) => item.toJson()).toList(),
        'categories': categories.map((item) => item.toJson()).toList(),
        'transactions': transactions.map((item) => item.toJson()).toList(),
        'budgets': budgets.map((item) => item.toJson()).toList(),
        'exchange_rates': exchangeRates.map((item) => item.toJson()).toList(),
        'reports': reports.map((item) => item.toJson()).toList(),
        'conflicts': conflicts,
        'quick_memories': quickMemories.map((item) => item.toJson()).toList(),
        'default_account_id': defaultAccountId,
        'sync_state': {
          'server_version': syncState.serverVersion,
          if (syncState.lastSyncedAt != null)
            'last_synced_at': syncState.lastSyncedAt,
        },
      };

  static int _serverVersionFromJson(Object? value) {
    if (value is! Map) return 0;
    final serverVersion = value['server_version'];
    return serverVersion is num ? serverVersion.toInt() : 0;
  }

  factory FinanceState.fromJson(Map<String, Object?> json) => FinanceState(
        schemaVersion: (json['schema_version'] as num?)?.toInt() ?? 1,
        currentMonth: json['current_month'] as String? ?? '',
        preferredCurrency: json['preferred_currency'] as String? ?? 'CNY',
        commonCurrencies:
            (json['common_currencies'] as List?)?.cast<String>() ??
                const ['CNY', 'HKD', 'USD', 'EUR', 'JPY', 'GBP'],
        accounts: ((json['accounts'] as List<Object?>?) ?? const <Object?>[])
            .map((item) =>
                Account.fromJson((item! as Map).cast<String, Object?>()))
            .toList(),
        categories:
            ((json['categories'] as List<Object?>?) ?? const <Object?>[])
                .map((item) =>
                    Category.fromJson((item! as Map).cast<String, Object?>()))
                .toList(),
        transactions:
            ((json['transactions'] as List<Object?>?) ?? const <Object?>[])
                .map((item) => FinanceTransaction.fromJson(
                    (item! as Map).cast<String, Object?>()))
                .toList(),
        budgets: ((json['budgets'] as List<Object?>?) ?? const <Object?>[])
            .map((item) =>
                Budget.fromJson((item! as Map).cast<String, Object?>()))
            .toList(),
        exchangeRates:
            ((json['exchange_rates'] as List<Object?>?) ?? const <Object?>[])
                .map((item) => ExchangeRateSnapshot.fromJson(
                    (item! as Map).cast<String, Object?>()))
                .toList(),
        reports: ((json['reports'] as List<Object?>?) ?? const <Object?>[])
            .map((item) =>
                Report.fromJson((item! as Map).cast<String, Object?>()))
            .toList(),
        conflicts: ((json['conflicts'] as List<Object?>?) ?? const <Object?>[])
            .cast<String>(),
        quickMemories: ((json['quick_memories'] as List<Object?>?) ??
                const <Object?>[])
            .map((item) =>
                QuickMemory.fromJson((item! as Map).cast<String, Object?>()))
            .toList(),
        defaultAccountId: json['default_account_id'] as String?,
        syncState: SyncState(
            serverVersion: _serverVersionFromJson(json['sync_state']),
            lastSyncedAt: json['sync_state'] is Map
                ? (json['sync_state'] as Map)['last_synced_at'] as String?
                : null),
      );
}

/// Where a candidate card came from. Inferred cards are ledger-based推算 and
/// must stay unselected until the user explicitly ticks them.
enum AgentDraftSource { explicit, inferred }

AgentDraftSource agentDraftSourceFromJson(Object? value) =>
    value == 'inferred' ? AgentDraftSource.inferred : AgentDraftSource.explicit;

String agentDraftSourceToJson(AgentDraftSource value) => value.name;

/// The bounded spoken range behind an approximate amount ("40多块" -> [40, 50)).
class DraftAmountRange {
  const DraftAmountRange({
    required this.lower,
    required this.upper,
    this.lowerInclusive = true,
    this.upperInclusive = false,
  });

  final double lower;
  final double upper;
  final bool lowerInclusive;
  final bool upperInclusive;

  bool get isOrdered =>
      lower < upper ||
      (lower == upper && lowerInclusive && upperInclusive);

  bool contains(double value) =>
      (lowerInclusive ? value >= lower : value > lower) &&
      (upperInclusive ? value <= upper : value < upper);
}

enum DraftEvidenceKind { sourceText, ledgerContext }

DraftEvidenceKind draftEvidenceKindFromJson(Object? value) =>
    value == 'ledger_context'
        ? DraftEvidenceKind.ledgerContext
        : DraftEvidenceKind.sourceText;

String draftEvidenceKindToJson(DraftEvidenceKind value) =>
    value == DraftEvidenceKind.ledgerContext ? 'ledger_context' : 'source_text';

/// A single traceable basis for a card: a verbatim slice of the user's text
/// (code point offsets, end exclusive) or a named ledger aggregate.
class DraftEvidence {
  const DraftEvidence({
    required this.kind,
    this.quote,
    this.start,
    this.end,
    this.contextPath,
    this.referenceDate,
  });

  final DraftEvidenceKind kind;
  final String? quote;
  final int? start;
  final int? end;
  final String? contextPath;
  final String? referenceDate;

  DraftEvidence copyWith({
    DraftEvidenceKind? kind,
    String? quote,
    int? start,
    int? end,
    String? contextPath,
    String? referenceDate,
  }) =>
      DraftEvidence(
        kind: kind ?? this.kind,
        quote: quote ?? this.quote,
        start: start ?? this.start,
        end: end ?? this.end,
        contextPath: contextPath ?? this.contextPath,
        referenceDate: referenceDate ?? this.referenceDate,
      );
}

class DraftOperand {
  const DraftOperand({
    required this.key,
    required this.label,
    required this.amount,
    this.isApproximate = false,
  });

  final String key;
  final String label;
  final double amount;
  final bool isApproximate;
}

/// The auditable arithmetic behind an inferred card. Kept on the session-level
/// draft only; it is never persisted, synced or backed up.
class DraftDerivation {
  const DraftDerivation({
    required this.kind,
    required this.referenceDate,
    required this.targetDate,
    required this.operands,
    required this.formula,
    required this.result,
    required this.contextFingerprint,
  });

  final String kind;
  final String referenceDate;
  final String targetDate;
  final List<DraftOperand> operands;
  final String formula;
  final double result;
  final String contextFingerprint;
}

class AgentDraft {
  const AgentDraft({
    required this.amount,
    required this.type,
    required this.categoryId,
    required this.accountId,
    required this.date,
    required this.note,
    required this.confidence,
    this.fromAccountId,
    this.toAccountId,
    this.currency = 'CNY',
    this.missingFacts = const <String>[],
    this.source = AgentDraftSource.explicit,
    this.isApproximate = false,
    this.amountRange,
    this.evidence = const <DraftEvidence>[],
    this.derivation,
  });

  final double amount;
  final TransactionType type;
  final String? categoryId;
  final String? accountId;
  final String date;
  final String note;
  final double confidence;
  final String? fromAccountId;
  final String? toAccountId;
  final String currency;
  final List<String> missingFacts;
  final AgentDraftSource source;
  final bool isApproximate;
  final DraftAmountRange? amountRange;
  final List<DraftEvidence> evidence;
  final DraftDerivation? derivation;

  bool get isInferred => source == AgentDraftSource.inferred;

  /// The first verbatim phrase this card rests on, if any.
  String? get primaryQuote {
    for (final item in evidence) {
      if (item.kind == DraftEvidenceKind.sourceText) {
        final quote = item.quote;
        if (quote != null && quote.isNotEmpty) return quote;
      }
    }
    return null;
  }

  AgentDraft copyWith({
    double? amount,
    TransactionType? type,
    String? categoryId,
    String? accountId,
    String? date,
    String? note,
    double? confidence,
    String? fromAccountId,
    String? toAccountId,
    String? currency,
    List<String>? missingFacts,
    AgentDraftSource? source,
    bool? isApproximate,
    DraftAmountRange? amountRange,
    List<DraftEvidence>? evidence,
    DraftDerivation? derivation,
    bool clearCategoryId = false,
    bool clearAccountId = false,
    bool clearAmountRange = false,
    bool clearDerivation = false,
  }) {
    return AgentDraft(
      amount: amount ?? this.amount,
      type: type ?? this.type,
      categoryId: clearCategoryId ? null : categoryId ?? this.categoryId,
      accountId: clearAccountId ? null : accountId ?? this.accountId,
      date: date ?? this.date,
      note: note ?? this.note,
      confidence: confidence ?? this.confidence,
      fromAccountId: fromAccountId ?? this.fromAccountId,
      toAccountId: toAccountId ?? this.toAccountId,
      currency: currency ?? this.currency,
      missingFacts: missingFacts ?? this.missingFacts,
      source: source ?? this.source,
      isApproximate: isApproximate ?? this.isApproximate,
      amountRange:
          clearAmountRange ? null : amountRange ?? this.amountRange,
      evidence: evidence ?? this.evidence,
      derivation: clearDerivation ? null : derivation ?? this.derivation,
    );
  }
}

class UserProfile {
  const UserProfile({
    required this.id,
    required this.username,
    required this.displayName,
    this.quickMemories = const <QuickMemory>[],
  });

  final String id;
  final String username;
  final String displayName;
  final List<QuickMemory> quickMemories;

  Map<String, Object?> toJson() => {
        'id': id,
        'username': username,
        'display_name': displayName,
        'quick_memories': quickMemories.map((item) => item.toJson()).toList(),
      };

  factory UserProfile.fromJson(Map<String, Object?> json) => UserProfile(
        id: json['id']! as String,
        username: json['username']! as String,
        displayName:
            json['display_name'] as String? ?? json['username']! as String,
        quickMemories: ((json['quick_memories'] as List<Object?>?) ??
                const <Object?>[])
            .map((item) =>
                QuickMemory.fromJson((item! as Map).cast<String, Object?>()))
            .toList(),
      );
}

class AccountBalance {
  const AccountBalance({required this.account, required this.balance});

  final Account account;
  final double balance;
}

class BudgetProgress {
  const BudgetProgress(
      {required this.budget, required this.spent, required this.status});

  final Budget budget;
  final double spent;
  final BudgetStatus status;

  double get ratio => budget.limit <= 0 ? 0 : spent / budget.limit;
}

enum BudgetAlertLevel { warning, exhausted, over }

class BudgetAlert {
  const BudgetAlert(
      {required this.budget, required this.spent, required this.level});

  final Budget budget;
  final double spent;
  final BudgetAlertLevel level;

  String get key => 'budget:${budget.id}:${budget.month}:${level.name}';
}

class FinanceMetrics {
  const FinanceMetrics({
    required this.monthKey,
    required this.income,
    required this.expense,
    required this.savings,
    required this.savingsRate,
    required this.accountBalances,
    required this.assetTotal,
    required this.liabilityTotal,
    required this.netWorth,
    required this.budgetProgress,
    this.pendingConversionCount = 0,
  });

  final String monthKey;
  final double income;
  final double expense;
  final double savings;
  final double savingsRate;
  final List<AccountBalance> accountBalances;
  final double assetTotal;
  final double liabilityTotal;
  final double netWorth;
  final List<BudgetProgress> budgetProgress;
  final int pendingConversionCount;

  /// Backward-compatible alias for consumers that used the original name.
  double get liabilities => liabilityTotal;
}
