import '../../../core/database/local_state_session.dart';
import '../../../core/network/api_session.dart';
import '../../../core/network/api_transport.dart';
import '../../../data/sync_queue.dart';
import '../../../domain/models.dart';
import '../domain/asset_rules.dart';
import 'assets_remote_data_source.dart';

/// Account payload as the V2 wire expects it: the default flag is read-only on
/// the account entity and must be omitted, otherwise the server rejects a
/// changed projection with `read_only_field`.
Map<String, Object?> accountWirePayload(Account account) {
  final json = account.toJson();
  json.remove('is_default_payment');
  return json;
}

class AssetsRepository {
  AssetsRepository({required this.session, this.remote});

  final LocalStateSession session;
  final AssetsRemoteDataSource? remote;

  ApiSession? get api => remote?.api;
  SyncQueue get queue => session.queue;

  Future<FinanceState?> load() => session.load();

  /// Fetches the server-signed calibration basis; the store persists the
  /// token together with the original target and effective date.
  Future<BalanceBasis> fetchBalanceBasis({
    required String accountId,
    required String effectiveOn,
  }) {
    final source = remote;
    if (source == null) {
      throw const ApiFailure(ApiFailureKind.configuration, '当前未配置同步服务');
    }
    return source.fetchBalanceBasis(
        accountId: accountId, effectiveOn: effectiveOn);
  }

  Future<WealthView> fetchWealthSnapshot({String? asOfDate}) {
    final source = remote;
    if (source == null) {
      throw const ApiFailure(ApiFailureKind.configuration, '当前未配置同步服务');
    }
    return source.fetchWealthSnapshot(asOfDate: asOfDate);
  }

  Future<FinanceState> saveAccount(Account account, {FinanceState? baseState}) {
    return session.write(
      (current) => AssetRules.upsertAccount(current, account),
      deriveOperations: (current, next) {
        final previous =
            current.accounts.where((item) => item.id == account.id).firstOrNull;
        final saved =
            next.accounts.where((item) => item.id == account.id).firstOrNull;
        if (saved == null) return const <SyncOperation>[];
        final timestamp = DateTime.now().toIso8601String();
        final operations = <SyncOperation>[
          SyncOperation(
            clientOpId:
                'account:${account.id}:${DateTime.now().microsecondsSinceEpoch}',
            entity: 'accounts',
            entityId: account.id,
            type: SyncOperationType.upsert,
            // `is_default_payment` is read-only on the account entity; the
            // default account travels through the `user_preferences` singleton.
            payload: accountWirePayload(saved),
            createdAt: timestamp,
            baseVersion: previous?.serverVersion,
            base: previous?.toJson(),
          ),
        ];
        // The local default changed (including clearing it): persist the
        // preference entity so the server owns the authoritative choice.
        if (next.defaultAccountId != current.defaultAccountId) {
          operations.add(
              _preferenceOperation(current, next.defaultAccountId, timestamp));
        }
        return operations;
      },
      initialState: baseState,
    );
  }

  Future<FinanceState> setDefaultAccount(String accountId,
      {FinanceState? baseState}) {
    return session.write(
      (current) => AssetRules.setDefaultAccount(current, accountId),
      deriveOperations: (current, next) {
        if (next.defaultAccountId == current.defaultAccountId) {
          return const <SyncOperation>[];
        }
        return [
          _preferenceOperation(
              current, next.defaultAccountId, DateTime.now().toIso8601String()),
        ];
      },
      initialState: baseState,
    );
  }

  /// Builds the singleton preference upsert. A null [defaultAccountId]
  /// explicitly clears the preference; the base snapshot is the previously
  /// known authoritative preference, never a fabricated one.
  SyncOperation _preferenceOperation(
      FinanceState current, String? defaultAccountId, String createdAt) {
    final preference = current.preference;
    return SyncOperation(
      clientOpId: 'preference:${DateTime.now().microsecondsSinceEpoch}',
      entity: 'user_preferences',
      entityId: UserPreference.singletonId,
      type: SyncOperationType.upsert,
      payload: <String, Object?>{'default_account_id': defaultAccountId},
      createdAt: createdAt,
      baseVersion: preference?.serverVersion,
      base: preference?.toJson(),
    );
  }

