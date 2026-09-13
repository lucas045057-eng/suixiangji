import 'package:flutter_test/flutter_test.dart';
import 'package:wealthmate_flutter/features/app_update/domain/app_version.dart';

Map<String, Object?> releaseJson({
  int latestBuild = 3,
  int minimumSupportedBuild = 3,
  String? downloadUrl = 'https://download.invalid/app.apk',
}) {
  return {
    'latest_version': '1.0.0',
    'latest_build': latestBuild,
    'minimum_supported_version': '1.0.0',
    'minimum_supported_build': minimumSupportedBuild,
    'force_update': false,
    'download_url': downloadUrl,
    'release_notes': '正式版本',
  };
}

void main() {
  test('Beta 1.2.0+2 sees formal 1.0.0+3 as an update', () {
    final remote = AppVersion.fromJson(releaseJson());

    expect(remote.isUpdateAvailable(2), isTrue);
  });

  test('a lower version name with an equal build is not an update', () {
    final remote = AppVersion.fromJson(releaseJson());

    expect(remote.isUpdateAvailable(3), isFalse);
  });

  test('a higher version name with a lower build is not an update', () {
    final remote = AppVersion.fromJson({
      ...releaseJson(latestBuild: 2),
      'latest_version': '1.2.1',
    });

    expect(remote.isUpdateAvailable(3), isFalse);
  });

  test(
      'a build below the minimum supported build requires a valid forced update',
      () {
    final remote = AppVersion.fromJson(releaseJson());

    expect(remote.requiresForceUpdate(2), isTrue);
    expect(remote.requiresForceUpdate(3), isFalse);
  });

  test('an insecure download URL is rejected', () {
    expect(
      () => AppVersion.fromJson(
        releaseJson(downloadUrl: 'http://download.invalid/app.apk'),
      ),
      throwsA(isA<FormatException>()),
    );
  });
}
