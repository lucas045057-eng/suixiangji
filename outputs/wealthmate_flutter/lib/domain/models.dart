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

enum TransactionType { income, expense, transfer, adjustment }

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
  // Recognise adjustment explicitly. Falling through to expense would turn a
  // balance correction into a consumption record.
  if (value == 'adjustment') return TransactionType.adjustment;
  return TransactionType.values.firstWhere(
    (item) => item.name == value,
    orElse: () => TransactionType.expense,
  );
}

double? _jsonDouble(Object? value) {
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value);
  return null;
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
    bool clearOpeningConversion = false,
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
      openingCnyAmount: clearOpeningConversion
          ? null
          : openingCnyAmount ?? this.openingCnyAmount,
      exchangeRate:
          clearOpeningConversion ? null : exchangeRate ?? this.exchangeRate,
      exchangeRateDate: clearOpeningConversion
          ? null
          : exchangeRateDate ?? this.exchangeRateDate,
      exchangeRateSource: clearOpeningConversion
          ? null
          : exchangeRateSource ?? this.exchangeRateSource,
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
      this.type = TransactionType.expense,
      this.serverVersion});

  final String id;
  final String name;
  final bool active;
  final TransactionType type;

  /// Server-assigned version used as the V2 compare-and-set baseline. Null for
  /// a category that has never been accepted by the server; never fabricated.
  final int? serverVersion;

  Category copyWith({
    String? id,
    String? name,
    bool? active,
    TransactionType? type,
    int? serverVersion,
  }) =>
      Category(
        id: id ?? this.id,
        name: name ?? this.name,
        active: active ?? this.active,
        type: type ?? this.type,
        serverVersion: serverVersion ?? this.serverVersion,
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'active': active,
        'type': transactionTypeToJson(type),
        'server_version': serverVersion,
      };

  factory Category.fromJson(Map<String, Object?> json) => Category(
        id: json['id']! as String,
        name: json['name']! as String,
        active: json['active'] as bool? ?? true,
        type: transactionTypeFromJson(json['type'] ?? json['kind']),
        serverVersion: (json['server_version'] as num?)?.toInt(),
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
    this.adjustmentMeta,
    this.reversesTransactionId,
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

  /// Balance-calibration metadata. Present only on adjustment rows.
  final Map<String, Object?>? adjustmentMeta;

  /// The original calibration this row reverses, if any.
  final String? reversesTransactionId;
  final String clientOpId;
  final int? serverVersion;
  final String? updatedAt;
  final String? deletedAt;

  bool get isAdjustment => type == TransactionType.adjustment;

  /// A reversal is itself an adjustment, but it may not be reversed again.
  bool get isReversal => isAdjustment && reversesTransactionId != null;

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
    Map<String, Object?>? adjustmentMeta,
    String? reversesTransactionId,
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
      adjustmentMeta: adjustmentMeta ?? this.adjustmentMeta,
      reversesTransactionId:
          reversesTransactionId ?? this.reversesTransactionId,
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
        'adjustment_meta': adjustmentMeta,
        'reverses_transaction_id': reversesTransactionId,
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
        amount: _jsonDouble(json['amount']) ?? 0,
        currency: json['currency'] as String? ??
            (json['original_currency'] as String? ?? 'CNY'),
        cnyAmount: _jsonDouble(json['cny_amount']),
        exchangeRate: _jsonDouble(json['exchange_rate']),
        exchangeRateDate: json['exchange_rate_date'] as String?,
        exchangeRateSource: json['exchange_rate_source'] as String?,
        conversionStatus: json['conversion_status'] as String? ?? 'ready',
        adjustmentMeta: json['adjustment_meta'] is Map
            ? (json['adjustment_meta']! as Map).cast<String, Object?>()
            : null,
        reversesTransactionId: json['reverses_transaction_id'] as String?,
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

/// A locally saved balance-calibration target.
///
/// It is only written when the adjustment could not be submitted (offline or
/// a rejected command); a draft never changes a balance by itself.
class CalibrationDraft {
  const CalibrationDraft({
    required this.accountId,
    required this.targetCny,
    required this.effectiveOn,
    required this.createdAt,
    this.expectedCurrentCny,
    this.basisToken,
    this.basisExpiresAt,
    this.basisBalanceCny,
    this.clientOpId,
    this.adjustmentId,
  });

  final String accountId;
  final double targetCny;
  final String effectiveOn;
  final String createdAt;

  /// The raw six-decimal balance the target was compared against, when known.
  final double? expectedCurrentCny;

  /// Server-issued short-lived proof of the balance at [effectiveOn]. It is
  /// persisted verbatim and re-sent unchanged on retry; the client must not
  /// refresh it just because a local timeout elapsed.
  final String? basisToken;
  final String? basisExpiresAt;

  /// The authoritative six-decimal balance carried by [basisToken].
  final String? basisBalanceCny;

  /// The operation identity is persisted with the token so an ambiguous
  /// outage can be retried with the same `client_op_id`.
  final String? clientOpId;
  final String? adjustmentId;

  CalibrationDraft copyWith({
    String? accountId,
    double? targetCny,
    String? effectiveOn,
    String? createdAt,
    double? expectedCurrentCny,
    String? basisToken,
    String? basisExpiresAt,
    String? basisBalanceCny,
    String? clientOpId,
    String? adjustmentId,
    bool clearBasis = false,
    bool clearOperation = false,
  }) =>
      CalibrationDraft(
        accountId: accountId ?? this.accountId,
        targetCny: targetCny ?? this.targetCny,
        effectiveOn: effectiveOn ?? this.effectiveOn,
        createdAt: createdAt ?? this.createdAt,
        expectedCurrentCny: expectedCurrentCny ?? this.expectedCurrentCny,
        basisToken: clearBasis ? null : (basisToken ?? this.basisToken),
        basisExpiresAt:
            clearBasis ? null : (basisExpiresAt ?? this.basisExpiresAt),
        basisBalanceCny:
            clearBasis ? null : (basisBalanceCny ?? this.basisBalanceCny),
        clientOpId: clearOperation ? null : (clientOpId ?? this.clientOpId),
        adjustmentId:
            clearOperation ? null : (adjustmentId ?? this.adjustmentId),
      );

  Map<String, Object?> toJson() => {
        'account_id': accountId,
        'target_cny': targetCny,
        'effective_on': effectiveOn,
        'created_at': createdAt,
        'expected_current_cny': expectedCurrentCny,
        if (basisToken != null) 'basis_token': basisToken,
        if (basisExpiresAt != null) 'basis_expires_at': basisExpiresAt,
        if (basisBalanceCny != null) 'basis_balance_cny': basisBalanceCny,
        if (clientOpId != null) 'client_op_id': clientOpId,
        if (adjustmentId != null) 'adjustment_id': adjustmentId,
      };

  factory CalibrationDraft.fromJson(Map<String, Object?> json) =>
      CalibrationDraft(
        accountId: json['account_id']! as String,
        targetCny: _jsonDouble(json['target_cny']) ?? 0,
        effectiveOn: json['effective_on'] as String? ?? '',
        createdAt: json['created_at'] as String? ?? '',
        expectedCurrentCny: _jsonDouble(json['expected_current_cny']),
        basisToken: json['basis_token'] as String?,
        basisExpiresAt: json['basis_expires_at'] as String?,
        basisBalanceCny: json['basis_balance_cny'] as String?,
        clientOpId: json['client_op_id'] as String?,
        adjustmentId: json['adjustment_id'] as String?,
      );
}

/// Server-issued proof of an account's CNY book balance on a business date.
///
/// The token is opaque to the client: persist and resend it, never decode it
/// or recompute the digest. `balance_cny` is the six-decimal source of truth
/// for the calibration target comparison.
class BalanceBasis {
  const BalanceBasis({
    required this.accountId,
    required this.effectiveOn,
    required this.balanceCny,
    required this.basisVersion,
    required this.basisToken,
    required this.ttlSeconds,
    this.expiresAt,
    this.serverVersion,
  });

  final String accountId;
  final String effectiveOn;
  final String balanceCny;
  final int basisVersion;
  final String basisToken;
  final int ttlSeconds;
  final String? expiresAt;
  final int? serverVersion;

  factory BalanceBasis.fromJson(Map<String, Object?> json) => BalanceBasis(
        accountId: json['account_id']! as String,
        effectiveOn: json['effective_on']! as String,
        balanceCny: json['balance_cny']?.toString() ?? '',
        basisVersion: (json['basis_version'] as num?)?.toInt() ?? 1,
        basisToken: json['basis_token']! as String,
        ttlSeconds: (json['ttl_seconds'] as num?)?.toInt() ?? 600,
        expiresAt: json['expires_at'] as String?,
        serverVersion: (json['server_version'] as num?)?.toInt(),
      );
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
      this.error,
      this.upgradeRequiredProtocol,
      this.upgradeRequiredWithoutVersion = false});

  final int serverVersion;
  final String? lastSyncedAt;
  final bool isSyncing;
  final String? error;

  /// Set when the server answers 426 `upgrade_required` and named a floor.
  /// Automatic sync stays gated until the app satisfies it or the user taps
  /// the explicit retry entry. Never fabricated when the server omitted it.
  final int? upgradeRequiredProtocol;

  /// A 426 arrived without a parseable `min_protocol`. The requirement is real
  /// but its version is unknown, so the gate stays closed rather than silently
  /// opening. Kept separate from [upgradeRequiredProtocol] so a missing version
  /// is never rendered as `vnull` and never mistaken for "no gate".
  final bool upgradeRequiredWithoutVersion;

  bool get needsUpgrade =>
      upgradeRequiredProtocol != null || upgradeRequiredWithoutVersion;

  /// Whether this build (at [supportedProtocol]) is still below what the
  /// server demanded. A persisted requirement at or below the local capability
  /// is stale and must not block a retry after an app upgrade. An unknown
  /// requirement can never be proven satisfied, so it keeps the gate closed.
  bool requiresUpgrade(int supportedProtocol) {
    if (upgradeRequiredWithoutVersion) return true;
    final required = upgradeRequiredProtocol;
    return required != null && required > supportedProtocol;
  }

  /// User-facing requirement text. Never renders a missing version.
  String get upgradeRequirementLabel => upgradeRequiredProtocol == null
      ? '服务端要求更高协议版本（未提供具体版本）'
      : '服务端要求协议 v$upgradeRequiredProtocol 或更高';

  SyncState copyWith(
          {int? serverVersion,
          String? lastSyncedAt,
          bool? isSyncing,
          String? error,
          int? upgradeRequiredProtocol,
          bool? upgradeRequiredWithoutVersion,
          bool clearUpgradeRequired = false}) =>
      SyncState(
        serverVersion: serverVersion ?? this.serverVersion,
        lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
        isSyncing: isSyncing ?? this.isSyncing,
        error: error,
        upgradeRequiredProtocol:
            clearUpgradeRequired || upgradeRequiredWithoutVersion == true
                ? null
                : upgradeRequiredProtocol ?? this.upgradeRequiredProtocol,
        upgradeRequiredWithoutVersion: clearUpgradeRequired
            ? false
            : upgradeRequiredWithoutVersion ??
                (upgradeRequiredProtocol != null
                    ? false
                    : this.upgradeRequiredWithoutVersion),
      );
}

