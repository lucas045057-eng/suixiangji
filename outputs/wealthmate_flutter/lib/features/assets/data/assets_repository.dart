import '../../../core/database/local_state_session.dart';
import '../../../core/network/api_session.dart';
import '../../../data/sync_queue.dart';
import '../../../domain/models.dart';
import '../domain/asset_rules.dart';
import 'assets_remote_data_source.dart';

class AssetsRepository {
  AssetsRepository({required this.session, this.remote});

  final LocalStateSession session;
  final AssetsRemoteDataSource? remote;

  ApiSession? get api => remote?.api;
  SyncQueue get queue => session.queue;

  Future<FinanceState?> load() => session.load();

  Future<FinanceState> saveAccount(Account account, {FinanceState? baseState}) {
    return session.write(
      (current) => AssetRules.upsertAccount(current, account),
      appendOperations: [
        SyncOperation(
          clientOpId:
              'account:${account.id}:${DateTime.now().microsecondsSinceEpoch}',
          entity: 'accounts',
          entityId: account.id,
          type: SyncOperationType.upsert,
          payload: account.toJson(),
          createdAt: DateTime.now().toIso8601String(),
        ),
      ],
      initialState: baseState,
    );
  }

  Future<FinanceState> setDefaultAccount(String accountId,
      {FinanceState? baseState}) {
    return session.write(
      (current) => AssetRules.setDefaultAccount(current, accountId),
      initialState: baseState,
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
  Future<FinanceState> adoptAdjustment(
    FinanceTransaction adjustment, {
    required String accountId,
    FinanceState? baseState,
  }) {
    return session.write(
      (current) => AssetRules.upsertTransaction(
        current,
        adjustment,
      ).copyWith(calibrationDrafts: current.calibrationDrafts
          .where((draft) => draft.accountId != accountId)
          .toList()),
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
                payload: account.toJson(),
                createdAt: DateTime.now().toIso8601String()));
      },
      initialState: baseState,
    );
  }
}
