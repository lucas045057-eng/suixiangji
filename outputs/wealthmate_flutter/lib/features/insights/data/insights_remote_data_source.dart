import '../../../data/api_client.dart';

class InsightsRemoteDataSource {
  InsightsRemoteDataSource({required this.api});

  final ApiClient api;

  Future<Map<String, Object?>> fetchStats(String monthKey) =>
      api.fetchStats(monthKey);

  Future<Map<String, Object?>> fetchMonthlyReport(String monthKey,
          {bool force = false}) =>
      api.fetchMonthlyReport(monthKey, force: force);
}