/// A durable, user-facing record of one server-rejected sync operation.
///
/// Rejections never become retry loops: the operation leaves the queue and the
/// local optimistic change is rolled back, while this issue stays readable and
/// survives restarts.
class SyncIssue {
  const SyncIssue({
    required this.clientOpId,
    required this.entity,
    required this.entityId,
    required this.code,
    this.detail = '',
    this.field,
    this.createdAt = '',
  });

  final String clientOpId;
  final String entity;
  final String entityId;
  final String code;
  final String detail;
  final String? field;
  final String createdAt;

  String get entityLabel => switch (entity) {
        'accounts' => '账户',
        'categories' => '分类',
        'transactions' => '账目',
        'budgets' => '预算',
        'user_preferences' => '默认账户',
        _ => '数据',
      };

  String get userMessage {
    final label = entityLabel;
    return switch (code) {
      'financial_conflict' || 'base_field_missing' => '$label的财务字段已变化，修改未生效',
      'read_only_field' => '该字段由系统维护，修改已跳过',
      'duplicate_key' => '$label名称或唯一字段重复，修改未生效',
      'dependency_rejected' => '依赖的数据未同步，$label修改已跳过',
      'invalid_reference' || 'inactive_reference' => '$label引用的数据不可用，已跳过',
      'invalid_default_account' => '默认账户不可用，已跳过',
      'version_conflict' => '数据已在其他设备更新，已采用服务器版本',
      'balance_changed' => '账目已变化，请重新核对校准',
      'conversion_pending' => '账户存在待换算账目，请先补充汇率',
      'not_found' || 'forbidden' || 'entity_deleted' => '$label已不存在或无权访问，已跳过',
      'immutable_adjustment' => '余额校准流水不可修改',
      'operation_mismatch' => '同步操作重复，已跳过',
      'unsupported_entity' || 'unsupported_field' => '$label包含不支持的字段，已跳过',
      'invalid_field' ||
      'invalid_amount' ||
      'invalid_base' ||
      'invalid_base_version' ||
      'identity_mismatch' =>
        '$label数据不合法，已跳过',
      _ => '$label修改未生效（$code）',
    };
  }

