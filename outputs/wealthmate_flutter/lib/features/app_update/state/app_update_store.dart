import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/network/api_transport.dart';
import '../data/app_update_downloader.dart';
import '../data/app_update_installer.dart';
import '../data/app_update_remote_data_source.dart';
import '../domain/app_version.dart';

enum AppUpdateStatus {
  idle,
  checking,
  available,
  downloading,
  downloaded,
  installing,
  waitingForPermission,
  upToDate,
  failed,
}

typedef AppUpdateExternalLauncher = Future<bool> Function(Uri uri);

class AppUpdateStore extends ChangeNotifier {
  AppUpdateStore({
    required this.remote,
    required this.currentVersion,
    required this.currentBuild,
    AppUpdateDownloader? downloader,
    AppUpdateInstaller? installer,
    AppUpdateExternalLauncher? externalLauncher,
  })  : downloader = downloader ?? AppUpdateDownloader(),
        installer = installer ?? MethodChannelAppUpdateInstaller(),
        externalLauncher = externalLauncher ?? _launchExternal;

  final AppUpdateRemoteDataSource remote;
  final String currentVersion;
  final int currentBuild;
  final AppUpdateDownloader downloader;
  final AppUpdateInstaller installer;
  final AppUpdateExternalLauncher externalLauncher;

  AppUpdateStatus _status = AppUpdateStatus.idle;
  AppVersion? _remoteVersion;
  String? _error;
  double _progress = 0;
  String? _cachedApkPath;
  Future<void>? _downloadFuture;
  Future<void>? _installFuture;

  AppUpdateStatus get status => _status;
  AppVersion? get remoteVersion => _remoteVersion;
  String? get error => _error;
  double get progress => _progress;
  String? get cachedApkPath => _cachedApkPath;
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
      _error = failure is ApiFailure ? failure.message : failure.toString();
    } catch (_) {
      _remoteVersion = null;
      _status = AppUpdateStatus.failed;
      _error = '暂时无法检查更新，请稍后重试';
    }
    notifyListeners();
  }

  Future<void> download() {
    final existing = _downloadFuture;
    if (existing != null) return existing;
    final task = _downloadImpl();
    _downloadFuture = task;
    task.then<void>(
      (_) => _clearDownloadTask(task),
      onError: (Object _, StackTrace __) => _clearDownloadTask(task),
    );
    return task;
  }

  Future<void> _downloadImpl() async {
    final version = _remoteVersion;
    final downloadUrl = version?.downloadUrl;
    if (downloadUrl == null) {
      throw StateError('当前更新没有可用的 HTTPS 下载地址');
    }
    _status = AppUpdateStatus.downloading;
    _progress = 0;
    _error = null;
    notifyListeners();
    try {
      final path = await downloader.download(
        Uri.parse(downloadUrl),
        onProgress: (received, total) {
          _progress = total == null || total <= 0 ? 0 : received / total;
          notifyListeners();
        },
      );
      _cachedApkPath = path;
      _progress = 1;
      _status = AppUpdateStatus.downloaded;
      notifyListeners();
    } catch (error) {
      _status = AppUpdateStatus.failed;
      _error = '下载失败，请检查网络后重试：$error';
      notifyListeners();
      rethrow;
    }
  }

  Future<void> cancelDownload() async {
    await downloader.cancel();
  }

  Future<void> retry() => download();

  Future<void> install() {
    final existing = _installFuture;
    if (existing != null) return existing;
    final task = _installImpl();
    _installFuture = task;
    task.then<void>(
      (_) => _clearInstallTask(task),
      onError: (Object _, StackTrace __) => _clearInstallTask(task),
    );
    return task;
  }

  Future<void> _installImpl() async {
    final path = _cachedApkPath;
    if (path == null) {
      throw StateError('更新安装文件尚未下载');
    }
    _status = AppUpdateStatus.installing;
    _error = null;
    notifyListeners();
    try {
      final outcome = await installer.install(path);
      switch (outcome) {
        case InstallOutcome.started:
          _status = AppUpdateStatus.installing;
        case InstallOutcome.waitingForPermission:
          _status = AppUpdateStatus.waitingForPermission;
        case InstallOutcome.unsupported:
          final url = _remoteVersion?.downloadUrl;
          final launched =
              url == null ? false : await externalLauncher(Uri.parse(url));
          if (!launched) {
            _status = AppUpdateStatus.failed;
            _error = '当前设备不支持应用内安装，请稍后重试';
          } else {
            _status = AppUpdateStatus.downloaded;
          }
        case InstallOutcome.failed:
          _status = AppUpdateStatus.failed;
          _error = '安装更新失败，请重试';
      }
      notifyListeners();
    } catch (error) {
      _status = AppUpdateStatus.failed;
      _error = '安装更新失败，请重试：$error';
      notifyListeners();
      rethrow;
    }
  }

  Future<void> resumeInstall() => install();

  void _clearDownloadTask(Future<void> task) {
    if (identical(_downloadFuture, task)) _downloadFuture = null;
  }

  void _clearInstallTask(Future<void> task) {
    if (identical(_installFuture, task)) _installFuture = null;
  }

  @override
  void dispose() {
    downloader.close();
    super.dispose();
  }
}

Future<bool> _launchExternal(Uri uri) =>
    launchUrl(uri, mode: LaunchMode.externalApplication);
