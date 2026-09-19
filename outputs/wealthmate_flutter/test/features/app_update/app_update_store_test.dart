import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wealthmate_flutter/core/network/api_session.dart';
import 'package:wealthmate_flutter/core/network/api_transport.dart';
import 'package:wealthmate_flutter/features/app_update/data/app_update_remote_data_source.dart';
import 'package:wealthmate_flutter/features/app_update/domain/app_version.dart';
import 'package:wealthmate_flutter/features/app_update/state/app_update_store.dart';

class FakeAppUpdateRemoteDataSource extends AppUpdateRemoteDataSource {
  FakeAppUpdateRemoteDataSource({this.result, this.failure, this.future})
      : super(api: UnusedApiSession());

  final AppVersion? result;
  final ApiFailure? failure;
  final Future<AppVersion>? future;

  @override
  Future<AppVersion> fetch() async {
    final error = failure;
    if (error != null) throw error;
    final pending = future;
    if (pending != null) return pending;
    return result!;
  }
}

enum TestInstallOutcome { started, waitingForPermission, unsupported, failed }

class FakeUpdateDownloader {
  int calls = 0;
  int cancellations = 0;
  final List<Completer<String>> tasks = <Completer<String>>[];
  void Function(int receivedBytes, int? totalBytes)? onProgress;

  Future<String> download(
    Uri uri, {
    required void Function(int receivedBytes, int? totalBytes) onProgress,
  }) {
    calls += 1;
    this.onProgress = onProgress;
    final task = Completer<String>();
    tasks.add(task);
    return task.future;
  }

  Future<void> cancel() async {
    cancellations += 1;
    if (tasks.isNotEmpty && !tasks.last.isCompleted) {
      tasks.last.completeError(const FileSystemException('cancelled'));
    }
  }
}

class FakeUpdateInstaller {
  int calls = 0;
  final List<String> paths = <String>[];
  final List<Completer<TestInstallOutcome>> tasks =
      <Completer<TestInstallOutcome>>[];

  Future<TestInstallOutcome> install(String apkPath) {
    calls += 1;
    paths.add(apkPath);
    final task = Completer<TestInstallOutcome>();
    tasks.add(task);
    return task.future;
  }
}

typedef ExternalUpdateLauncher = Future<bool> Function(Uri uri);

AppUpdateStore storeWithUpdateSeams({
  required FakeAppUpdateRemoteDataSource remote,
  required FakeUpdateDownloader downloader,
  required FakeUpdateInstaller installer,
  required ExternalUpdateLauncher externalLauncher,
}) {
  try {
    return Function.apply(
      AppUpdateStore.new,
      const <Object?>[],
      <Symbol, Object?>{
        #remote: remote,
        #currentVersion: '1.0.0',
        #currentBuild: 2,
        #downloader: downloader,
        #installer: installer,
        #externalLauncher: externalLauncher,
      },
    ) as AppUpdateStore;
  } on NoSuchMethodError catch (error) {
    throw TestFailure(
      'AppUpdateStore does not expose the required injected downloader, '
      'installer, and external fallback seams: $error',
    );
  }
}

Future<void> startDownload(AppUpdateStore store) {
  try {
    return (store as dynamic).download() as Future<void>;
  } on NoSuchMethodError catch (error) {
    throw TestFailure(
      'AppUpdateStore.download() is missing; the production state machine '
      'cannot start an in-app download: $error',
    );
  }
}

Future<void> installDownloaded(AppUpdateStore store) {
  try {
    return (store as dynamic).install() as Future<void>;
  } on NoSuchMethodError catch (error) {
    throw TestFailure(
      'AppUpdateStore.install() is missing; the cached APK cannot reach the '
      'native installer: $error',
    );
  }
}

Future<void> retryUpdate(AppUpdateStore store) {
  try {
    return (store as dynamic).retry() as Future<void>;
  } on NoSuchMethodError catch (error) {
    throw TestFailure(
      'AppUpdateStore.retry() is missing; failed downloads cannot create a '
      'fresh task: $error',
    );
  }
}

Future<void> resumeInstall(AppUpdateStore store) {
  try {
    return (store as dynamic).resumeInstall() as Future<void>;
  } on NoSuchMethodError catch (error) {
    throw TestFailure(
      'AppUpdateStore.resumeInstall() is missing; permission return cannot '
      'reuse the cached APK: $error',
    );
  }
}

double updateProgress(AppUpdateStore store) {
  try {
    return (store as dynamic).progress as double;
  } on NoSuchMethodError catch (error) {
    throw TestFailure('AppUpdateStore.progress is missing: $error');
  }
}

String? cachedApkPath(AppUpdateStore store) {
  try {
    return (store as dynamic).cachedApkPath as String?;
  } on NoSuchMethodError catch (error) {
    throw TestFailure('AppUpdateStore.cachedApkPath is missing: $error');
  }
}

String statusName(AppUpdateStore store) => store.status.name;

class UnusedApiSession implements ApiSession {
  @override
  ApiTransport get transport => throw UnimplementedError();

  @override
  String? get token => null;

  @override
  int get sessionGeneration => 0;

  @override
  Future<void> Function()? get onAuthExpired => null;

  @override
  set onAuthExpired(FutureOr<void> Function()? callback) {}

  @override
  int beginSession() => 0;

  @override
  void requireSession(int generation, [String? requestToken]) {}

  @override
  Future<void> saveToken(String value, {bool newSession = true}) async {}

  @override
  Future<void> saveLastVerifiedUserId(String userId) async {}

  @override
  Future<void> logout() async {}
}

AppVersion release() => AppVersion.fromJson({
      'latest_version': '1.0.0',
      'latest_build': 3,
      'minimum_supported_version': '1.0.0',
      'minimum_supported_build': 3,
      'force_update': false,
      'download_url': 'https://download.invalid/app.apk',
      'release_notes': '正式版本',
    });