  Map<String, Object?> toJson() => {
        'client_op_id': clientOpId,
        'entity': entity,
        'entity_id': entityId,
        'code': code,
        'detail': detail,
        'field': field,
        'created_at': createdAt,
      };

  factory SyncIssue.fromJson(Map<String, Object?> json) => SyncIssue(
        clientOpId: json['client_op_id'] as String? ?? '',
        entity: json['entity'] as String? ?? '',
        entityId: json['entity_id'] as String? ?? '',
        code: json['code'] as String? ?? 'validation_error',
        detail: json['detail'] as String? ?? '',
        field: json['field'] as String?,
        createdAt: json['created_at'] as String? ?? '',
      );
}

/// The authoritative per-user singleton preference row (`id = self`).
///
/// `null` in [FinanceState.preference] means "not established yet"; an empty
/// `preferences` array in a pull response must not be read as "cleared".
class UserPreference {
  const UserPreference({
    this.defaultAccountId,
    this.serverVersion,
    this.updatedAt,
  });

  static const singletonId = 'self';

  final String? defaultAccountId;
  final int? serverVersion;
  final String? updatedAt;

  UserPreference copyWith({
    String? defaultAccountId,
    bool clearDefaultAccount = false,
    int? serverVersion,
    String? updatedAt,
  }) =>
      UserPreference(
        defaultAccountId: clearDefaultAccount
            ? null
            : defaultAccountId ?? this.defaultAccountId,
        serverVersion: serverVersion ?? this.serverVersion,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  Map<String, Object?> toJson() => {
        'id': singletonId,
        'default_account_id': defaultAccountId,
        'server_version': serverVersion,
        'updated_at': updatedAt,
      };

  factory UserPreference.fromJson(Map<String, Object?> json) => UserPreference(
        defaultAccountId: json['default_account_id'] as String?,
        serverVersion: (json['server_version'] as num?)?.toInt(),
        updatedAt: json['updated_at'] as String?,
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
    // Constructor-built states are current. Persisted states written before
    // 1.1.0 have no marker and read as 1, which forces one full pull so that
    // adjustments skipped by the legacy cursor are not lost.
    this.financialSchemaVersion = 3,
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
    this.calibrationDrafts = const <CalibrationDraft>[],
    this.syncIssues = const <SyncIssue>[],
    this.preference,
    this.defaultAccountId,
    this.syncState = const SyncState(),
  });

