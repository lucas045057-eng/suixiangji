// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'drift_database.dart';

// ignore_for_file: type=lint
class $LocalAccountsTable extends LocalAccounts
    with TableInfo<$LocalAccountsTable, LocalAccount> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LocalAccountsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
      'name', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _typeMeta = const VerificationMeta('type');
  @override
  late final GeneratedColumn<String> type = GeneratedColumn<String>(
      'type', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _accountKindMeta =
      const VerificationMeta('accountKind');
  @override
  late final GeneratedColumn<String> accountKind = GeneratedColumn<String>(
      'account_kind', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant('other'));
  static const VerificationMeta _currencyMeta =
      const VerificationMeta('currency');
  @override
  late final GeneratedColumn<String> currency = GeneratedColumn<String>(
      'currency', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant('CNY'));
  static const VerificationMeta _openingBalanceMeta =
      const VerificationMeta('openingBalance');
  @override
  late final GeneratedColumn<double> openingBalance = GeneratedColumn<double>(
      'opening_balance', aliasedName, false,
      type: DriftSqlType.double,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _openingCnyAmountMeta =
      const VerificationMeta('openingCnyAmount');
  @override
  late final GeneratedColumn<double> openingCnyAmount = GeneratedColumn<double>(
      'opening_cny_amount', aliasedName, true,
      type: DriftSqlType.double, requiredDuringInsert: false);
  static const VerificationMeta _exchangeRateDateMeta =
      const VerificationMeta('exchangeRateDate');
  @override
  late final GeneratedColumn<String> exchangeRateDate = GeneratedColumn<String>(
      'exchange_rate_date', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _exchangeRateSourceMeta =
      const VerificationMeta('exchangeRateSource');
  @override
  late final GeneratedColumn<String> exchangeRateSource =
      GeneratedColumn<String>('exchange_rate_source', aliasedName, true,
          type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _isLiquidMeta =
      const VerificationMeta('isLiquid');
  @override
  late final GeneratedColumn<bool> isLiquid = GeneratedColumn<bool>(
      'is_liquid', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("is_liquid" IN (0, 1))'),
      defaultValue: const Constant(false));
  static const VerificationMeta _isDefaultPaymentMeta =
      const VerificationMeta('isDefaultPayment');
  @override
  late final GeneratedColumn<bool> isDefaultPayment = GeneratedColumn<bool>(
      'is_default_payment', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints: GeneratedColumn.constraintIsAlways(
          'CHECK ("is_default_payment" IN (0, 1))'),
      defaultValue: const Constant(false));
  static const VerificationMeta _deletedAtMeta =
      const VerificationMeta('deletedAt');
  @override
  late final GeneratedColumn<String> deletedAt = GeneratedColumn<String>(
      'deleted_at', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _serverVersionMeta =
      const VerificationMeta('serverVersion');
  @override
  late final GeneratedColumn<int> serverVersion = GeneratedColumn<int>(
      'server_version', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _updatedAtMeta =
      const VerificationMeta('updatedAt');
  @override
  late final GeneratedColumn<String> updatedAt = GeneratedColumn<String>(
      'updated_at', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  @override
  List<GeneratedColumn> get $columns => [
        id,
        name,
        type,
        accountKind,
        currency,
        openingBalance,
        openingCnyAmount,
        exchangeRateDate,
        exchangeRateSource,
        isLiquid,
        isDefaultPayment,
        deletedAt,
        serverVersion,
        updatedAt
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'local_accounts';
  @override
  VerificationContext validateIntegrity(Insertable<LocalAccount> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
          _nameMeta, name.isAcceptableOrUnknown(data['name']!, _nameMeta));
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('type')) {
      context.handle(
          _typeMeta, type.isAcceptableOrUnknown(data['type']!, _typeMeta));
    } else if (isInserting) {
      context.missing(_typeMeta);
    }
    if (data.containsKey('account_kind')) {
      context.handle(
          _accountKindMeta,
          accountKind.isAcceptableOrUnknown(
              data['account_kind']!, _accountKindMeta));
    }
    if (data.containsKey('currency')) {
      context.handle(_currencyMeta,
          currency.isAcceptableOrUnknown(data['currency']!, _currencyMeta));
    }
    if (data.containsKey('opening_balance')) {
      context.handle(
          _openingBalanceMeta,
          openingBalance.isAcceptableOrUnknown(
              data['opening_balance']!, _openingBalanceMeta));
    }
    if (data.containsKey('opening_cny_amount')) {
      context.handle(
          _openingCnyAmountMeta,
          openingCnyAmount.isAcceptableOrUnknown(
              data['opening_cny_amount']!, _openingCnyAmountMeta));
    }
    if (data.containsKey('exchange_rate_date')) {
      context.handle(
          _exchangeRateDateMeta,
          exchangeRateDate.isAcceptableOrUnknown(
              data['exchange_rate_date']!, _exchangeRateDateMeta));
    }
    if (data.containsKey('exchange_rate_source')) {
      context.handle(
          _exchangeRateSourceMeta,
          exchangeRateSource.isAcceptableOrUnknown(
              data['exchange_rate_source']!, _exchangeRateSourceMeta));
    }
    if (data.containsKey('is_liquid')) {
      context.handle(_isLiquidMeta,
          isLiquid.isAcceptableOrUnknown(data['is_liquid']!, _isLiquidMeta));
    }
    if (data.containsKey('is_default_payment')) {
      context.handle(
          _isDefaultPaymentMeta,
          isDefaultPayment.isAcceptableOrUnknown(
              data['is_default_payment']!, _isDefaultPaymentMeta));
    }
    if (data.containsKey('deleted_at')) {
      context.handle(_deletedAtMeta,
          deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta));
    }
    if (data.containsKey('server_version')) {
      context.handle(
          _serverVersionMeta,
          serverVersion.isAcceptableOrUnknown(
              data['server_version']!, _serverVersionMeta));
    }
    if (data.containsKey('updated_at')) {
      context.handle(_updatedAtMeta,
          updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  LocalAccount map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LocalAccount(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      name: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}name'])!,
      type: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}type'])!,
      accountKind: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}account_kind'])!,
      currency: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}currency'])!,
      openingBalance: attachedDatabase.typeMapping.read(
          DriftSqlType.double, data['${effectivePrefix}opening_balance'])!,
      openingCnyAmount: attachedDatabase.typeMapping.read(
          DriftSqlType.double, data['${effectivePrefix}opening_cny_amount']),
      exchangeRateDate: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}exchange_rate_date']),
      exchangeRateSource: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}exchange_rate_source']),
      isLiquid: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}is_liquid'])!,
      isDefaultPayment: attachedDatabase.typeMapping.read(
          DriftSqlType.bool, data['${effectivePrefix}is_default_payment'])!,
      deletedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}deleted_at']),
      serverVersion: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}server_version'])!,
      updatedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}updated_at']),
    );
  }

  @override
  $LocalAccountsTable createAlias(String alias) {
    return $LocalAccountsTable(attachedDatabase, alias);
  }
}

class LocalAccount extends DataClass implements Insertable<LocalAccount> {
  final String id;
  final String name;
  final String type;
  final String accountKind;
  final String currency;
  final double openingBalance;
  final double? openingCnyAmount;
  final String? exchangeRateDate;
  final String? exchangeRateSource;
  final bool isLiquid;
  final bool isDefaultPayment;
  final String? deletedAt;
  final int serverVersion;
  final String? updatedAt;
  const LocalAccount(
      {required this.id,
      required this.name,
      required this.type,
      required this.accountKind,
      required this.currency,
      required this.openingBalance,
      this.openingCnyAmount,
      this.exchangeRateDate,
      this.exchangeRateSource,
      required this.isLiquid,
      required this.isDefaultPayment,
      this.deletedAt,
      required this.serverVersion,
      this.updatedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    map['type'] = Variable<String>(type);
    map['account_kind'] = Variable<String>(accountKind);
    map['currency'] = Variable<String>(currency);
    map['opening_balance'] = Variable<double>(openingBalance);
    if (!nullToAbsent || openingCnyAmount != null) {
      map['opening_cny_amount'] = Variable<double>(openingCnyAmount);
    }
    if (!nullToAbsent || exchangeRateDate != null) {
      map['exchange_rate_date'] = Variable<String>(exchangeRateDate);
    }
    if (!nullToAbsent || exchangeRateSource != null) {
      map['exchange_rate_source'] = Variable<String>(exchangeRateSource);
    }
    map['is_liquid'] = Variable<bool>(isLiquid);
    map['is_default_payment'] = Variable<bool>(isDefaultPayment);
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<String>(deletedAt);
    }
    map['server_version'] = Variable<int>(serverVersion);
    if (!nullToAbsent || updatedAt != null) {
      map['updated_at'] = Variable<String>(updatedAt);
    }
    return map;
  }

  LocalAccountsCompanion toCompanion(bool nullToAbsent) {
    return LocalAccountsCompanion(
      id: Value(id),
      name: Value(name),
      type: Value(type),
      accountKind: Value(accountKind),
      currency: Value(currency),
      openingBalance: Value(openingBalance),
      openingCnyAmount: openingCnyAmount == null && nullToAbsent
          ? const Value.absent()
          : Value(openingCnyAmount),
      exchangeRateDate: exchangeRateDate == null && nullToAbsent
          ? const Value.absent()
          : Value(exchangeRateDate),
      exchangeRateSource: exchangeRateSource == null && nullToAbsent
          ? const Value.absent()
          : Value(exchangeRateSource),
      isLiquid: Value(isLiquid),
      isDefaultPayment: Value(isDefaultPayment),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
      serverVersion: Value(serverVersion),
      updatedAt: updatedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(updatedAt),
    );
  }

