import '../../../core/network/api_session.dart';
import '../../../core/network/api_transport.dart';
import '../domain/app_version.dart';

class AppUpdateRemoteDataSource {
  AppUpdateRemoteDataSource({required this.api});

  final ApiSession api;

  Future<AppVersion> fetch() async {
    try {
      final json = await requestMapWithSession(
        api,
        'GET',
        '/app/version',
        includeAuth: false,
      );
      return AppVersion.fromJson(json);
    } on FormatException catch (error) {
      throw ApiFailure(ApiFailureKind.server, error.message);
    }
  }
}