  final int schemaVersion;
  final int financialSchemaVersion;
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
  final List<CalibrationDraft> calibrationDrafts;
  final List<SyncIssue> syncIssues;
  final UserPreference? preference;
  final String? defaultAccountId;
  final SyncState syncState;

  CalibrationDraft? calibrationDraftFor(String accountId) => calibrationDrafts
      .where((draft) => draft.accountId == accountId)
      .firstOrNull;

  FinanceState copyWith({
    int? schemaVersion,
    int? financialSchemaVersion,
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
    List<CalibrationDraft>? calibrationDrafts,
    List<SyncIssue>? syncIssues,
    UserPreference? preference,
    bool clearPreference = false,
    String? defaultAccountId,
    bool clearDefaultAccountId = false,
    SyncState? syncState,
  }) {
    return FinanceState(
      schemaVersion: schemaVersion ?? this.schemaVersion,
      financialSchemaVersion:
          financialSchemaVersion ?? this.financialSchemaVersion,
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
      calibrationDrafts: calibrationDrafts ?? this.calibrationDrafts,
      syncIssues: syncIssues ?? this.syncIssues,
      preference: clearPreference ? null : preference ?? this.preference,
      defaultAccountId: clearDefaultAccountId
          ? null
          : defaultAccountId ?? this.defaultAccountId,
      syncState: syncState ?? this.syncState,
    );
  }

