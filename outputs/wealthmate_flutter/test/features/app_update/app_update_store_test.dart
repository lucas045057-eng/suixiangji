import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:wealthmate_flutter/core/network/api_session.dart';
import 'package:wealthmate_flutter/core/network/api_transport.dart';
import 'package:wealthmate_flutter/features/app_update/data/app_update_remote_data_source.dart';
import 'package:wealthmate_flutter/features/app_update/domain/app_version.dart';
import 'package:wealthmate_flutter/features/app_update/state/app_update_store.dart';

class FakeAppUpdateRemoteDataSource extends AppUpdateRemoteDataSource {
  FakeAppUpdateRemoteDataSource({this.result, this.failure})
      : super(api: UnusedApiSession());

  final AppVersion? result;
  final ApiFailure? failure;

  @override
  Future<AppVersion> fetch() async {
    final error = failure;
    if (error != null) throw error;
    return result!;
  }
}

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
}
