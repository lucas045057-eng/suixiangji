import '../../../core/database/local_state_session.dart';
import '../../../core/network/api_session.dart';
import '../../../data/sync_queue.dart';
import '../../../domain/models.dart';
import 'insights_remote_data_source.dart';

class InsightsRepository {
  InsightsRepository({required this.session, this.remote});

  final LocalStateSession session;
  final InsightsRemoteDataSource? remote;

  ApiSession? get api => remote?.api;
  SyncQueue get queue => session.queue;

  Future<FinanceState?> load() => session.load();

  Future<Map<String, Object?>> fetchStats(String monthKey) {
    final dataSource = remote;
    if (dataSource == null) return Future.error(StateError('同步服务未配置'));
    return dataSource.fetchStats(monthKey);
  }

  Future<Map<String, Object?>> fetchMonthlyReport(String monthKey,
      {bool force = false}) {
    final dataSource = remote;
    if (dataSource == null) return Future.error(StateError('同步服务未配置'));
    return dataSource.fetchMonthlyReport(monthKey, force: force);
  }

  Future<FinanceState> saveReport(Report report, {FinanceState? baseState}) {
    return session.write(
      (current) => current.copyWith(reports: [
        ...current.reports.where((item) => item.month != report.month),
        report,
      ]),
      initialState: baseState,
    );
  }
}