  Map<String, Object?> toJson() => {
        'schema_version': schemaVersion,
        'financial_schema_version': financialSchemaVersion,
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
        'calibration_drafts':
            calibrationDrafts.map((item) => item.toJson()).toList(),
        'sync_issues': syncIssues.map((item) => item.toJson()).toList(),
        'preference': preference?.toJson(),
        'default_account_id': defaultAccountId,
        'sync_state': {
          'server_version': syncState.serverVersion,
          if (syncState.lastSyncedAt != null)
            'last_synced_at': syncState.lastSyncedAt,
          if (syncState.upgradeRequiredProtocol != null)
            'upgrade_required_protocol': syncState.upgradeRequiredProtocol,
          if (syncState.upgradeRequiredWithoutVersion)
            'upgrade_required_without_version': true,
        },
      };

  static int _serverVersionFromJson(Object? value) {
    if (value is! Map) return 0;
    final serverVersion = value['server_version'];
    return serverVersion is num ? serverVersion.toInt() : 0;
  }

  factory FinanceState.fromJson(Map<String, Object?> json) => FinanceState(
        schemaVersion: (json['schema_version'] as num?)?.toInt() ?? 1,
        financialSchemaVersion:
            (json['financial_schema_version'] as num?)?.toInt() ?? 1,
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
        calibrationDrafts: ((json['calibration_drafts'] as List<Object?>?) ??
                const <Object?>[])
            .map((item) => CalibrationDraft.fromJson(
                (item! as Map).cast<String, Object?>()))
            .toList(),
        syncIssues:
            ((json['sync_issues'] as List<Object?>?) ?? const <Object?>[])
                .map((item) =>
                    SyncIssue.fromJson((item! as Map).cast<String, Object?>()))
                .toList(),
        preference: json['preference'] is Map
            ? UserPreference.fromJson(
                (json['preference']! as Map).cast<String, Object?>())
            : null,
        defaultAccountId: json['default_account_id'] as String?,
        syncState: SyncState(
            serverVersion: _serverVersionFromJson(json['sync_state']),
            lastSyncedAt: json['sync_state'] is Map
                ? (json['sync_state'] as Map)['last_synced_at'] as String?
                : null,
            upgradeRequiredProtocol: json['sync_state'] is Map
                ? ((json['sync_state'] as Map)['upgrade_required_protocol']
                        as num?)
                    ?.toInt()
                : null,
            upgradeRequiredWithoutVersion: json['sync_state'] is Map &&
                (json['sync_state']
                        as Map)['upgrade_required_without_version'] ==
                    true),
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
      lower < upper || (lower == upper && lowerInclusive && upperInclusive);

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
      amountRange: clearAmountRange ? null : amountRange ?? this.amountRange,
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
  const AccountBalance({
    required this.account,
    required this.balance,
    this.isPending = false,
    this.pendingConversionCount = 0,
  });

  final Account account;

  /// Known CNY book value. When [isPending] is true this is only the partial
  /// sum of the entries that do have a frozen CNY snapshot; it must never be
  /// presented as the account's actual balance.
  final double balance;

  /// True when the opening amount or any related entry still lacks a usable
  /// CNY snapshot. The UI shows 「待换算」 instead of [balance] in that case:
  /// an unknown conversion is not the same thing as zero.
  final bool isPending;

  /// How many opening/transaction snapshots are missing for this account.
  final int pendingConversionCount;
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

  /// Totals are complete only while [hasPendingBalances] is false. Otherwise
  /// they are the partial sum of the accounts that do have a frozen snapshot,
  /// and the UI must label them as pending rather than show them as complete.
  final double assetTotal;
  final double liabilityTotal;
  final double netWorth;
  final List<BudgetProgress> budgetProgress;
  final int pendingConversionCount;

  /// Number of active accounts whose opening/entries still lack a CNY
  /// snapshot. A balance that is unknown is never reported as zero.
  int get pendingAccountCount =>
      accountBalances.where((item) => item.isPending).length;

  bool get hasPendingBalances => pendingAccountCount > 0;

  /// Backward-compatible alias for consumers that used the original name.
  double get liabilities => liabilityTotal;
}

/// One account row of the V2 `/wealth` response.
///
/// `cny_balance` is null when any entry lacks a usable CNY snapshot. It is a
/// genuine unknown, never zero: `displayBalance` keeps that distinction.
class WealthAccountView {
  const WealthAccountView({
    required this.id,
    required this.name,
    required this.type,
    required this.currency,
    required this.cnyBalance,
    required this.cnyBalanceExact,
    required this.conversionStatus,
    this.pendingConversionCount = 0,
  });