  Future<FinanceState> saveCalibrationDraft(CalibrationDraft draft,
      {FinanceState? baseState}) {
    // A draft is local intent only: no account upsert, no balance change.
    return session.write(
      (current) => AssetRules.upsertCalibrationDraft(current, draft),
      initialState: baseState,
    );
  }

  /// Drops an unsubmitted calibration draft for [accountId]. Used when the
  /// server declared the submission terminal (balance changed, scope mismatch)
  /// so a stale token cannot be retried by accident.
  Future<FinanceState> clearCalibrationDraft(String accountId,
      {FinanceState? baseState}) {
    return session.write(
      (current) => current.copyWith(
          calibrationDrafts: current.calibrationDrafts
              .where((draft) => draft.accountId != accountId)
              .toList()),
      initialState: baseState,
    );
  }

  /// Writes an optimistic adjustment locally. It deliberately appends no sync
  /// operation: the backend rejects adjustments on the normal transaction path.
  Future<FinanceState> saveLocalAdjustment(FinanceTransaction adjustment,
      {FinanceState? baseState}) {
    return session.write(
      (current) => AssetRules.upsertTransaction(current, adjustment),
      initialState: baseState,
    );
  }

  /// Replaces the optimistic row with the authoritative adjustment and clears
  /// the account's pending draft in the same write.
  ///
  /// The authoritative adjustment may come back under a different ID than the
  /// optimistic one. Remove the optimistic row first (matched by ID or client
  /// operation ID) so a mismatch cannot leave two rows behind and double-count
  /// the balance (Pi O-1).
  Future<FinanceState> adoptAdjustment(
    FinanceTransaction adjustment, {
    required String accountId,
    String? optimisticAdjustmentId,
    String? optimisticClientOpId,
    FinanceState? baseState,
  }) {
    return session.write(
      (current) {
        final retained = current.transactions.where((row) {
          if (row.id == adjustment.id) return true;
          if (optimisticAdjustmentId != null &&
              row.id == optimisticAdjustmentId) {
            return false;
          }
          if (optimisticClientOpId != null &&
              row.clientOpId == optimisticClientOpId) {
            return false;
          }
          return true;
        }).toList();
        return AssetRules.upsertTransaction(
          current.copyWith(transactions: retained),
          adjustment,
        ).copyWith(
            calibrationDrafts: current.calibrationDrafts
                .where((draft) => draft.accountId != accountId)
                .toList());
      },
      initialState: baseState,
    );
  }

  /// Removes an unconfirmed optimistic adjustment, optionally keeping the
  /// target as an explicitly unsubmitted draft.
  Future<FinanceState> discardAdjustment(
    String adjustmentId, {
    CalibrationDraft? draft,
    FinanceState? baseState,
  }) {
    return session.write(
      (current) {
        final next = AssetRules.removeTransaction(current, adjustmentId);
        return draft == null
            ? next
            : AssetRules.upsertCalibrationDraft(next, draft);
      },
      initialState: baseState,
    );
  }

  Future<FinanceState> saveExchangeRate(ExchangeRateSnapshot snapshot,
      {FinanceState? baseState}) {
    final base = snapshot.baseCurrency.toUpperCase();
    return session.write(
      (current) => AssetRules.applyExchangeRate(current, snapshot),
      deriveOperations: (current, next) {
        final before = {
          for (final account in current.accounts) account.id: account,
        };
        // Only accounts whose CNY opening snapshot is filled for the first
        // time produce an operation; a refresh never rewrites landed values.
        return next.accounts
            .where((account) =>
                account.isActive &&
                account.currency.toUpperCase() == base &&
                snapshot.quoteCurrency == 'CNY' &&
                account.openingCnyAmount != null &&
                before[account.id]?.openingCnyAmount == null)
            .map((account) => SyncOperation(
                clientOpId:
                    'account:${account.id}:${DateTime.now().microsecondsSinceEpoch}',
                entity: 'accounts',
                entityId: account.id,
                type: SyncOperationType.upsert,
                payload: accountWirePayload(account),
                createdAt: DateTime.now().toIso8601String(),
                baseVersion: before[account.id]?.serverVersion,
                base: before[account.id]?.toJson()));
      },
      initialState: baseState,
    );
  }
}
