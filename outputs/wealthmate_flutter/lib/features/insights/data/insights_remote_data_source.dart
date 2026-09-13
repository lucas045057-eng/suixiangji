import '../../../core/network/api_session.dart';

class InsightsRemoteDataSource {
  InsightsRemoteDataSource({required this.api});

  final ApiSession api;

  Future<Map<String, Object?>> fetchStats(String monthKey) =>
      requestMapWithSession(api, 'GET', '/stats?month=$monthKey');

  Future<Map<String, Object?>> fetchMonthlyReport(String monthKey,
          {bool force = false}) =>
      requestMapWithSession(
          api, 'GET', '/reports/monthly/$monthKey?force=$force');
}
