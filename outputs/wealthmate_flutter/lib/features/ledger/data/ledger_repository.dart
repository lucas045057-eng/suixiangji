import '../../../core/database/local_state_session.dart';
import '../../../data/api_client.dart';
import '../../../data/sync_queue.dart';
import '../../../domain/models.dart';
import 'ledger_remote_data_source.dart';

class LedgerRepository {
  LedgerRepository({required this.session, this.remote});

  final LocalStateSession session;
  final LedgerRemoteDataSource? remote;

  ApiClient? get api => remote?.api;
  SyncQueue get queue => session.queue;

  Future<FinanceState?> load() => session.load();

  Future<FinanceState> applyTransaction(
    FinanceState Function(FinanceState) mutation, {
    required SyncOperation operation,
  }) {
    return session.write(
      mutation,
      appendOperations: [operation],
    );
  }
}
