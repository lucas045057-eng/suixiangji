import 'package:flutter/foundation.dart';

import '../data/app_update_remote_data_source.dart';
import '../domain/app_version.dart';

enum AppUpdateStatus { idle, checking, available, upToDate, failed }

class AppUpdateStore extends ChangeNotifier {
  AppUpdateStore({
    required this.remote,
    required this.currentVersion,
    required this.currentBuild,
  });

  final AppUpdateRemoteDataSource remote;
  final String currentVersion;
  final int currentBuild;

  AppUpdateStatus _status = AppUpdateStatus.idle;
  AppVersion? _remoteVersion;
  String? _error;

  AppUpdateStatus get status => _status;
  AppVersion? get remoteVersion => _remoteVersion;
  String? get error => _error;
  bool get updateAvailable => _status == AppUpdateStatus.available;
  bool get forceUpdate =>
      _remoteVersion?.requiresForceUpdate(currentBuild) == true;

  Future<void> check() async {
    _status = AppUpdateStatus.checking;
    _error = null;
    notifyListeners();
    try {
      final remoteVersion = await remote.fetch();
      _remoteVersion = remoteVersion;
      _status = remoteVersion.isUpdateAvailable(currentBuild)
          ? AppUpdateStatus.available
          : AppUpdateStatus.upToDate;
    } on Exception catch (failure) {
      _remoteVersion = null;
      _status = AppUpdateStatus.failed;
      _error = failure.toString();
    } catch (_) {
      _remoteVersion = null;
      _status = AppUpdateStatus.failed;
      _error = '暂时无法检查更新，请稍后重试';
    }
    notifyListeners();
  }
}