void main() {
  test('check exposes checking before the available state', () async {
    final response = Completer<AppVersion>();
    final store = AppUpdateStore(
      remote: FakeAppUpdateRemoteDataSource(future: response.future),
      currentVersion: '1.0.0',
      currentBuild: 2,
    );

    final task = store.check();
    expect(store.status, AppUpdateStatus.checking);
    response.complete(release());
    await task;

    expect(store.status, AppUpdateStatus.available);
  });

  test('check reports an available update by build number', () async {
    final store = AppUpdateStore(
      remote: FakeAppUpdateRemoteDataSource(result: release()),
      currentVersion: '1.2.0',
      currentBuild: 2,
    );

    await store.check();

    expect(store.status, AppUpdateStatus.available);
    expect(store.updateAvailable, isTrue);
    expect(store.forceUpdate, isTrue);
  });

  test('check reports a failed status without throwing', () async {
    final store = AppUpdateStore(
      remote: FakeAppUpdateRemoteDataSource(
        failure: const ApiFailure(ApiFailureKind.network, 'offline'),
      ),
      currentVersion: '1.0.0',
      currentBuild: 3,
    );

    await store.check();

    expect(store.status, AppUpdateStatus.failed);
    expect(store.error, 'offline');
  });

  test('download progress reaches downloaded then install reaches installing',
      () async {
    final downloader = FakeUpdateDownloader();
    final installer = FakeUpdateInstaller();
    final store = storeWithUpdateSeams(
      remote: FakeAppUpdateRemoteDataSource(result: release()),
      downloader: downloader,
      installer: installer,
      externalLauncher: (_) async => true,
    );
    await store.check();

    final download = startDownload(store);
    expect(statusName(store), 'downloading');
    downloader.onProgress!(2, 4);
    expect(updateProgress(store), closeTo(0.5, 0.01));
    downloader.tasks.single.complete('/app/cache/update.apk');
    await download;
    expect(statusName(store), 'downloaded');
    expect(cachedApkPath(store), '/app/cache/update.apk');

    final installation = installDownloaded(store);
    expect(statusName(store), 'installing');
    installer.tasks.single.complete(TestInstallOutcome.started);
    await installation;
  });

  test('active callers share one download Future and start one request',
      () async {
    final downloader = FakeUpdateDownloader();
    final store = storeWithUpdateSeams(
      remote: FakeAppUpdateRemoteDataSource(result: release()),
      downloader: downloader,
      installer: FakeUpdateInstaller(),
      externalLauncher: (_) async => true,
    );
    await store.check();

    final first = startDownload(store);
    final second = startDownload(store);

    expect(identical(first, second), isTrue);
    expect(downloader.calls, 1);
    downloader.tasks.single.complete('/app/cache/update.apk');
    await first;
    await second;
  });

  test('network failure is retryable and retry creates a new task', () async {
    final downloader = FakeUpdateDownloader();
    final store = storeWithUpdateSeams(
      remote: FakeAppUpdateRemoteDataSource(result: release()),
      downloader: downloader,
      installer: FakeUpdateInstaller(),
      externalLauncher: (_) async => true,
    );
    await store.check();

    final first = startDownload(store);
    downloader.tasks.single.completeError(const SocketException('offline'));
    await expectLater(first, throwsA(isA<SocketException>()));
    expect(statusName(store), 'failed');
    expect(store.error, contains('下载失败'));

    final retry = retryUpdate(store);
    expect(identical(first, retry), isFalse);
    expect(downloader.calls, 2);
    downloader.tasks.last.complete('/app/cache/update.apk');
    await retry;
    expect(statusName(store), 'downloaded');
  });

  test('permission resume reuses the cached APK without redownloading',
      () async {
    final downloader = FakeUpdateDownloader();
    final installer = FakeUpdateInstaller();
    final store = storeWithUpdateSeams(
      remote: FakeAppUpdateRemoteDataSource(result: release()),
      downloader: downloader,
      installer: installer,
      externalLauncher: (_) async => true,
    );
    await store.check();

    final download = startDownload(store);
    downloader.tasks.single.complete('/app/cache/update.apk');
    await download;
    final firstInstall = installDownloaded(store);
    installer.tasks.single.complete(TestInstallOutcome.waitingForPermission);
    await firstInstall;

    expect(statusName(store), 'waitingForPermission');
    expect(cachedApkPath(store), '/app/cache/update.apk');
    final resumed = resumeInstall(store);
    expect(downloader.calls, 1);
    expect(installer.calls, 2);
    expect(installer.paths, <String>[
      '/app/cache/update.apk',
      '/app/cache/update.apk',
    ]);
    installer.tasks.last.complete(TestInstallOutcome.started);
    await resumed;
  });

  test('external URL fallback runs only when native install is unsupported',
      () async {
    for (final outcome in TestInstallOutcome.values) {
      final downloader = FakeUpdateDownloader();
      final installer = FakeUpdateInstaller();
      var launches = 0;
      final store = storeWithUpdateSeams(
        remote: FakeAppUpdateRemoteDataSource(result: release()),
        downloader: downloader,
        installer: installer,
        externalLauncher: (_) async {
          launches += 1;
          return true;
        },
      );
      await store.check();
      final download = startDownload(store);
      downloader.tasks.single.complete('/app/cache/update.apk');
      await download;

      final installation = installDownloaded(store);
      installer.tasks.single.complete(outcome);
      await installation;

      expect(
        launches,
        outcome == TestInstallOutcome.unsupported ? 1 : 0,
        reason:
            'Native outcome $outcome must not make Chrome the primary path.',
      );
    }
  });
}
