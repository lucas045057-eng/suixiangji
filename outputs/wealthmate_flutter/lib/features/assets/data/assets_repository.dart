import '../../../core/database/local_state_session.dart';
import '../../../data/api_client.dart';
import '../../../data/sync_queue.dart';
import '../../../domain/models.dart';
import '../domain/asset_rules.dart';
import 'assets_remote_data_source.dart';

class AssetsRepository {
  AssetsRepository({required this.session, this.remote});

  final LocalStateSession session;
  final AssetsRemoteDataSource? remote;

  ApiClient? get api => remote?.api;
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

  Future<FinanceState> saveExchangeRate(ExchangeRateSnapshot snapshot,
      {FinanceState? baseState}) {
    return session.write(
      (current) => AssetRules.applyExchangeRate(current, snapshot),
      initialState: baseState,
    );
  }
}
