import '../../../core/network/api_session.dart';

class BackupRemoteDataSource {
  BackupRemoteDataSource({required this.api});

  final ApiSession api;

  Future<Map<String, Object?>> exportBackup() =>
      requestMapWithSession(api, 'GET', '/backup/export');

  Future<Map<String, Object?>> restoreBackup(
          Map<String, Object?> backup) =>
      requestMapWithSession(
        api,
        'POST',
        '/backup/restore',
        body: backup,
      );
}