  factory LocalAccount.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LocalAccount(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      type: serializer.fromJson<String>(json['type']),
      accountKind: serializer.fromJson<String>(json['accountKind']),
      currency: serializer.fromJson<String>(json['currency']),
      openingBalance: serializer.fromJson<double>(json['openingBalance']),
      openingCnyAmount: serializer.fromJson<double?>(json['openingCnyAmount']),
      exchangeRateDate: serializer.fromJson<String?>(json['exchangeRateDate']),
      exchangeRateSource:
          serializer.fromJson<String?>(json['exchangeRateSource']),
      isLiquid: serializer.fromJson<bool>(json['isLiquid']),
      isDefaultPayment: serializer.fromJson<bool>(json['isDefaultPayment']),
      deletedAt: serializer.fromJson<String?>(json['deletedAt']),
      serverVersion: serializer.fromJson<int>(json['serverVersion']),
      updatedAt: serializer.fromJson<String?>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'type': serializer.toJson<String>(type),
      'accountKind': serializer.toJson<String>(accountKind),
      'currency': serializer.toJson<String>(currency),
      'openingBalance': serializer.toJson<double>(openingBalance),
      'openingCnyAmount': serializer.toJson<double?>(openingCnyAmount),
      'exchangeRateDate': serializer.toJson<String?>(exchangeRateDate),
      'exchangeRateSource': serializer.toJson<String?>(exchangeRateSource),
      'isLiquid': serializer.toJson<bool>(isLiquid),
      'isDefaultPayment': serializer.toJson<bool>(isDefaultPayment),
      'deletedAt': serializer.toJson<String?>(deletedAt),
      'serverVersion': serializer.toJson<int>(serverVersion),
      'updatedAt': serializer.toJson<String?>(updatedAt),
    };
  }

  LocalAccount copyWith(
          {String? id,
          String? name,
          String? type,
          String? accountKind,
          String? currency,
          double? openingBalance,
          Value<double?> openingCnyAmount = const Value.absent(),
          Value<String?> exchangeRateDate = const Value.absent(),
          Value<String?> exchangeRateSource = const Value.absent(),
          bool? isLiquid,
          bool? isDefaultPayment,
          Value<String?> deletedAt = const Value.absent(),
          int? serverVersion,
          Value<String?> updatedAt = const Value.absent()}) =>
      LocalAccount(
        id: id ?? this.id,
        name: name ?? this.name,
        type: type ?? this.type,
        accountKind: accountKind ?? this.accountKind,
        currency: currency ?? this.currency,
        openingBalance: openingBalance ?? this.openingBalance,
        openingCnyAmount: openingCnyAmount.present
            ? openingCnyAmount.value
            : this.openingCnyAmount,
        exchangeRateDate: exchangeRateDate.present
            ? exchangeRateDate.value
            : this.exchangeRateDate,
        exchangeRateSource: exchangeRateSource.present
            ? exchangeRateSource.value
            : this.exchangeRateSource,
        isLiquid: isLiquid ?? this.isLiquid,
        isDefaultPayment: isDefaultPayment ?? this.isDefaultPayment,
        deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
        serverVersion: serverVersion ?? this.serverVersion,
        updatedAt: updatedAt.present ? updatedAt.value : this.updatedAt,
      );
  LocalAccount copyWithCompanion(LocalAccountsCompanion data) {
    return LocalAccount(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      type: data.type.present ? data.type.value : this.type,
      accountKind:
          data.accountKind.present ? data.accountKind.value : this.accountKind,
      currency: data.currency.present ? data.currency.value : this.currency,
      openingBalance: data.openingBalance.present
          ? data.openingBalance.value
          : this.openingBalance,
      openingCnyAmount: data.openingCnyAmount.present
          ? data.openingCnyAmount.value
          : this.openingCnyAmount,
      exchangeRateDate: data.exchangeRateDate.present
          ? data.exchangeRateDate.value
          : this.exchangeRateDate,
      exchangeRateSource: data.exchangeRateSource.present
          ? data.exchangeRateSource.value
          : this.exchangeRateSource,
      isLiquid: data.isLiquid.present ? data.isLiquid.value : this.isLiquid,
      isDefaultPayment: data.isDefaultPayment.present
          ? data.isDefaultPayment.value
          : this.isDefaultPayment,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
      serverVersion: data.serverVersion.present
          ? data.serverVersion.value
          : this.serverVersion,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LocalAccount(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('type: $type, ')
          ..write('accountKind: $accountKind, ')
          ..write('currency: $currency, ')
          ..write('openingBalance: $openingBalance, ')
          ..write('openingCnyAmount: $openingCnyAmount, ')
          ..write('exchangeRateDate: $exchangeRateDate, ')
          ..write('exchangeRateSource: $exchangeRateSource, ')
          ..write('isLiquid: $isLiquid, ')
          ..write('isDefaultPayment: $isDefaultPayment, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('serverVersion: $serverVersion, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
      id,
      name,
      type,
      accountKind,
      currency,
      openingBalance,
      openingCnyAmount,
      exchangeRateDate,
      exchangeRateSource,
      isLiquid,
      isDefaultPayment,
      deletedAt,
      serverVersion,
      updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LocalAccount &&
          other.id == this.id &&
          other.name == this.name &&
          other.type == this.type &&
          other.accountKind == this.accountKind &&
          other.currency == this.currency &&
          other.openingBalance == this.openingBalance &&
          other.openingCnyAmount == this.openingCnyAmount &&
          other.exchangeRateDate == this.exchangeRateDate &&
          other.exchangeRateSource == this.exchangeRateSource &&
          other.isLiquid == this.isLiquid &&
          other.isDefaultPayment == this.isDefaultPayment &&
          other.deletedAt == this.deletedAt &&
          other.serverVersion == this.serverVersion &&
          other.updatedAt == this.updatedAt);
}

class LocalAccountsCompanion extends UpdateCompanion<LocalAccount> {
  final Value<String> id;
  final Value<String> name;
  final Value<String> type;
  final Value<String> accountKind;
  final Value<String> currency;
  final Value<double> openingBalance;
  final Value<double?> openingCnyAmount;
  final Value<String?> exchangeRateDate;
  final Value<String?> exchangeRateSource;
  final Value<bool> isLiquid;
  final Value<bool> isDefaultPayment;
  final Value<String?> deletedAt;
  final Value<int> serverVersion;
  final Value<String?> updatedAt;
  final Value<int> rowid;
  const LocalAccountsCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.type = const Value.absent(),
    this.accountKind = const Value.absent(),
    this.currency = const Value.absent(),
    this.openingBalance = const Value.absent(),
    this.openingCnyAmount = const Value.absent(),
    this.exchangeRateDate = const Value.absent(),
    this.exchangeRateSource = const Value.absent(),
    this.isLiquid = const Value.absent(),
    this.isDefaultPayment = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.serverVersion = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  LocalAccountsCompanion.insert({
    required String id,
    required String name,
    required String type,
    this.accountKind = const Value.absent(),
    this.currency = const Value.absent(),
    this.openingBalance = const Value.absent(),
    this.openingCnyAmount = const Value.absent(),
    this.exchangeRateDate = const Value.absent(),
    this.exchangeRateSource = const Value.absent(),
    this.isLiquid = const Value.absent(),
    this.isDefaultPayment = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.serverVersion = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        name = Value(name),
        type = Value(type);
  static Insertable<LocalAccount> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<String>? type,
    Expression<String>? accountKind,
    Expression<String>? currency,
    Expression<double>? openingBalance,
    Expression<double>? openingCnyAmount,
    Expression<String>? exchangeRateDate,
    Expression<String>? exchangeRateSource,
    Expression<bool>? isLiquid,
    Expression<bool>? isDefaultPayment,
    Expression<String>? deletedAt,
    Expression<int>? serverVersion,
    Expression<String>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (type != null) 'type': type,
      if (accountKind != null) 'account_kind': accountKind,
      if (currency != null) 'currency': currency,
      if (openingBalance != null) 'opening_balance': openingBalance,
      if (openingCnyAmount != null) 'opening_cny_amount': openingCnyAmount,
      if (exchangeRateDate != null) 'exchange_rate_date': exchangeRateDate,
      if (exchangeRateSource != null)
        'exchange_rate_source': exchangeRateSource,
      if (isLiquid != null) 'is_liquid': isLiquid,
      if (isDefaultPayment != null) 'is_default_payment': isDefaultPayment,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (serverVersion != null) 'server_version': serverVersion,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  LocalAccountsCompanion copyWith(
      {Value<String>? id,
      Value<String>? name,
      Value<String>? type,
      Value<String>? accountKind,
      Value<String>? currency,
      Value<double>? openingBalance,
      Value<double?>? openingCnyAmount,
      Value<String?>? exchangeRateDate,
      Value<String?>? exchangeRateSource,
      Value<bool>? isLiquid,
      Value<bool>? isDefaultPayment,
      Value<String?>? deletedAt,
      Value<int>? serverVersion,
      Value<String?>? updatedAt,
      Value<int>? rowid}) {
    return LocalAccountsCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      type: type ?? this.type,
      accountKind: accountKind ?? this.accountKind,
      currency: currency ?? this.currency,
      openingBalance: openingBalance ?? this.openingBalance,
      openingCnyAmount: openingCnyAmount ?? this.openingCnyAmount,
      exchangeRateDate: exchangeRateDate ?? this.exchangeRateDate,
      exchangeRateSource: exchangeRateSource ?? this.exchangeRateSource,
      isLiquid: isLiquid ?? this.isLiquid,
      isDefaultPayment: isDefaultPayment ?? this.isDefaultPayment,
      deletedAt: deletedAt ?? this.deletedAt,
      serverVersion: serverVersion ?? this.serverVersion,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (type.present) {
      map['type'] = Variable<String>(type.value);
    }
    if (accountKind.present) {
      map['account_kind'] = Variable<String>(accountKind.value);
    }
    if (currency.present) {
      map['currency'] = Variable<String>(currency.value);
    }
    if (openingBalance.present) {
      map['opening_balance'] = Variable<double>(openingBalance.value);
    }
    if (openingCnyAmount.present) {
      map['opening_cny_amount'] = Variable<double>(openingCnyAmount.value);
    }
    if (exchangeRateDate.present) {
      map['exchange_rate_date'] = Variable<String>(exchangeRateDate.value);
    }
    if (exchangeRateSource.present) {
      map['exchange_rate_source'] = Variable<String>(exchangeRateSource.value);
    }
    if (isLiquid.present) {
      map['is_liquid'] = Variable<bool>(isLiquid.value);
    }
    if (isDefaultPayment.present) {
      map['is_default_payment'] = Variable<bool>(isDefaultPayment.value);
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<String>(deletedAt.value);
    }
    if (serverVersion.present) {
      map['server_version'] = Variable<int>(serverVersion.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<String>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LocalAccountsCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('type: $type, ')
          ..write('accountKind: $accountKind, ')
          ..write('currency: $currency, ')
          ..write('openingBalance: $openingBalance, ')
          ..write('openingCnyAmount: $openingCnyAmount, ')
          ..write('exchangeRateDate: $exchangeRateDate, ')
          ..write('exchangeRateSource: $exchangeRateSource, ')
          ..write('isLiquid: $isLiquid, ')
          ..write('isDefaultPayment: $isDefaultPayment, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('serverVersion: $serverVersion, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $LocalTransactionsTable extends LocalTransactions
    with TableInfo<$LocalTransactionsTable, LocalTransaction> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LocalTransactionsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _dateMeta = const VerificationMeta('date');
  @override
  late final GeneratedColumn<String> date = GeneratedColumn<String>(
      'date', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _typeMeta = const VerificationMeta('type');
  @override
  late final GeneratedColumn<String> type = GeneratedColumn<String>(
      'type', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _amountMeta = const VerificationMeta('amount');
  @override
  late final GeneratedColumn<double> amount = GeneratedColumn<double>(
      'amount', aliasedName, false,
      type: DriftSqlType.double, requiredDuringInsert: true);
  static const VerificationMeta _currencyMeta =
      const VerificationMeta('currency');
  @override
  late final GeneratedColumn<String> currency = GeneratedColumn<String>(
      'currency', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant('CNY'));
  static const VerificationMeta _cnyAmountMeta =
      const VerificationMeta('cnyAmount');
  @override
  late final GeneratedColumn<double> cnyAmount = GeneratedColumn<double>(
      'cny_amount', aliasedName, true,
      type: DriftSqlType.double, requiredDuringInsert: false);
  static const VerificationMeta _exchangeRateMeta =
      const VerificationMeta('exchangeRate');
  @override
  late final GeneratedColumn<double> exchangeRate = GeneratedColumn<double>(
      'exchange_rate', aliasedName, true,
      type: DriftSqlType.double, requiredDuringInsert: false);
  static const VerificationMeta _exchangeRateDateMeta =
      const VerificationMeta('exchangeRateDate');
  @override
  late final GeneratedColumn<String> exchangeRateDate = GeneratedColumn<String>(
      'exchange_rate_date', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _exchangeRateSourceMeta =
      const VerificationMeta('exchangeRateSource');
  @override
  late final GeneratedColumn<String> exchangeRateSource =
      GeneratedColumn<String>('exchange_rate_source', aliasedName, true,
          type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _conversionStatusMeta =
      const VerificationMeta('conversionStatus');
  @override
  late final GeneratedColumn<String> conversionStatus = GeneratedColumn<String>(
      'conversion_status', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant('ready'));
  static const VerificationMeta _categoryIdMeta =
      const VerificationMeta('categoryId');
  @override
  late final GeneratedColumn<String> categoryId = GeneratedColumn<String>(
      'category_id', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _accountIdMeta =
      const VerificationMeta('accountId');
  @override
  late final GeneratedColumn<String> accountId = GeneratedColumn<String>(
      'account_id', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _fromAccountIdMeta =
      const VerificationMeta('fromAccountId');
  @override
  late final GeneratedColumn<String> fromAccountId = GeneratedColumn<String>(
      'from_account_id', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _toAccountIdMeta =
      const VerificationMeta('toAccountId');
  @override
  late final GeneratedColumn<String> toAccountId = GeneratedColumn<String>(
      'to_account_id', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _occurredAtMeta =
      const VerificationMeta('occurredAt');
  @override
  late final GeneratedColumn<String> occurredAt = GeneratedColumn<String>(
      'occurred_at', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _noteMeta = const VerificationMeta('note');
  @override
  late final GeneratedColumn<String> note = GeneratedColumn<String>(
      'note', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant(''));
  static const VerificationMeta _clientOpIdMeta =
      const VerificationMeta('clientOpId');
  @override
  late final GeneratedColumn<String> clientOpId = GeneratedColumn<String>(
      'client_op_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _deletedAtMeta =
      const VerificationMeta('deletedAt');
  @override
  late final GeneratedColumn<String> deletedAt = GeneratedColumn<String>(
      'deleted_at', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _serverVersionMeta =
      const VerificationMeta('serverVersion');
  @override
  late final GeneratedColumn<int> serverVersion = GeneratedColumn<int>(
      'server_version', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  @override
  List<GeneratedColumn> get $columns => [
        id,
        date,
        type,
        amount,
        currency,
        cnyAmount,
        exchangeRate,
        exchangeRateDate,
        exchangeRateSource,
        conversionStatus,
        categoryId,
        accountId,
        fromAccountId,
        toAccountId,
        occurredAt,
        note,
        clientOpId,
        deletedAt,
        serverVersion
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'local_transactions';
  @override
  VerificationContext validateIntegrity(Insertable<LocalTransaction> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('date')) {
      context.handle(
          _dateMeta, date.isAcceptableOrUnknown(data['date']!, _dateMeta));
    } else if (isInserting) {
      context.missing(_dateMeta);
    }
    if (data.containsKey('type')) {
      context.handle(
          _typeMeta, type.isAcceptableOrUnknown(data['type']!, _typeMeta));
    } else if (isInserting) {
      context.missing(_typeMeta);
    }
    if (data.containsKey('amount')) {
      context.handle(_amountMeta,
          amount.isAcceptableOrUnknown(data['amount']!, _amountMeta));
    } else if (isInserting) {
      context.missing(_amountMeta);
    }
    if (data.containsKey('currency')) {
      context.handle(_currencyMeta,
          currency.isAcceptableOrUnknown(data['currency']!, _currencyMeta));
    }
    if (data.containsKey('cny_amount')) {
      context.handle(_cnyAmountMeta,
          cnyAmount.isAcceptableOrUnknown(data['cny_amount']!, _cnyAmountMeta));
    }
    if (data.containsKey('exchange_rate')) {
      context.handle(
          _exchangeRateMeta,
          exchangeRate.isAcceptableOrUnknown(
              data['exchange_rate']!, _exchangeRateMeta));
    }
    if (data.containsKey('exchange_rate_date')) {
      context.handle(
          _exchangeRateDateMeta,
          exchangeRateDate.isAcceptableOrUnknown(
              data['exchange_rate_date']!, _exchangeRateDateMeta));
    }
    if (data.containsKey('exchange_rate_source')) {
      context.handle(
          _exchangeRateSourceMeta,
          exchangeRateSource.isAcceptableOrUnknown(
              data['exchange_rate_source']!, _exchangeRateSourceMeta));
    }
    if (data.containsKey('conversion_status')) {
      context.handle(
          _conversionStatusMeta,
          conversionStatus.isAcceptableOrUnknown(
              data['conversion_status']!, _conversionStatusMeta));
    }
    if (data.containsKey('category_id')) {
      context.handle(
          _categoryIdMeta,
          categoryId.isAcceptableOrUnknown(
              data['category_id']!, _categoryIdMeta));
    }
    if (data.containsKey('account_id')) {
      context.handle(_accountIdMeta,
          accountId.isAcceptableOrUnknown(data['account_id']!, _accountIdMeta));
    }
    if (data.containsKey('from_account_id')) {
      context.handle(
          _fromAccountIdMeta,
          fromAccountId.isAcceptableOrUnknown(
              data['from_account_id']!, _fromAccountIdMeta));
    }
    if (data.containsKey('to_account_id')) {
      context.handle(
          _toAccountIdMeta,
          toAccountId.isAcceptableOrUnknown(
              data['to_account_id']!, _toAccountIdMeta));
    }
    if (data.containsKey('occurred_at')) {
      context.handle(
          _occurredAtMeta,
          occurredAt.isAcceptableOrUnknown(
              data['occurred_at']!, _occurredAtMeta));
    }
    if (data.containsKey('note')) {
      context.handle(
          _noteMeta, note.isAcceptableOrUnknown(data['note']!, _noteMeta));
    }
    if (data.containsKey('client_op_id')) {
      context.handle(
          _clientOpIdMeta,
          clientOpId.isAcceptableOrUnknown(
              data['client_op_id']!, _clientOpIdMeta));
    } else if (isInserting) {
      context.missing(_clientOpIdMeta);
    }
    if (data.containsKey('deleted_at')) {
      context.handle(_deletedAtMeta,
          deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta));
    }
    if (data.containsKey('server_version')) {
      context.handle(
          _serverVersionMeta,
          serverVersion.isAcceptableOrUnknown(
              data['server_version']!, _serverVersionMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  LocalTransaction map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LocalTransaction(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      date: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}date'])!,
      type: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}type'])!,
      amount: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}amount'])!,
      currency: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}currency'])!,
      cnyAmount: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}cny_amount']),
      exchangeRate: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}exchange_rate']),
      exchangeRateDate: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}exchange_rate_date']),
      exchangeRateSource: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}exchange_rate_source']),
      conversionStatus: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}conversion_status'])!,
      categoryId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}category_id']),
      accountId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}account_id']),
      fromAccountId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}from_account_id']),
      toAccountId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}to_account_id']),
      occurredAt: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}occurred_at']),
      note: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}note'])!,
      clientOpId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}client_op_id'])!,
      deletedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}deleted_at']),
      serverVersion: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}server_version'])!,
    );
  }

  @override
  $LocalTransactionsTable createAlias(String alias) {
    return $LocalTransactionsTable(attachedDatabase, alias);
  }
}

class LocalTransaction extends DataClass
    implements Insertable<LocalTransaction> {
  final String id;
  final String date;
  final String type;
  final double amount;
  final String currency;
  final double? cnyAmount;
  final double? exchangeRate;
  final String? exchangeRateDate;
  final String? exchangeRateSource;
  final String conversionStatus;
  final String? categoryId;
  final String? accountId;
  final String? fromAccountId;
  final String? toAccountId;
  final String? occurredAt;
  final String note;
  final String clientOpId;
  final String? deletedAt;
  final int serverVersion;
  const LocalTransaction(
      {required this.id,
      required this.date,
      required this.type,
      required this.amount,
      required this.currency,
      this.cnyAmount,
      this.exchangeRate,
      this.exchangeRateDate,
      this.exchangeRateSource,
      required this.conversionStatus,
      this.categoryId,
      this.accountId,
      this.fromAccountId,
      this.toAccountId,
      this.occurredAt,
      required this.note,
      required this.clientOpId,
      this.deletedAt,
      required this.serverVersion});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['date'] = Variable<String>(date);
    map['type'] = Variable<String>(type);
    map['amount'] = Variable<double>(amount);
    map['currency'] = Variable<String>(currency);
    if (!nullToAbsent || cnyAmount != null) {
      map['cny_amount'] = Variable<double>(cnyAmount);
    }
    if (!nullToAbsent || exchangeRate != null) {
      map['exchange_rate'] = Variable<double>(exchangeRate);
    }
    if (!nullToAbsent || exchangeRateDate != null) {
      map['exchange_rate_date'] = Variable<String>(exchangeRateDate);
    }
    if (!nullToAbsent || exchangeRateSource != null) {
      map['exchange_rate_source'] = Variable<String>(exchangeRateSource);
    }
    map['conversion_status'] = Variable<String>(conversionStatus);
    if (!nullToAbsent || categoryId != null) {
      map['category_id'] = Variable<String>(categoryId);
    }
    if (!nullToAbsent || accountId != null) {
      map['account_id'] = Variable<String>(accountId);
    }
    if (!nullToAbsent || fromAccountId != null) {
      map['from_account_id'] = Variable<String>(fromAccountId);
    }
    if (!nullToAbsent || toAccountId != null) {
      map['to_account_id'] = Variable<String>(toAccountId);
    }
    if (!nullToAbsent || occurredAt != null) {
      map['occurred_at'] = Variable<String>(occurredAt);
    }
    map['note'] = Variable<String>(note);
    map['client_op_id'] = Variable<String>(clientOpId);
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<String>(deletedAt);
    }
    map['server_version'] = Variable<int>(serverVersion);
    return map;
  }

  LocalTransactionsCompanion toCompanion(bool nullToAbsent) {
    return LocalTransactionsCompanion(
      id: Value(id),
      date: Value(date),
      type: Value(type),
      amount: Value(amount),
      currency: Value(currency),
      cnyAmount: cnyAmount == null && nullToAbsent
          ? const Value.absent()
          : Value(cnyAmount),
      exchangeRate: exchangeRate == null && nullToAbsent
          ? const Value.absent()
          : Value(exchangeRate),
      exchangeRateDate: exchangeRateDate == null && nullToAbsent
          ? const Value.absent()
          : Value(exchangeRateDate),
      exchangeRateSource: exchangeRateSource == null && nullToAbsent
          ? const Value.absent()
          : Value(exchangeRateSource),
      conversionStatus: Value(conversionStatus),
      categoryId: categoryId == null && nullToAbsent
          ? const Value.absent()
          : Value(categoryId),
      accountId: accountId == null && nullToAbsent
          ? const Value.absent()
          : Value(accountId),
      fromAccountId: fromAccountId == null && nullToAbsent
          ? const Value.absent()
          : Value(fromAccountId),
      toAccountId: toAccountId == null && nullToAbsent
          ? const Value.absent()
          : Value(toAccountId),
      occurredAt: occurredAt == null && nullToAbsent
          ? const Value.absent()
          : Value(occurredAt),
      note: Value(note),
      clientOpId: Value(clientOpId),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
      serverVersion: Value(serverVersion),
    );
  }

  factory LocalTransaction.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LocalTransaction(
      id: serializer.fromJson<String>(json['id']),
      date: serializer.fromJson<String>(json['date']),
      type: serializer.fromJson<String>(json['type']),
      amount: serializer.fromJson<double>(json['amount']),
      currency: serializer.fromJson<String>(json['currency']),
      cnyAmount: serializer.fromJson<double?>(json['cnyAmount']),
      exchangeRate: serializer.fromJson<double?>(json['exchangeRate']),
      exchangeRateDate: serializer.fromJson<String?>(json['exchangeRateDate']),
      exchangeRateSource:
          serializer.fromJson<String?>(json['exchangeRateSource']),
      conversionStatus: serializer.fromJson<String>(json['conversionStatus']),
      categoryId: serializer.fromJson<String?>(json['categoryId']),
      accountId: serializer.fromJson<String?>(json['accountId']),
      fromAccountId: serializer.fromJson<String?>(json['fromAccountId']),
      toAccountId: serializer.fromJson<String?>(json['toAccountId']),
      occurredAt: serializer.fromJson<String?>(json['occurredAt']),
      note: serializer.fromJson<String>(json['note']),
      clientOpId: serializer.fromJson<String>(json['clientOpId']),
      deletedAt: serializer.fromJson<String?>(json['deletedAt']),
      serverVersion: serializer.fromJson<int>(json['serverVersion']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'date': serializer.toJson<String>(date),
      'type': serializer.toJson<String>(type),
      'amount': serializer.toJson<double>(amount),
      'currency': serializer.toJson<String>(currency),
      'cnyAmount': serializer.toJson<double?>(cnyAmount),
      'exchangeRate': serializer.toJson<double?>(exchangeRate),
      'exchangeRateDate': serializer.toJson<String?>(exchangeRateDate),
      'exchangeRateSource': serializer.toJson<String?>(exchangeRateSource),
      'conversionStatus': serializer.toJson<String>(conversionStatus),
      'categoryId': serializer.toJson<String?>(categoryId),
      'accountId': serializer.toJson<String?>(accountId),
      'fromAccountId': serializer.toJson<String?>(fromAccountId),
      'toAccountId': serializer.toJson<String?>(toAccountId),
      'occurredAt': serializer.toJson<String?>(occurredAt),
      'note': serializer.toJson<String>(note),
      'clientOpId': serializer.toJson<String>(clientOpId),
      'deletedAt': serializer.toJson<String?>(deletedAt),
      'serverVersion': serializer.toJson<int>(serverVersion),
    };
  }

  LocalTransaction copyWith(
          {String? id,
          String? date,
          String? type,
          double? amount,
          String? currency,
          Value<double?> cnyAmount = const Value.absent(),
          Value<double?> exchangeRate = const Value.absent(),
          Value<String?> exchangeRateDate = const Value.absent(),
          Value<String?> exchangeRateSource = const Value.absent(),
          String? conversionStatus,
          Value<String?> categoryId = const Value.absent(),
          Value<String?> accountId = const Value.absent(),
          Value<String?> fromAccountId = const Value.absent(),
          Value<String?> toAccountId = const Value.absent(),
          Value<String?> occurredAt = const Value.absent(),
          String? note,
          String? clientOpId,
          Value<String?> deletedAt = const Value.absent(),
          int? serverVersion}) =>
      LocalTransaction(
        id: id ?? this.id,
        date: date ?? this.date,
        type: type ?? this.type,
        amount: amount ?? this.amount,
        currency: currency ?? this.currency,
        cnyAmount: cnyAmount.present ? cnyAmount.value : this.cnyAmount,
        exchangeRate:
            exchangeRate.present ? exchangeRate.value : this.exchangeRate,
        exchangeRateDate: exchangeRateDate.present
            ? exchangeRateDate.value
            : this.exchangeRateDate,
        exchangeRateSource: exchangeRateSource.present
            ? exchangeRateSource.value
            : this.exchangeRateSource,
        conversionStatus: conversionStatus ?? this.conversionStatus,
        categoryId: categoryId.present ? categoryId.value : this.categoryId,
        accountId: accountId.present ? accountId.value : this.accountId,
        fromAccountId:
            fromAccountId.present ? fromAccountId.value : this.fromAccountId,
        toAccountId: toAccountId.present ? toAccountId.value : this.toAccountId,
        occurredAt: occurredAt.present ? occurredAt.value : this.occurredAt,
        note: note ?? this.note,
        clientOpId: clientOpId ?? this.clientOpId,
        deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
        serverVersion: serverVersion ?? this.serverVersion,
      );
  LocalTransaction copyWithCompanion(LocalTransactionsCompanion data) {
    return LocalTransaction(
      id: data.id.present ? data.id.value : this.id,
      date: data.date.present ? data.date.value : this.date,
      type: data.type.present ? data.type.value : this.type,
      amount: data.amount.present ? data.amount.value : this.amount,
      currency: data.currency.present ? data.currency.value : this.currency,
      cnyAmount: data.cnyAmount.present ? data.cnyAmount.value : this.cnyAmount,
      exchangeRate: data.exchangeRate.present
          ? data.exchangeRate.value
          : this.exchangeRate,
      exchangeRateDate: data.exchangeRateDate.present
          ? data.exchangeRateDate.value
          : this.exchangeRateDate,
      exchangeRateSource: data.exchangeRateSource.present
          ? data.exchangeRateSource.value
          : this.exchangeRateSource,
      conversionStatus: data.conversionStatus.present
          ? data.conversionStatus.value
          : this.conversionStatus,
      categoryId:
          data.categoryId.present ? data.categoryId.value : this.categoryId,
      accountId: data.accountId.present ? data.accountId.value : this.accountId,
      fromAccountId: data.fromAccountId.present
          ? data.fromAccountId.value
          : this.fromAccountId,
      toAccountId:
          data.toAccountId.present ? data.toAccountId.value : this.toAccountId,
      occurredAt:
          data.occurredAt.present ? data.occurredAt.value : this.occurredAt,
      note: data.note.present ? data.note.value : this.note,
      clientOpId:
          data.clientOpId.present ? data.clientOpId.value : this.clientOpId,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
      serverVersion: data.serverVersion.present
          ? data.serverVersion.value
          : this.serverVersion,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LocalTransaction(')
          ..write('id: $id, ')
          ..write('date: $date, ')
          ..write('type: $type, ')
          ..write('amount: $amount, ')
          ..write('currency: $currency, ')
          ..write('cnyAmount: $cnyAmount, ')
          ..write('exchangeRate: $exchangeRate, ')
          ..write('exchangeRateDate: $exchangeRateDate, ')
          ..write('exchangeRateSource: $exchangeRateSource, ')
          ..write('conversionStatus: $conversionStatus, ')
          ..write('categoryId: $categoryId, ')
          ..write('accountId: $accountId, ')
          ..write('fromAccountId: $fromAccountId, ')
          ..write('toAccountId: $toAccountId, ')
          ..write('occurredAt: $occurredAt, ')
          ..write('note: $note, ')
          ..write('clientOpId: $clientOpId, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('serverVersion: $serverVersion')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
      id,
      date,
      type,
      amount,
      currency,
      cnyAmount,
      exchangeRate,
      exchangeRateDate,
      exchangeRateSource,
      conversionStatus,
      categoryId,
      accountId,
      fromAccountId,
      toAccountId,
      occurredAt,
      note,
      clientOpId,
      deletedAt,
      serverVersion);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LocalTransaction &&
          other.id == this.id &&
          other.date == this.date &&
          other.type == this.type &&
          other.amount == this.amount &&
          other.currency == this.currency &&
          other.cnyAmount == this.cnyAmount &&
          other.exchangeRate == this.exchangeRate &&
          other.exchangeRateDate == this.exchangeRateDate &&
          other.exchangeRateSource == this.exchangeRateSource &&
          other.conversionStatus == this.conversionStatus &&
          other.categoryId == this.categoryId &&
          other.accountId == this.accountId &&
          other.fromAccountId == this.fromAccountId &&
          other.toAccountId == this.toAccountId &&
          other.occurredAt == this.occurredAt &&
          other.note == this.note &&
          other.clientOpId == this.clientOpId &&
          other.deletedAt == this.deletedAt &&
          other.serverVersion == this.serverVersion);
}

class LocalTransactionsCompanion extends UpdateCompanion<LocalTransaction> {
  final Value<String> id;
  final Value<String> date;
  final Value<String> type;
  final Value<double> amount;
  final Value<String> currency;
  final Value<double?> cnyAmount;
  final Value<double?> exchangeRate;
  final Value<String?> exchangeRateDate;
  final Value<String?> exchangeRateSource;
  final Value<String> conversionStatus;
  final Value<String?> categoryId;
  final Value<String?> accountId;
  final Value<String?> fromAccountId;
  final Value<String?> toAccountId;
  final Value<String?> occurredAt;
  final Value<String> note;
  final Value<String> clientOpId;
  final Value<String?> deletedAt;
  final Value<int> serverVersion;
  final Value<int> rowid;
  const LocalTransactionsCompanion({
    this.id = const Value.absent(),
    this.date = const Value.absent(),
    this.type = const Value.absent(),
    this.amount = const Value.absent(),
    this.currency = const Value.absent(),
    this.cnyAmount = const Value.absent(),
    this.exchangeRate = const Value.absent(),
    this.exchangeRateDate = const Value.absent(),
    this.exchangeRateSource = const Value.absent(),
    this.conversionStatus = const Value.absent(),
    this.categoryId = const Value.absent(),
    this.accountId = const Value.absent(),
    this.fromAccountId = const Value.absent(),
    this.toAccountId = const Value.absent(),
    this.occurredAt = const Value.absent(),
    this.note = const Value.absent(),
    this.clientOpId = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.serverVersion = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  LocalTransactionsCompanion.insert({
    required String id,
    required String date,
    required String type,
    required double amount,
    this.currency = const Value.absent(),
    this.cnyAmount = const Value.absent(),
    this.exchangeRate = const Value.absent(),
    this.exchangeRateDate = const Value.absent(),
    this.exchangeRateSource = const Value.absent(),
    this.conversionStatus = const Value.absent(),
    this.categoryId = const Value.absent(),
    this.accountId = const Value.absent(),
    this.fromAccountId = const Value.absent(),
    this.toAccountId = const Value.absent(),
    this.occurredAt = const Value.absent(),
    this.note = const Value.absent(),
    required String clientOpId,
    this.deletedAt = const Value.absent(),
    this.serverVersion = const Value.absent(),
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        date = Value(date),
        type = Value(type),
        amount = Value(amount),
        clientOpId = Value(clientOpId);
  static Insertable<LocalTransaction> custom({
    Expression<String>? id,
    Expression<String>? date,
    Expression<String>? type,
    Expression<double>? amount,
    Expression<String>? currency,
    Expression<double>? cnyAmount,
    Expression<double>? exchangeRate,
    Expression<String>? exchangeRateDate,
    Expression<String>? exchangeRateSource,
    Expression<String>? conversionStatus,
    Expression<String>? categoryId,
    Expression<String>? accountId,
    Expression<String>? fromAccountId,
    Expression<String>? toAccountId,
    Expression<String>? occurredAt,
    Expression<String>? note,
    Expression<String>? clientOpId,
    Expression<String>? deletedAt,
    Expression<int>? serverVersion,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (date != null) 'date': date,
      if (type != null) 'type': type,
      if (amount != null) 'amount': amount,
      if (currency != null) 'currency': currency,
      if (cnyAmount != null) 'cny_amount': cnyAmount,
      if (exchangeRate != null) 'exchange_rate': exchangeRate,
      if (exchangeRateDate != null) 'exchange_rate_date': exchangeRateDate,
      if (exchangeRateSource != null)
        'exchange_rate_source': exchangeRateSource,
      if (conversionStatus != null) 'conversion_status': conversionStatus,
      if (categoryId != null) 'category_id': categoryId,
      if (accountId != null) 'account_id': accountId,
      if (fromAccountId != null) 'from_account_id': fromAccountId,
      if (toAccountId != null) 'to_account_id': toAccountId,
      if (occurredAt != null) 'occurred_at': occurredAt,
      if (note != null) 'note': note,
      if (clientOpId != null) 'client_op_id': clientOpId,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (serverVersion != null) 'server_version': serverVersion,
      if (rowid != null) 'rowid': rowid,
    });
  }

  LocalTransactionsCompanion copyWith(
      {Value<String>? id,
      Value<String>? date,
      Value<String>? type,
      Value<double>? amount,
      Value<String>? currency,
      Value<double?>? cnyAmount,
      Value<double?>? exchangeRate,
      Value<String?>? exchangeRateDate,
      Value<String?>? exchangeRateSource,
      Value<String>? conversionStatus,
      Value<String?>? categoryId,
      Value<String?>? accountId,
      Value<String?>? fromAccountId,
      Value<String?>? toAccountId,
      Value<String?>? occurredAt,
      Value<String>? note,
      Value<String>? clientOpId,
      Value<String?>? deletedAt,
      Value<int>? serverVersion,
      Value<int>? rowid}) {
    return LocalTransactionsCompanion(
      id: id ?? this.id,
      date: date ?? this.date,
      type: type ?? this.type,
      amount: amount ?? this.amount,
      currency: currency ?? this.currency,
      cnyAmount: cnyAmount ?? this.cnyAmount,
      exchangeRate: exchangeRate ?? this.exchangeRate,
      exchangeRateDate: exchangeRateDate ?? this.exchangeRateDate,
      exchangeRateSource: exchangeRateSource ?? this.exchangeRateSource,
      conversionStatus: conversionStatus ?? this.conversionStatus,
      categoryId: categoryId ?? this.categoryId,
      accountId: accountId ?? this.accountId,
      fromAccountId: fromAccountId ?? this.fromAccountId,
      toAccountId: toAccountId ?? this.toAccountId,
      occurredAt: occurredAt ?? this.occurredAt,
      note: note ?? this.note,
      clientOpId: clientOpId ?? this.clientOpId,
      deletedAt: deletedAt ?? this.deletedAt,
      serverVersion: serverVersion ?? this.serverVersion,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (date.present) {
      map['date'] = Variable<String>(date.value);
    }
    if (type.present) {
      map['type'] = Variable<String>(type.value);
    }
    if (amount.present) {
      map['amount'] = Variable<double>(amount.value);
    }
    if (currency.present) {
      map['currency'] = Variable<String>(currency.value);
    }
    if (cnyAmount.present) {
      map['cny_amount'] = Variable<double>(cnyAmount.value);
    }
    if (exchangeRate.present) {
      map['exchange_rate'] = Variable<double>(exchangeRate.value);
    }
    if (exchangeRateDate.present) {
      map['exchange_rate_date'] = Variable<String>(exchangeRateDate.value);
    }
    if (exchangeRateSource.present) {
      map['exchange_rate_source'] = Variable<String>(exchangeRateSource.value);
    }
    if (conversionStatus.present) {
      map['conversion_status'] = Variable<String>(conversionStatus.value);
    }
    if (categoryId.present) {
      map['category_id'] = Variable<String>(categoryId.value);
    }
    if (accountId.present) {
      map['account_id'] = Variable<String>(accountId.value);
    }
    if (fromAccountId.present) {
      map['from_account_id'] = Variable<String>(fromAccountId.value);
    }
    if (toAccountId.present) {
      map['to_account_id'] = Variable<String>(toAccountId.value);
    }
    if (occurredAt.present) {
      map['occurred_at'] = Variable<String>(occurredAt.value);
    }
    if (note.present) {
      map['note'] = Variable<String>(note.value);
    }
    if (clientOpId.present) {
      map['client_op_id'] = Variable<String>(clientOpId.value);
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<String>(deletedAt.value);
    }
    if (serverVersion.present) {
      map['server_version'] = Variable<int>(serverVersion.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LocalTransactionsCompanion(')
          ..write('id: $id, ')
          ..write('date: $date, ')
          ..write('type: $type, ')
          ..write('amount: $amount, ')
          ..write('currency: $currency, ')
          ..write('cnyAmount: $cnyAmount, ')
          ..write('exchangeRate: $exchangeRate, ')
          ..write('exchangeRateDate: $exchangeRateDate, ')
          ..write('exchangeRateSource: $exchangeRateSource, ')
          ..write('conversionStatus: $conversionStatus, ')
          ..write('categoryId: $categoryId, ')
          ..write('accountId: $accountId, ')
          ..write('fromAccountId: $fromAccountId, ')
          ..write('toAccountId: $toAccountId, ')
          ..write('occurredAt: $occurredAt, ')
          ..write('note: $note, ')
          ..write('clientOpId: $clientOpId, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('serverVersion: $serverVersion, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $LocalSyncOperationsTable extends LocalSyncOperations
    with TableInfo<$LocalSyncOperationsTable, LocalSyncOperation> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LocalSyncOperationsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _clientOpIdMeta =
      const VerificationMeta('clientOpId');
  @override
  late final GeneratedColumn<String> clientOpId = GeneratedColumn<String>(
      'client_op_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _entityMeta = const VerificationMeta('entity');
  @override
  late final GeneratedColumn<String> entity = GeneratedColumn<String>(
      'entity', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _entityIdMeta =
      const VerificationMeta('entityId');
  @override
  late final GeneratedColumn<String> entityId = GeneratedColumn<String>(
      'entity_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _typeMeta = const VerificationMeta('type');
  @override
  late final GeneratedColumn<String> type = GeneratedColumn<String>(
      'type', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _payloadMeta =
      const VerificationMeta('payload');
  @override
  late final GeneratedColumn<String> payload = GeneratedColumn<String>(
      'payload', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<String> createdAt = GeneratedColumn<String>(
      'created_at', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  @override
  List<GeneratedColumn> get $columns =>
      [clientOpId, entity, entityId, type, payload, createdAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'local_sync_operations';
  @override
  VerificationContext validateIntegrity(Insertable<LocalSyncOperation> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('client_op_id')) {
      context.handle(
          _clientOpIdMeta,
          clientOpId.isAcceptableOrUnknown(
              data['client_op_id']!, _clientOpIdMeta));
    } else if (isInserting) {
      context.missing(_clientOpIdMeta);
    }
    if (data.containsKey('entity')) {
      context.handle(_entityMeta,
          entity.isAcceptableOrUnknown(data['entity']!, _entityMeta));
    } else if (isInserting) {
      context.missing(_entityMeta);
    }
    if (data.containsKey('entity_id')) {
      context.handle(_entityIdMeta,
          entityId.isAcceptableOrUnknown(data['entity_id']!, _entityIdMeta));
    } else if (isInserting) {
      context.missing(_entityIdMeta);
    }
    if (data.containsKey('type')) {
      context.handle(
          _typeMeta, type.isAcceptableOrUnknown(data['type']!, _typeMeta));
    } else if (isInserting) {
      context.missing(_typeMeta);
    }
    if (data.containsKey('payload')) {
      context.handle(_payloadMeta,
          payload.isAcceptableOrUnknown(data['payload']!, _payloadMeta));
    } else if (isInserting) {
      context.missing(_payloadMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {clientOpId};
  @override
  LocalSyncOperation map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LocalSyncOperation(
      clientOpId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}client_op_id'])!,
      entity: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}entity'])!,
      entityId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}entity_id'])!,
      type: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}type'])!,
      payload: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}payload'])!,
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}created_at']),
    );
  }

  @override
  $LocalSyncOperationsTable createAlias(String alias) {
    return $LocalSyncOperationsTable(attachedDatabase, alias);
  }
}

class LocalSyncOperation extends DataClass
    implements Insertable<LocalSyncOperation> {
  final String clientOpId;
  final String entity;
  final String entityId;
  final String type;
  final String payload;
  final String? createdAt;
  const LocalSyncOperation(
      {required this.clientOpId,
      required this.entity,
      required this.entityId,
      required this.type,
      required this.payload,
      this.createdAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['client_op_id'] = Variable<String>(clientOpId);
    map['entity'] = Variable<String>(entity);
    map['entity_id'] = Variable<String>(entityId);
    map['type'] = Variable<String>(type);
    map['payload'] = Variable<String>(payload);
    if (!nullToAbsent || createdAt != null) {
      map['created_at'] = Variable<String>(createdAt);
    }
    return map;
  }

  LocalSyncOperationsCompanion toCompanion(bool nullToAbsent) {
    return LocalSyncOperationsCompanion(
      clientOpId: Value(clientOpId),
      entity: Value(entity),
      entityId: Value(entityId),
      type: Value(type),
      payload: Value(payload),
      createdAt: createdAt == null && nullToAbsent
          ? const Value.absent()
          : Value(createdAt),
    );
  }

  factory LocalSyncOperation.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LocalSyncOperation(
      clientOpId: serializer.fromJson<String>(json['clientOpId']),
      entity: serializer.fromJson<String>(json['entity']),
      entityId: serializer.fromJson<String>(json['entityId']),
      type: serializer.fromJson<String>(json['type']),
      payload: serializer.fromJson<String>(json['payload']),
      createdAt: serializer.fromJson<String?>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'clientOpId': serializer.toJson<String>(clientOpId),
      'entity': serializer.toJson<String>(entity),
      'entityId': serializer.toJson<String>(entityId),
      'type': serializer.toJson<String>(type),
      'payload': serializer.toJson<String>(payload),
      'createdAt': serializer.toJson<String?>(createdAt),
    };
  }

  LocalSyncOperation copyWith(
          {String? clientOpId,
          String? entity,
          String? entityId,
          String? type,
          String? payload,
          Value<String?> createdAt = const Value.absent()}) =>
      LocalSyncOperation(
        clientOpId: clientOpId ?? this.clientOpId,
        entity: entity ?? this.entity,
        entityId: entityId ?? this.entityId,
        type: type ?? this.type,
        payload: payload ?? this.payload,
        createdAt: createdAt.present ? createdAt.value : this.createdAt,
      );
  LocalSyncOperation copyWithCompanion(LocalSyncOperationsCompanion data) {
    return LocalSyncOperation(
      clientOpId:
          data.clientOpId.present ? data.clientOpId.value : this.clientOpId,
      entity: data.entity.present ? data.entity.value : this.entity,
      entityId: data.entityId.present ? data.entityId.value : this.entityId,
      type: data.type.present ? data.type.value : this.type,
      payload: data.payload.present ? data.payload.value : this.payload,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LocalSyncOperation(')
          ..write('clientOpId: $clientOpId, ')
          ..write('entity: $entity, ')
          ..write('entityId: $entityId, ')
          ..write('type: $type, ')
          ..write('payload: $payload, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(clientOpId, entity, entityId, type, payload, createdAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LocalSyncOperation &&
          other.clientOpId == this.clientOpId &&
          other.entity == this.entity &&
          other.entityId == this.entityId &&
          other.type == this.type &&
          other.payload == this.payload &&
          other.createdAt == this.createdAt);
}

class LocalSyncOperationsCompanion extends UpdateCompanion<LocalSyncOperation> {
  final Value<String> clientOpId;
  final Value<String> entity;
  final Value<String> entityId;
  final Value<String> type;
  final Value<String> payload;
  final Value<String?> createdAt;
  final Value<int> rowid;
  const LocalSyncOperationsCompanion({
    this.clientOpId = const Value.absent(),
    this.entity = const Value.absent(),
    this.entityId = const Value.absent(),
    this.type = const Value.absent(),
    this.payload = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  LocalSyncOperationsCompanion.insert({
    required String clientOpId,
    required String entity,
    required String entityId,
    required String type,
    required String payload,
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  })  : clientOpId = Value(clientOpId),
        entity = Value(entity),
        entityId = Value(entityId),
        type = Value(type),
        payload = Value(payload);
  static Insertable<LocalSyncOperation> custom({
    Expression<String>? clientOpId,
    Expression<String>? entity,
    Expression<String>? entityId,
    Expression<String>? type,
    Expression<String>? payload,
    Expression<String>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (clientOpId != null) 'client_op_id': clientOpId,
      if (entity != null) 'entity': entity,
      if (entityId != null) 'entity_id': entityId,
      if (type != null) 'type': type,
      if (payload != null) 'payload': payload,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  LocalSyncOperationsCompanion copyWith(
      {Value<String>? clientOpId,
      Value<String>? entity,
      Value<String>? entityId,
      Value<String>? type,
      Value<String>? payload,
      Value<String?>? createdAt,
      Value<int>? rowid}) {
    return LocalSyncOperationsCompanion(
      clientOpId: clientOpId ?? this.clientOpId,
      entity: entity ?? this.entity,
      entityId: entityId ?? this.entityId,
      type: type ?? this.type,
      payload: payload ?? this.payload,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (clientOpId.present) {
      map['client_op_id'] = Variable<String>(clientOpId.value);
    }
    if (entity.present) {
      map['entity'] = Variable<String>(entity.value);
    }
    if (entityId.present) {
      map['entity_id'] = Variable<String>(entityId.value);
    }
    if (type.present) {
      map['type'] = Variable<String>(type.value);
    }
    if (payload.present) {
      map['payload'] = Variable<String>(payload.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<String>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LocalSyncOperationsCompanion(')
          ..write('clientOpId: $clientOpId, ')
          ..write('entity: $entity, ')
          ..write('entityId: $entityId, ')
          ..write('type: $type, ')
          ..write('payload: $payload, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $LocalMetadataTable extends LocalMetadata
    with TableInfo<$LocalMetadataTable, LocalMetadataData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LocalMetadataTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _keyMeta = const VerificationMeta('key');
  @override
  late final GeneratedColumn<String> key = GeneratedColumn<String>(
      'key', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _valueMeta = const VerificationMeta('value');
  @override
  late final GeneratedColumn<String> value = GeneratedColumn<String>(
      'value', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns => [key, value];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'local_metadata';
  @override
  VerificationContext validateIntegrity(Insertable<LocalMetadataData> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('key')) {
      context.handle(
          _keyMeta, key.isAcceptableOrUnknown(data['key']!, _keyMeta));
    } else if (isInserting) {
      context.missing(_keyMeta);
    }
    if (data.containsKey('value')) {
      context.handle(
          _valueMeta, value.isAcceptableOrUnknown(data['value']!, _valueMeta));
    } else if (isInserting) {
      context.missing(_valueMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {key};
  @override
  LocalMetadataData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LocalMetadataData(
      key: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}key'])!,
      value: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}value'])!,
    );
  }

  @override
  $LocalMetadataTable createAlias(String alias) {
    return $LocalMetadataTable(attachedDatabase, alias);
  }
}

class LocalMetadataData extends DataClass
    implements Insertable<LocalMetadataData> {
  final String key;
  final String value;
  const LocalMetadataData({required this.key, required this.value});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['key'] = Variable<String>(key);
    map['value'] = Variable<String>(value);
    return map;
  }

  LocalMetadataCompanion toCompanion(bool nullToAbsent) {
    return LocalMetadataCompanion(
      key: Value(key),
      value: Value(value),
    );
  }

  factory LocalMetadataData.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LocalMetadataData(
      key: serializer.fromJson<String>(json['key']),
      value: serializer.fromJson<String>(json['value']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'key': serializer.toJson<String>(key),
      'value': serializer.toJson<String>(value),
    };
  }

  LocalMetadataData copyWith({String? key, String? value}) => LocalMetadataData(
        key: key ?? this.key,
        value: value ?? this.value,
      );
  LocalMetadataData copyWithCompanion(LocalMetadataCompanion data) {
    return LocalMetadataData(
      key: data.key.present ? data.key.value : this.key,
      value: data.value.present ? data.value.value : this.value,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LocalMetadataData(')
          ..write('key: $key, ')
          ..write('value: $value')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(key, value);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LocalMetadataData &&
          other.key == this.key &&
          other.value == this.value);
}

class LocalMetadataCompanion extends UpdateCompanion<LocalMetadataData> {
  final Value<String> key;
  final Value<String> value;
  final Value<int> rowid;
  const LocalMetadataCompanion({
    this.key = const Value.absent(),
    this.value = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  LocalMetadataCompanion.insert({
    required String key,
    required String value,
    this.rowid = const Value.absent(),
  })  : key = Value(key),
        value = Value(value);
  static Insertable<LocalMetadataData> custom({
    Expression<String>? key,
    Expression<String>? value,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (key != null) 'key': key,
      if (value != null) 'value': value,
      if (rowid != null) 'rowid': rowid,
    });
  }

  LocalMetadataCompanion copyWith(
      {Value<String>? key, Value<String>? value, Value<int>? rowid}) {
    return LocalMetadataCompanion(
      key: key ?? this.key,
      value: value ?? this.value,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (key.present) {
      map['key'] = Variable<String>(key.value);
    }
    if (value.present) {
      map['value'] = Variable<String>(value.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LocalMetadataCompanion(')
          ..write('key: $key, ')
          ..write('value: $value, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $LocalBudgetsTable extends LocalBudgets
    with TableInfo<$LocalBudgetsTable, LocalBudget> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LocalBudgetsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _monthMeta = const VerificationMeta('month');
  @override
  late final GeneratedColumn<String> month = GeneratedColumn<String>(
      'month', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _categoryIdMeta =
      const VerificationMeta('categoryId');
  @override
  late final GeneratedColumn<String> categoryId = GeneratedColumn<String>(
      'category_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _budgetLimitMeta =
      const VerificationMeta('budgetLimit');
  @override
  late final GeneratedColumn<double> budgetLimit = GeneratedColumn<double>(
      'budget_limit', aliasedName, false,
      type: DriftSqlType.double, requiredDuringInsert: true);
  static const VerificationMeta _activeMeta = const VerificationMeta('active');
  @override
  late final GeneratedColumn<bool> active = GeneratedColumn<bool>(
      'active', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("active" IN (0, 1))'),
      defaultValue: const Constant(true));
  static const VerificationMeta _deletedAtMeta =
      const VerificationMeta('deletedAt');
  @override
  late final GeneratedColumn<String> deletedAt = GeneratedColumn<String>(
      'deleted_at', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _serverVersionMeta =
      const VerificationMeta('serverVersion');
  @override
  late final GeneratedColumn<int> serverVersion = GeneratedColumn<int>(
      'server_version', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _updatedAtMeta =
      const VerificationMeta('updatedAt');
  @override
  late final GeneratedColumn<String> updatedAt = GeneratedColumn<String>(
      'updated_at', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  @override
  List<GeneratedColumn> get $columns => [
        id,
        month,
        categoryId,
        budgetLimit,
        active,
        deletedAt,
        serverVersion,
        updatedAt
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'local_budgets';
  @override
  VerificationContext validateIntegrity(Insertable<LocalBudget> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('month')) {
      context.handle(
          _monthMeta, month.isAcceptableOrUnknown(data['month']!, _monthMeta));
    } else if (isInserting) {
      context.missing(_monthMeta);
    }
    if (data.containsKey('category_id')) {
      context.handle(
          _categoryIdMeta,
          categoryId.isAcceptableOrUnknown(
              data['category_id']!, _categoryIdMeta));
    } else if (isInserting) {
      context.missing(_categoryIdMeta);
    }
    if (data.containsKey('budget_limit')) {
      context.handle(
          _budgetLimitMeta,
          budgetLimit.isAcceptableOrUnknown(
              data['budget_limit']!, _budgetLimitMeta));
    } else if (isInserting) {
      context.missing(_budgetLimitMeta);
    }
    if (data.containsKey('active')) {
      context.handle(_activeMeta,
          active.isAcceptableOrUnknown(data['active']!, _activeMeta));
    }
    if (data.containsKey('deleted_at')) {
      context.handle(_deletedAtMeta,
          deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta));
    }
    if (data.containsKey('server_version')) {
      context.handle(
          _serverVersionMeta,
          serverVersion.isAcceptableOrUnknown(
              data['server_version']!, _serverVersionMeta));
    }
    if (data.containsKey('updated_at')) {
      context.handle(_updatedAtMeta,
          updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  LocalBudget map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LocalBudget(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      month: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}month'])!,
      categoryId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}category_id'])!,
      budgetLimit: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}budget_limit'])!,
      active: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}active'])!,
      deletedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}deleted_at']),
      serverVersion: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}server_version'])!,
      updatedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}updated_at']),
    );
  }

  @override
  $LocalBudgetsTable createAlias(String alias) {
    return $LocalBudgetsTable(attachedDatabase, alias);
  }
}

class LocalBudget extends DataClass implements Insertable<LocalBudget> {
  final String id;
  final String month;
  final String categoryId;
  final double budgetLimit;
  final bool active;
  final String? deletedAt;
  final int serverVersion;
  final String? updatedAt;
  const LocalBudget(
      {required this.id,
      required this.month,
      required this.categoryId,
      required this.budgetLimit,
      required this.active,
      this.deletedAt,
      required this.serverVersion,
      this.updatedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['month'] = Variable<String>(month);
    map['category_id'] = Variable<String>(categoryId);
    map['budget_limit'] = Variable<double>(budgetLimit);
    map['active'] = Variable<bool>(active);
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<String>(deletedAt);
    }
    map['server_version'] = Variable<int>(serverVersion);
    if (!nullToAbsent || updatedAt != null) {
      map['updated_at'] = Variable<String>(updatedAt);
    }
    return map;
  }

  LocalBudgetsCompanion toCompanion(bool nullToAbsent) {
    return LocalBudgetsCompanion(
      id: Value(id),
      month: Value(month),
      categoryId: Value(categoryId),
      budgetLimit: Value(budgetLimit),
      active: Value(active),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
      serverVersion: Value(serverVersion),
      updatedAt: updatedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(updatedAt),
    );
  }

  factory LocalBudget.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LocalBudget(
      id: serializer.fromJson<String>(json['id']),
      month: serializer.fromJson<String>(json['month']),
      categoryId: serializer.fromJson<String>(json['categoryId']),
      budgetLimit: serializer.fromJson<double>(json['budgetLimit']),
      active: serializer.fromJson<bool>(json['active']),
      deletedAt: serializer.fromJson<String?>(json['deletedAt']),
      serverVersion: serializer.fromJson<int>(json['serverVersion']),
      updatedAt: serializer.fromJson<String?>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'month': serializer.toJson<String>(month),
      'categoryId': serializer.toJson<String>(categoryId),
      'budgetLimit': serializer.toJson<double>(budgetLimit),
      'active': serializer.toJson<bool>(active),
      'deletedAt': serializer.toJson<String?>(deletedAt),
      'serverVersion': serializer.toJson<int>(serverVersion),
      'updatedAt': serializer.toJson<String?>(updatedAt),
    };
  }

  LocalBudget copyWith(
          {String? id,
          String? month,
          String? categoryId,
          double? budgetLimit,
          bool? active,
          Value<String?> deletedAt = const Value.absent(),
          int? serverVersion,
          Value<String?> updatedAt = const Value.absent()}) =>
      LocalBudget(
        id: id ?? this.id,
        month: month ?? this.month,
        categoryId: categoryId ?? this.categoryId,
        budgetLimit: budgetLimit ?? this.budgetLimit,
        active: active ?? this.active,
        deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
        serverVersion: serverVersion ?? this.serverVersion,
        updatedAt: updatedAt.present ? updatedAt.value : this.updatedAt,
      );
  LocalBudget copyWithCompanion(LocalBudgetsCompanion data) {
    return LocalBudget(
      id: data.id.present ? data.id.value : this.id,
      month: data.month.present ? data.month.value : this.month,
      categoryId:
          data.categoryId.present ? data.categoryId.value : this.categoryId,
      budgetLimit:
          data.budgetLimit.present ? data.budgetLimit.value : this.budgetLimit,
      active: data.active.present ? data.active.value : this.active,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
      serverVersion: data.serverVersion.present
          ? data.serverVersion.value
          : this.serverVersion,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LocalBudget(')
          ..write('id: $id, ')
          ..write('month: $month, ')
          ..write('categoryId: $categoryId, ')
          ..write('budgetLimit: $budgetLimit, ')
          ..write('active: $active, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('serverVersion: $serverVersion, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, month, categoryId, budgetLimit, active,
      deletedAt, serverVersion, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LocalBudget &&
          other.id == this.id &&
          other.month == this.month &&
          other.categoryId == this.categoryId &&
          other.budgetLimit == this.budgetLimit &&
          other.active == this.active &&
          other.deletedAt == this.deletedAt &&
          other.serverVersion == this.serverVersion &&
          other.updatedAt == this.updatedAt);
}

class LocalBudgetsCompanion extends UpdateCompanion<LocalBudget> {
  final Value<String> id;
  final Value<String> month;
  final Value<String> categoryId;
  final Value<double> budgetLimit;
  final Value<bool> active;
  final Value<String?> deletedAt;
  final Value<int> serverVersion;
  final Value<String?> updatedAt;
  final Value<int> rowid;
  const LocalBudgetsCompanion({
    this.id = const Value.absent(),
    this.month = const Value.absent(),
    this.categoryId = const Value.absent(),
    this.budgetLimit = const Value.absent(),
    this.active = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.serverVersion = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  LocalBudgetsCompanion.insert({
    required String id,
    required String month,
    required String categoryId,
    required double budgetLimit,
    this.active = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.serverVersion = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        month = Value(month),
        categoryId = Value(categoryId),
        budgetLimit = Value(budgetLimit);
  static Insertable<LocalBudget> custom({
    Expression<String>? id,
    Expression<String>? month,
    Expression<String>? categoryId,
    Expression<double>? budgetLimit,
    Expression<bool>? active,
    Expression<String>? deletedAt,
    Expression<int>? serverVersion,
    Expression<String>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (month != null) 'month': month,
      if (categoryId != null) 'category_id': categoryId,
      if (budgetLimit != null) 'budget_limit': budgetLimit,
      if (active != null) 'active': active,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (serverVersion != null) 'server_version': serverVersion,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  LocalBudgetsCompanion copyWith(
      {Value<String>? id,
      Value<String>? month,
      Value<String>? categoryId,
      Value<double>? budgetLimit,
      Value<bool>? active,
      Value<String?>? deletedAt,
      Value<int>? serverVersion,
      Value<String?>? updatedAt,
      Value<int>? rowid}) {
    return LocalBudgetsCompanion(
      id: id ?? this.id,
      month: month ?? this.month,
      categoryId: categoryId ?? this.categoryId,
      budgetLimit: budgetLimit ?? this.budgetLimit,
      active: active ?? this.active,
      deletedAt: deletedAt ?? this.deletedAt,
      serverVersion: serverVersion ?? this.serverVersion,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (month.present) {
      map['month'] = Variable<String>(month.value);
    }
    if (categoryId.present) {
      map['category_id'] = Variable<String>(categoryId.value);
    }
    if (budgetLimit.present) {
      map['budget_limit'] = Variable<double>(budgetLimit.value);
    }
    if (active.present) {
      map['active'] = Variable<bool>(active.value);
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<String>(deletedAt.value);
    }
    if (serverVersion.present) {
      map['server_version'] = Variable<int>(serverVersion.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<String>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LocalBudgetsCompanion(')
          ..write('id: $id, ')
          ..write('month: $month, ')
          ..write('categoryId: $categoryId, ')
          ..write('budgetLimit: $budgetLimit, ')
          ..write('active: $active, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('serverVersion: $serverVersion, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $LocalAccountsTable localAccounts = $LocalAccountsTable(this);
  late final $LocalTransactionsTable localTransactions =
      $LocalTransactionsTable(this);
  late final $LocalSyncOperationsTable localSyncOperations =
      $LocalSyncOperationsTable(this);
  late final $LocalMetadataTable localMetadata = $LocalMetadataTable(this);
  late final $LocalBudgetsTable localBudgets = $LocalBudgetsTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
        localAccounts,
        localTransactions,
        localSyncOperations,
        localMetadata,
        localBudgets
      ];
}

typedef $$LocalAccountsTableCreateCompanionBuilder = LocalAccountsCompanion
    Function({
  required String id,
  required String name,
  required String type,
  Value<String> accountKind,
  Value<String> currency,
  Value<double> openingBalance,
  Value<double?> openingCnyAmount,
  Value<String?> exchangeRateDate,
  Value<String?> exchangeRateSource,
  Value<bool> isLiquid,
  Value<bool> isDefaultPayment,
  Value<String?> deletedAt,
  Value<int> serverVersion,
  Value<String?> updatedAt,
  Value<int> rowid,
});
typedef $$LocalAccountsTableUpdateCompanionBuilder = LocalAccountsCompanion
    Function({
  Value<String> id,
  Value<String> name,
  Value<String> type,
  Value<String> accountKind,
  Value<String> currency,
  Value<double> openingBalance,
  Value<double?> openingCnyAmount,
  Value<String?> exchangeRateDate,
  Value<String?> exchangeRateSource,
  Value<bool> isLiquid,
  Value<bool> isDefaultPayment,
  Value<String?> deletedAt,
  Value<int> serverVersion,
  Value<String?> updatedAt,
  Value<int> rowid,
});

class $$LocalAccountsTableFilterComposer
    extends Composer<_$AppDatabase, $LocalAccountsTable> {
  $$LocalAccountsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get name => $composableBuilder(
      column: $table.name, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get type => $composableBuilder(
      column: $table.type, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get accountKind => $composableBuilder(
      column: $table.accountKind, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get currency => $composableBuilder(
      column: $table.currency, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get openingBalance => $composableBuilder(
      column: $table.openingBalance,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get openingCnyAmount => $composableBuilder(
      column: $table.openingCnyAmount,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get exchangeRateDate => $composableBuilder(
      column: $table.exchangeRateDate,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get exchangeRateSource => $composableBuilder(
      column: $table.exchangeRateSource,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get isLiquid => $composableBuilder(
      column: $table.isLiquid, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get isDefaultPayment => $composableBuilder(
      column: $table.isDefaultPayment,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get deletedAt => $composableBuilder(
      column: $table.deletedAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get serverVersion => $composableBuilder(
      column: $table.serverVersion, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnFilters(column));
}

class $$LocalAccountsTableOrderingComposer
    extends Composer<_$AppDatabase, $LocalAccountsTable> {
  $$LocalAccountsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get name => $composableBuilder(
      column: $table.name, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get type => $composableBuilder(
      column: $table.type, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get accountKind => $composableBuilder(
      column: $table.accountKind, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get currency => $composableBuilder(
      column: $table.currency, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get openingBalance => $composableBuilder(
      column: $table.openingBalance,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get openingCnyAmount => $composableBuilder(
      column: $table.openingCnyAmount,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get exchangeRateDate => $composableBuilder(
      column: $table.exchangeRateDate,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get exchangeRateSource => $composableBuilder(
      column: $table.exchangeRateSource,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get isLiquid => $composableBuilder(
      column: $table.isLiquid, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get isDefaultPayment => $composableBuilder(
      column: $table.isDefaultPayment,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get deletedAt => $composableBuilder(
      column: $table.deletedAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get serverVersion => $composableBuilder(
      column: $table.serverVersion,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnOrderings(column));
}

class $$LocalAccountsTableAnnotationComposer
    extends Composer<_$AppDatabase, $LocalAccountsTable> {
  $$LocalAccountsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get type =>
      $composableBuilder(column: $table.type, builder: (column) => column);

  GeneratedColumn<String> get accountKind => $composableBuilder(
      column: $table.accountKind, builder: (column) => column);

  GeneratedColumn<String> get currency =>
      $composableBuilder(column: $table.currency, builder: (column) => column);

  GeneratedColumn<double> get openingBalance => $composableBuilder(
      column: $table.openingBalance, builder: (column) => column);

  GeneratedColumn<double> get openingCnyAmount => $composableBuilder(
      column: $table.openingCnyAmount, builder: (column) => column);

  GeneratedColumn<String> get exchangeRateDate => $composableBuilder(
      column: $table.exchangeRateDate, builder: (column) => column);

  GeneratedColumn<String> get exchangeRateSource => $composableBuilder(
      column: $table.exchangeRateSource, builder: (column) => column);

  GeneratedColumn<bool> get isLiquid =>
      $composableBuilder(column: $table.isLiquid, builder: (column) => column);

  GeneratedColumn<bool> get isDefaultPayment => $composableBuilder(
      column: $table.isDefaultPayment, builder: (column) => column);

  GeneratedColumn<String> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);

  GeneratedColumn<int> get serverVersion => $composableBuilder(
      column: $table.serverVersion, builder: (column) => column);

  GeneratedColumn<String> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$LocalAccountsTableTableManager extends RootTableManager<
    _$AppDatabase,
    $LocalAccountsTable,
    LocalAccount,
    $$LocalAccountsTableFilterComposer,
    $$LocalAccountsTableOrderingComposer,
    $$LocalAccountsTableAnnotationComposer,
    $$LocalAccountsTableCreateCompanionBuilder,
    $$LocalAccountsTableUpdateCompanionBuilder,
    (
      LocalAccount,
      BaseReferences<_$AppDatabase, $LocalAccountsTable, LocalAccount>
    ),
    LocalAccount,
    PrefetchHooks Function()> {
  $$LocalAccountsTableTableManager(_$AppDatabase db, $LocalAccountsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LocalAccountsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LocalAccountsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$LocalAccountsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> name = const Value.absent(),
            Value<String> type = const Value.absent(),
            Value<String> accountKind = const Value.absent(),
            Value<String> currency = const Value.absent(),
            Value<double> openingBalance = const Value.absent(),
            Value<double?> openingCnyAmount = const Value.absent(),
            Value<String?> exchangeRateDate = const Value.absent(),
            Value<String?> exchangeRateSource = const Value.absent(),
            Value<bool> isLiquid = const Value.absent(),
            Value<bool> isDefaultPayment = const Value.absent(),
            Value<String?> deletedAt = const Value.absent(),
            Value<int> serverVersion = const Value.absent(),
            Value<String?> updatedAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              LocalAccountsCompanion(
            id: id,
            name: name,
            type: type,
            accountKind: accountKind,
            currency: currency,
            openingBalance: openingBalance,
            openingCnyAmount: openingCnyAmount,
            exchangeRateDate: exchangeRateDate,
            exchangeRateSource: exchangeRateSource,
            isLiquid: isLiquid,
            isDefaultPayment: isDefaultPayment,
            deletedAt: deletedAt,
            serverVersion: serverVersion,
            updatedAt: updatedAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String name,
            required String type,
            Value<String> accountKind = const Value.absent(),
            Value<String> currency = const Value.absent(),
            Value<double> openingBalance = const Value.absent(),
            Value<double?> openingCnyAmount = const Value.absent(),
            Value<String?> exchangeRateDate = const Value.absent(),
            Value<String?> exchangeRateSource = const Value.absent(),
            Value<bool> isLiquid = const Value.absent(),
            Value<bool> isDefaultPayment = const Value.absent(),
            Value<String?> deletedAt = const Value.absent(),
            Value<int> serverVersion = const Value.absent(),
            Value<String?> updatedAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              LocalAccountsCompanion.insert(
            id: id,
            name: name,
            type: type,
            accountKind: accountKind,
            currency: currency,
            openingBalance: openingBalance,
            openingCnyAmount: openingCnyAmount,
            exchangeRateDate: exchangeRateDate,
            exchangeRateSource: exchangeRateSource,
            isLiquid: isLiquid,
            isDefaultPayment: isDefaultPayment,
            deletedAt: deletedAt,
            serverVersion: serverVersion,
            updatedAt: updatedAt,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (
                    e.readTable<$LocalAccountsTable, LocalAccount>(table),
                    BaseReferences<_$AppDatabase, $LocalAccountsTable,
                        LocalAccount>(db, table, e)
                  ))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$LocalAccountsTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $LocalAccountsTable,
    LocalAccount,
    $$LocalAccountsTableFilterComposer,
    $$LocalAccountsTableOrderingComposer,
    $$LocalAccountsTableAnnotationComposer,
    $$LocalAccountsTableCreateCompanionBuilder,
    $$LocalAccountsTableUpdateCompanionBuilder,
    (
      LocalAccount,
      BaseReferences<_$AppDatabase, $LocalAccountsTable, LocalAccount>
    ),
    LocalAccount,
    PrefetchHooks Function()>;
typedef $$LocalTransactionsTableCreateCompanionBuilder
    = LocalTransactionsCompanion Function({
  required String id,
  required String date,
  required String type,
  required double amount,
  Value<String> currency,
  Value<double?> cnyAmount,
  Value<double?> exchangeRate,
  Value<String?> exchangeRateDate,
  Value<String?> exchangeRateSource,
  Value<String> conversionStatus,
  Value<String?> categoryId,
  Value<String?> accountId,
  Value<String?> fromAccountId,
  Value<String?> toAccountId,
  Value<String?> occurredAt,
  Value<String> note,
  required String clientOpId,
  Value<String?> deletedAt,
  Value<int> serverVersion,
  Value<int> rowid,
});
typedef $$LocalTransactionsTableUpdateCompanionBuilder
    = LocalTransactionsCompanion Function({
  Value<String> id,
  Value<String> date,
  Value<String> type,
  Value<double> amount,
  Value<String> currency,
  Value<double?> cnyAmount,
  Value<double?> exchangeRate,
  Value<String?> exchangeRateDate,
  Value<String?> exchangeRateSource,
  Value<String> conversionStatus,
  Value<String?> categoryId,
  Value<String?> accountId,
  Value<String?> fromAccountId,
  Value<String?> toAccountId,
  Value<String?> occurredAt,
  Value<String> note,
  Value<String> clientOpId,
  Value<String?> deletedAt,
  Value<int> serverVersion,
  Value<int> rowid,
});

class $$LocalTransactionsTableFilterComposer
    extends Composer<_$AppDatabase, $LocalTransactionsTable> {
  $$LocalTransactionsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get date => $composableBuilder(
      column: $table.date, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get type => $composableBuilder(
      column: $table.type, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get amount => $composableBuilder(
      column: $table.amount, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get currency => $composableBuilder(
      column: $table.currency, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get cnyAmount => $composableBuilder(
      column: $table.cnyAmount, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get exchangeRate => $composableBuilder(
      column: $table.exchangeRate, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get exchangeRateDate => $composableBuilder(
      column: $table.exchangeRateDate,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get exchangeRateSource => $composableBuilder(
      column: $table.exchangeRateSource,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get conversionStatus => $composableBuilder(
      column: $table.conversionStatus,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get categoryId => $composableBuilder(
      column: $table.categoryId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get accountId => $composableBuilder(
      column: $table.accountId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get fromAccountId => $composableBuilder(
      column: $table.fromAccountId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get toAccountId => $composableBuilder(
      column: $table.toAccountId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get occurredAt => $composableBuilder(
      column: $table.occurredAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get note => $composableBuilder(
      column: $table.note, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get clientOpId => $composableBuilder(
      column: $table.clientOpId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get deletedAt => $composableBuilder(
      column: $table.deletedAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get serverVersion => $composableBuilder(
      column: $table.serverVersion, builder: (column) => ColumnFilters(column));
}

class $$LocalTransactionsTableOrderingComposer
    extends Composer<_$AppDatabase, $LocalTransactionsTable> {
  $$LocalTransactionsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get date => $composableBuilder(
      column: $table.date, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get type => $composableBuilder(
      column: $table.type, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get amount => $composableBuilder(
      column: $table.amount, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get currency => $composableBuilder(
      column: $table.currency, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get cnyAmount => $composableBuilder(
      column: $table.cnyAmount, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get exchangeRate => $composableBuilder(
      column: $table.exchangeRate,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get exchangeRateDate => $composableBuilder(
      column: $table.exchangeRateDate,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get exchangeRateSource => $composableBuilder(
      column: $table.exchangeRateSource,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get conversionStatus => $composableBuilder(
      column: $table.conversionStatus,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get categoryId => $composableBuilder(
      column: $table.categoryId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get accountId => $composableBuilder(
      column: $table.accountId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get fromAccountId => $composableBuilder(
      column: $table.fromAccountId,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get toAccountId => $composableBuilder(
      column: $table.toAccountId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get occurredAt => $composableBuilder(
      column: $table.occurredAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get note => $composableBuilder(
      column: $table.note, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get clientOpId => $composableBuilder(
      column: $table.clientOpId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get deletedAt => $composableBuilder(
      column: $table.deletedAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get serverVersion => $composableBuilder(
      column: $table.serverVersion,
      builder: (column) => ColumnOrderings(column));
}

class $$LocalTransactionsTableAnnotationComposer
    extends Composer<_$AppDatabase, $LocalTransactionsTable> {
  $$LocalTransactionsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get date =>
      $composableBuilder(column: $table.date, builder: (column) => column);

  GeneratedColumn<String> get type =>
      $composableBuilder(column: $table.type, builder: (column) => column);

  GeneratedColumn<double> get amount =>
      $composableBuilder(column: $table.amount, builder: (column) => column);

  GeneratedColumn<String> get currency =>
      $composableBuilder(column: $table.currency, builder: (column) => column);

  GeneratedColumn<double> get cnyAmount =>
      $composableBuilder(column: $table.cnyAmount, builder: (column) => column);

  GeneratedColumn<double> get exchangeRate => $composableBuilder(
      column: $table.exchangeRate, builder: (column) => column);

  GeneratedColumn<String> get exchangeRateDate => $composableBuilder(
      column: $table.exchangeRateDate, builder: (column) => column);

  GeneratedColumn<String> get exchangeRateSource => $composableBuilder(
      column: $table.exchangeRateSource, builder: (column) => column);

  GeneratedColumn<String> get conversionStatus => $composableBuilder(
      column: $table.conversionStatus, builder: (column) => column);

  GeneratedColumn<String> get categoryId => $composableBuilder(
      column: $table.categoryId, builder: (column) => column);

  GeneratedColumn<String> get accountId =>
      $composableBuilder(column: $table.accountId, builder: (column) => column);

  GeneratedColumn<String> get fromAccountId => $composableBuilder(
      column: $table.fromAccountId, builder: (column) => column);

  GeneratedColumn<String> get toAccountId => $composableBuilder(
      column: $table.toAccountId, builder: (column) => column);

  GeneratedColumn<String> get occurredAt => $composableBuilder(
      column: $table.occurredAt, builder: (column) => column);

  GeneratedColumn<String> get note =>
      $composableBuilder(column: $table.note, builder: (column) => column);

  GeneratedColumn<String> get clientOpId => $composableBuilder(
      column: $table.clientOpId, builder: (column) => column);

  GeneratedColumn<String> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);

  GeneratedColumn<int> get serverVersion => $composableBuilder(
      column: $table.serverVersion, builder: (column) => column);
}

class $$LocalTransactionsTableTableManager extends RootTableManager<
    _$AppDatabase,
    $LocalTransactionsTable,
    LocalTransaction,
    $$LocalTransactionsTableFilterComposer,
    $$LocalTransactionsTableOrderingComposer,
    $$LocalTransactionsTableAnnotationComposer,
    $$LocalTransactionsTableCreateCompanionBuilder,
    $$LocalTransactionsTableUpdateCompanionBuilder,
    (
      LocalTransaction,
      BaseReferences<_$AppDatabase, $LocalTransactionsTable, LocalTransaction>
    ),
    LocalTransaction,
    PrefetchHooks Function()> {
  $$LocalTransactionsTableTableManager(
      _$AppDatabase db, $LocalTransactionsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LocalTransactionsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LocalTransactionsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$LocalTransactionsTableAnnotationComposer(
                  $db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> date = const Value.absent(),
            Value<String> type = const Value.absent(),
            Value<double> amount = const Value.absent(),
            Value<String> currency = const Value.absent(),
            Value<double?> cnyAmount = const Value.absent(),
            Value<double?> exchangeRate = const Value.absent(),
            Value<String?> exchangeRateDate = const Value.absent(),
            Value<String?> exchangeRateSource = const Value.absent(),
            Value<String> conversionStatus = const Value.absent(),
            Value<String?> categoryId = const Value.absent(),
            Value<String?> accountId = const Value.absent(),
            Value<String?> fromAccountId = const Value.absent(),
            Value<String?> toAccountId = const Value.absent(),
            Value<String?> occurredAt = const Value.absent(),
            Value<String> note = const Value.absent(),
            Value<String> clientOpId = const Value.absent(),
            Value<String?> deletedAt = const Value.absent(),
            Value<int> serverVersion = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              LocalTransactionsCompanion(
            id: id,
            date: date,
            type: type,
            amount: amount,
            currency: currency,
            cnyAmount: cnyAmount,
            exchangeRate: exchangeRate,
            exchangeRateDate: exchangeRateDate,
            exchangeRateSource: exchangeRateSource,
            conversionStatus: conversionStatus,
            categoryId: categoryId,
            accountId: accountId,
            fromAccountId: fromAccountId,
            toAccountId: toAccountId,
            occurredAt: occurredAt,
            note: note,
            clientOpId: clientOpId,
            deletedAt: deletedAt,
            serverVersion: serverVersion,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String date,
            required String type,
            required double amount,
            Value<String> currency = const Value.absent(),
            Value<double?> cnyAmount = const Value.absent(),
            Value<double?> exchangeRate = const Value.absent(),
            Value<String?> exchangeRateDate = const Value.absent(),
            Value<String?> exchangeRateSource = const Value.absent(),
            Value<String> conversionStatus = const Value.absent(),
            Value<String?> categoryId = const Value.absent(),
            Value<String?> accountId = const Value.absent(),
            Value<String?> fromAccountId = const Value.absent(),
            Value<String?> toAccountId = const Value.absent(),
            Value<String?> occurredAt = const Value.absent(),
            Value<String> note = const Value.absent(),
            required String clientOpId,
            Value<String?> deletedAt = const Value.absent(),
            Value<int> serverVersion = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              LocalTransactionsCompanion.insert(
            id: id,
            date: date,
            type: type,
            amount: amount,
            currency: currency,
            cnyAmount: cnyAmount,
            exchangeRate: exchangeRate,
            exchangeRateDate: exchangeRateDate,
            exchangeRateSource: exchangeRateSource,
            conversionStatus: conversionStatus,
            categoryId: categoryId,
            accountId: accountId,
            fromAccountId: fromAccountId,
            toAccountId: toAccountId,
            occurredAt: occurredAt,
            note: note,
            clientOpId: clientOpId,
            deletedAt: deletedAt,
            serverVersion: serverVersion,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (
                    e.readTable<$LocalTransactionsTable, LocalTransaction>(
                        table),
                    BaseReferences<_$AppDatabase, $LocalTransactionsTable,
                        LocalTransaction>(db, table, e)
                  ))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$LocalTransactionsTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $LocalTransactionsTable,
    LocalTransaction,
    $$LocalTransactionsTableFilterComposer,
    $$LocalTransactionsTableOrderingComposer,
    $$LocalTransactionsTableAnnotationComposer,
    $$LocalTransactionsTableCreateCompanionBuilder,
    $$LocalTransactionsTableUpdateCompanionBuilder,
    (
      LocalTransaction,
      BaseReferences<_$AppDatabase, $LocalTransactionsTable, LocalTransaction>
    ),
    LocalTransaction,
    PrefetchHooks Function()>;
typedef $$LocalSyncOperationsTableCreateCompanionBuilder
    = LocalSyncOperationsCompanion Function({
  required String clientOpId,
  required String entity,
  required String entityId,
  required String type,
  required String payload,
  Value<String?> createdAt,
  Value<int> rowid,
});
typedef $$LocalSyncOperationsTableUpdateCompanionBuilder
    = LocalSyncOperationsCompanion Function({
  Value<String> clientOpId,
  Value<String> entity,
  Value<String> entityId,
  Value<String> type,
  Value<String> payload,
  Value<String?> createdAt,
  Value<int> rowid,
});

class $$LocalSyncOperationsTableFilterComposer
    extends Composer<_$AppDatabase, $LocalSyncOperationsTable> {
  $$LocalSyncOperationsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get clientOpId => $composableBuilder(
      column: $table.clientOpId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get entity => $composableBuilder(
      column: $table.entity, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get entityId => $composableBuilder(
      column: $table.entityId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get type => $composableBuilder(
      column: $table.type, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get payload => $composableBuilder(
      column: $table.payload, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnFilters(column));
}

class $$LocalSyncOperationsTableOrderingComposer
    extends Composer<_$AppDatabase, $LocalSyncOperationsTable> {
  $$LocalSyncOperationsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get clientOpId => $composableBuilder(
      column: $table.clientOpId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get entity => $composableBuilder(
      column: $table.entity, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get entityId => $composableBuilder(
      column: $table.entityId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get type => $composableBuilder(
      column: $table.type, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get payload => $composableBuilder(
      column: $table.payload, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnOrderings(column));
}

class $$LocalSyncOperationsTableAnnotationComposer
    extends Composer<_$AppDatabase, $LocalSyncOperationsTable> {
  $$LocalSyncOperationsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get clientOpId => $composableBuilder(
      column: $table.clientOpId, builder: (column) => column);

  GeneratedColumn<String> get entity =>
      $composableBuilder(column: $table.entity, builder: (column) => column);

  GeneratedColumn<String> get entityId =>
      $composableBuilder(column: $table.entityId, builder: (column) => column);

  GeneratedColumn<String> get type =>
      $composableBuilder(column: $table.type, builder: (column) => column);

  GeneratedColumn<String> get payload =>
      $composableBuilder(column: $table.payload, builder: (column) => column);

  GeneratedColumn<String> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $$LocalSyncOperationsTableTableManager extends RootTableManager<
    _$AppDatabase,
    $LocalSyncOperationsTable,
    LocalSyncOperation,
    $$LocalSyncOperationsTableFilterComposer,
    $$LocalSyncOperationsTableOrderingComposer,
    $$LocalSyncOperationsTableAnnotationComposer,
    $$LocalSyncOperationsTableCreateCompanionBuilder,
    $$LocalSyncOperationsTableUpdateCompanionBuilder,
    (
      LocalSyncOperation,
      BaseReferences<_$AppDatabase, $LocalSyncOperationsTable,
          LocalSyncOperation>
    ),
    LocalSyncOperation,
    PrefetchHooks Function()> {
  $$LocalSyncOperationsTableTableManager(
      _$AppDatabase db, $LocalSyncOperationsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LocalSyncOperationsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LocalSyncOperationsTableOrderingComposer(
                  $db: db, $table: table),
          createComputedFieldComposer: () =>
              $$LocalSyncOperationsTableAnnotationComposer(
                  $db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> clientOpId = const Value.absent(),
            Value<String> entity = const Value.absent(),
            Value<String> entityId = const Value.absent(),
            Value<String> type = const Value.absent(),
            Value<String> payload = const Value.absent(),
            Value<String?> createdAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              LocalSyncOperationsCompanion(
            clientOpId: clientOpId,
            entity: entity,
            entityId: entityId,
            type: type,
            payload: payload,
            createdAt: createdAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String clientOpId,
            required String entity,
            required String entityId,
            required String type,
            required String payload,
            Value<String?> createdAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              LocalSyncOperationsCompanion.insert(
            clientOpId: clientOpId,
            entity: entity,
            entityId: entityId,
            type: type,
            payload: payload,
            createdAt: createdAt,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (
                    e.readTable<$LocalSyncOperationsTable, LocalSyncOperation>(
                        table),
                    BaseReferences<_$AppDatabase, $LocalSyncOperationsTable,
                        LocalSyncOperation>(db, table, e)
                  ))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$LocalSyncOperationsTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $LocalSyncOperationsTable,
    LocalSyncOperation,
    $$LocalSyncOperationsTableFilterComposer,
    $$LocalSyncOperationsTableOrderingComposer,
    $$LocalSyncOperationsTableAnnotationComposer,
    $$LocalSyncOperationsTableCreateCompanionBuilder,
    $$LocalSyncOperationsTableUpdateCompanionBuilder,
    (
      LocalSyncOperation,
      BaseReferences<_$AppDatabase, $LocalSyncOperationsTable,
          LocalSyncOperation>
    ),
    LocalSyncOperation,
    PrefetchHooks Function()>;
typedef $$LocalMetadataTableCreateCompanionBuilder = LocalMetadataCompanion
    Function({
  required String key,
  required String value,
  Value<int> rowid,
});
typedef $$LocalMetadataTableUpdateCompanionBuilder = LocalMetadataCompanion
    Function({
  Value<String> key,
  Value<String> value,
  Value<int> rowid,
});

class $$LocalMetadataTableFilterComposer
    extends Composer<_$AppDatabase, $LocalMetadataTable> {
  $$LocalMetadataTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get key => $composableBuilder(
      column: $table.key, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get value => $composableBuilder(
      column: $table.value, builder: (column) => ColumnFilters(column));
}

class $$LocalMetadataTableOrderingComposer
    extends Composer<_$AppDatabase, $LocalMetadataTable> {
  $$LocalMetadataTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get key => $composableBuilder(
      column: $table.key, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get value => $composableBuilder(
      column: $table.value, builder: (column) => ColumnOrderings(column));
}

class $$LocalMetadataTableAnnotationComposer
    extends Composer<_$AppDatabase, $LocalMetadataTable> {
  $$LocalMetadataTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get key =>
      $composableBuilder(column: $table.key, builder: (column) => column);

  GeneratedColumn<String> get value =>
      $composableBuilder(column: $table.value, builder: (column) => column);
}

class $$LocalMetadataTableTableManager extends RootTableManager<
    _$AppDatabase,
    $LocalMetadataTable,
    LocalMetadataData,
    $$LocalMetadataTableFilterComposer,
    $$LocalMetadataTableOrderingComposer,
    $$LocalMetadataTableAnnotationComposer,
    $$LocalMetadataTableCreateCompanionBuilder,
    $$LocalMetadataTableUpdateCompanionBuilder,
    (
      LocalMetadataData,
      BaseReferences<_$AppDatabase, $LocalMetadataTable, LocalMetadataData>
    ),
    LocalMetadataData,
    PrefetchHooks Function()> {
  $$LocalMetadataTableTableManager(_$AppDatabase db, $LocalMetadataTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LocalMetadataTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LocalMetadataTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$LocalMetadataTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> key = const Value.absent(),
            Value<String> value = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              LocalMetadataCompanion(
            key: key,
            value: value,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String key,
            required String value,
            Value<int> rowid = const Value.absent(),
          }) =>
              LocalMetadataCompanion.insert(
            key: key,
            value: value,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (
                    e.readTable<$LocalMetadataTable, LocalMetadataData>(table),
                    BaseReferences<_$AppDatabase, $LocalMetadataTable,
                        LocalMetadataData>(db, table, e)
                  ))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$LocalMetadataTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $LocalMetadataTable,
    LocalMetadataData,
    $$LocalMetadataTableFilterComposer,
    $$LocalMetadataTableOrderingComposer,
    $$LocalMetadataTableAnnotationComposer,
    $$LocalMetadataTableCreateCompanionBuilder,
    $$LocalMetadataTableUpdateCompanionBuilder,
    (
      LocalMetadataData,
      BaseReferences<_$AppDatabase, $LocalMetadataTable, LocalMetadataData>
    ),
    LocalMetadataData,
    PrefetchHooks Function()>;
typedef $$LocalBudgetsTableCreateCompanionBuilder = LocalBudgetsCompanion
    Function({
  required String id,
  required String month,
  required String categoryId,
  required double budgetLimit,
  Value<bool> active,
  Value<String?> deletedAt,
  Value<int> serverVersion,
  Value<String?> updatedAt,
  Value<int> rowid,
});
typedef $$LocalBudgetsTableUpdateCompanionBuilder = LocalBudgetsCompanion
    Function({
  Value<String> id,
  Value<String> month,
  Value<String> categoryId,
  Value<double> budgetLimit,
  Value<bool> active,
  Value<String?> deletedAt,
  Value<int> serverVersion,
  Value<String?> updatedAt,
  Value<int> rowid,
});

class $$LocalBudgetsTableFilterComposer
    extends Composer<_$AppDatabase, $LocalBudgetsTable> {
  $$LocalBudgetsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get month => $composableBuilder(
      column: $table.month, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get categoryId => $composableBuilder(
      column: $table.categoryId, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get budgetLimit => $composableBuilder(
      column: $table.budgetLimit, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get active => $composableBuilder(
      column: $table.active, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get deletedAt => $composableBuilder(
      column: $table.deletedAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get serverVersion => $composableBuilder(
      column: $table.serverVersion, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnFilters(column));
}

class $$LocalBudgetsTableOrderingComposer
    extends Composer<_$AppDatabase, $LocalBudgetsTable> {
  $$LocalBudgetsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get month => $composableBuilder(
      column: $table.month, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get categoryId => $composableBuilder(
      column: $table.categoryId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get budgetLimit => $composableBuilder(
      column: $table.budgetLimit, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get active => $composableBuilder(
      column: $table.active, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get deletedAt => $composableBuilder(
      column: $table.deletedAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get serverVersion => $composableBuilder(
      column: $table.serverVersion,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnOrderings(column));
}

class $$LocalBudgetsTableAnnotationComposer
    extends Composer<_$AppDatabase, $LocalBudgetsTable> {
  $$LocalBudgetsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get month =>
      $composableBuilder(column: $table.month, builder: (column) => column);

  GeneratedColumn<String> get categoryId => $composableBuilder(
      column: $table.categoryId, builder: (column) => column);

  GeneratedColumn<double> get budgetLimit => $composableBuilder(
      column: $table.budgetLimit, builder: (column) => column);

  GeneratedColumn<bool> get active =>
      $composableBuilder(column: $table.active, builder: (column) => column);

  GeneratedColumn<String> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);

  GeneratedColumn<int> get serverVersion => $composableBuilder(
      column: $table.serverVersion, builder: (column) => column);

  GeneratedColumn<String> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$LocalBudgetsTableTableManager extends RootTableManager<
    _$AppDatabase,
    $LocalBudgetsTable,
    LocalBudget,
    $$LocalBudgetsTableFilterComposer,
    $$LocalBudgetsTableOrderingComposer,
    $$LocalBudgetsTableAnnotationComposer,
    $$LocalBudgetsTableCreateCompanionBuilder,
    $$LocalBudgetsTableUpdateCompanionBuilder,
    (
      LocalBudget,
      BaseReferences<_$AppDatabase, $LocalBudgetsTable, LocalBudget>
    ),
    LocalBudget,
    PrefetchHooks Function()> {
  $$LocalBudgetsTableTableManager(_$AppDatabase db, $LocalBudgetsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LocalBudgetsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LocalBudgetsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$LocalBudgetsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> month = const Value.absent(),
            Value<String> categoryId = const Value.absent(),
            Value<double> budgetLimit = const Value.absent(),
            Value<bool> active = const Value.absent(),
            Value<String?> deletedAt = const Value.absent(),
            Value<int> serverVersion = const Value.absent(),
            Value<String?> updatedAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              LocalBudgetsCompanion(
            id: id,
            month: month,
            categoryId: categoryId,
            budgetLimit: budgetLimit,
            active: active,
            deletedAt: deletedAt,
            serverVersion: serverVersion,
            updatedAt: updatedAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String month,
            required String categoryId,
            required double budgetLimit,
            Value<bool> active = const Value.absent(),
            Value<String?> deletedAt = const Value.absent(),
            Value<int> serverVersion = const Value.absent(),
            Value<String?> updatedAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              LocalBudgetsCompanion.insert(
            id: id,
            month: month,
            categoryId: categoryId,
            budgetLimit: budgetLimit,
            active: active,
            deletedAt: deletedAt,
            serverVersion: serverVersion,
            updatedAt: updatedAt,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (
                    e.readTable<$LocalBudgetsTable, LocalBudget>(table),
                    BaseReferences<_$AppDatabase, $LocalBudgetsTable,
                        LocalBudget>(db, table, e)
                  ))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$LocalBudgetsTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $LocalBudgetsTable,
    LocalBudget,
    $$LocalBudgetsTableFilterComposer,
    $$LocalBudgetsTableOrderingComposer,
    $$LocalBudgetsTableAnnotationComposer,
    $$LocalBudgetsTableCreateCompanionBuilder,
    $$LocalBudgetsTableUpdateCompanionBuilder,
    (
      LocalBudget,
      BaseReferences<_$AppDatabase, $LocalBudgetsTable, LocalBudget>
    ),
    LocalBudget,
    PrefetchHooks Function()>;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$LocalAccountsTableTableManager get localAccounts =>
      $$LocalAccountsTableTableManager(_db, _db.localAccounts);
  $$LocalTransactionsTableTableManager get localTransactions =>
      $$LocalTransactionsTableTableManager(_db, _db.localTransactions);
  $$LocalSyncOperationsTableTableManager get localSyncOperations =>
      $$LocalSyncOperationsTableTableManager(_db, _db.localSyncOperations);
  $$LocalMetadataTableTableManager get localMetadata =>
      $$LocalMetadataTableTableManager(_db, _db.localMetadata);
  $$LocalBudgetsTableTableManager get localBudgets =>
      $$LocalBudgetsTableTableManager(_db, _db.localBudgets);
}