  final String id;
  final String name;
  final AccountType type;
  final String currency;
  final double? cnyBalance;
  final String? cnyBalanceExact;
  final String conversionStatus;
  final int pendingConversionCount;

  bool get isPending =>
      cnyBalance == null ||
      cnyBalanceExact == null ||
      conversionStatus == 'pending';

  String get displayBalance =>
      isPending ? '待换算' : (cnyBalanceExact ?? cnyBalance!.toStringAsFixed(2));

  factory WealthAccountView.fromJson(Map<String, Object?> json) =>
      WealthAccountView(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? '',
        type: accountTypeFromJson(json['type'] ?? json['kind']),
        currency: json['currency'] as String? ?? 'CNY',
        cnyBalance: _jsonDouble(json['cny_balance']),
        cnyBalanceExact: json['cny_balance_exact'] as String?,
        conversionStatus: json['conversion_status'] as String? ?? 'ready',
        pendingConversionCount:
            (json['pending_conversion_count'] as num?)?.toInt() ?? 0,
      );
}

/// V2 wealth snapshot as of an explicit business date.
///
/// Totals are null when any account is pending conversion. The `known_*`
/// values are partial sums and must not be shown as if they were complete.
class WealthView {
  const WealthView({
    this.asOfDate,
    this.excludesLaterAdjustments = false,
    this.valuationMode,
    this.totalAssets,
    this.totalLiabilities,
    this.netWorth,
    this.knownTotalAssets,
    this.knownTotalLiabilities,
    this.pendingConversionCount = 0,
    this.accounts = const <WealthAccountView>[],
    this.serverVersion = 0,
  });

  final String? asOfDate;
  final bool excludesLaterAdjustments;
  final String? valuationMode;
  final double? totalAssets;
  final double? totalLiabilities;
  final double? netWorth;
  final double? knownTotalAssets;
  final double? knownTotalLiabilities;
  final int pendingConversionCount;
  final List<WealthAccountView> accounts;
  final int serverVersion;

  bool get hasPending => netWorth == null || pendingConversionCount > 0;

  /// Totals are intentionally null while pending; callers must not coerce
  /// them to zero.
  String get netWorthDisplay =>
      netWorth == null ? '待换算' : netWorth!.toStringAsFixed(2);

  factory WealthView.fromJson(Map<String, Object?> json) => WealthView(
        asOfDate: json['as_of_date'] as String?,
        excludesLaterAdjustments: json['excludes_later_adjustments'] == true,
        valuationMode: json['valuation_mode'] as String?,
        totalAssets: _jsonDouble(json['total_assets']),
        totalLiabilities: _jsonDouble(json['total_liabilities']),
        netWorth: _jsonDouble(json['net_worth']),
        knownTotalAssets: _jsonDouble(json['known_total_assets']),
        knownTotalLiabilities: _jsonDouble(json['known_total_liabilities']),
        pendingConversionCount:
            (json['pending_conversion_count'] as num?)?.toInt() ?? 0,
        accounts: ((json['accounts'] as List<Object?>?) ?? const [])
            .whereType<Map>()
            .map((item) =>
                WealthAccountView.fromJson(item.cast<String, Object?>()))
            .toList(growable: false),
        serverVersion: (json['server_version'] as num?)?.toInt() ?? 0,
      );
}
