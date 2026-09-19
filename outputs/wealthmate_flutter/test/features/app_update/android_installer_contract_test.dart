import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const appUpdateChannelName = 'com.example.wealthmate_flutter/app_update';
const apkMimeType = 'application/vnd.android.package-archive';

enum InstallerOutcomeContract {
  started,
  waitingForPermission,
  unsupported,
  failed,
}

abstract interface class AppUpdateInstallerContract {
  Future<InstallerOutcomeContract> install(String apkPath);
}

typedef AppUpdateInstallerBuilder = AppUpdateInstallerContract Function({
  MethodChannel channel,
});

/// Test-only declaration of the Task 7 installer seam.
///
/// It deliberately has no MethodChannel implementation: the RED failure must
/// identify the missing production installer rather than make a test adapter
/// look like the feature exists.
AppUpdateInstallerContract _productionInstaller({
  MethodChannel channel = const MethodChannel(appUpdateChannelName),
}) {
  throw TestFailure(
    'The MethodChannel-backed AppUpdateInstaller is not implemented. '
    'V1.0.4 must bind install(String apkPath) to installApk.',
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel(appUpdateChannelName);
  final calls = <MethodCall>[];
  var nativeResult = 'started';

  setUp(() {
    calls.clear();
    nativeResult = 'started';
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return nativeResult;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('installApk is the primary action with the Android APK MIME', () async {
    final installer = _productionInstaller(channel: channel);

    final outcome = await installer.install('/app/cache/update.apk');

    expect(outcome, InstallerOutcomeContract.started);
    expect(calls, hasLength(1));
    expect(calls.single.method, 'installApk');
    expect(
      calls.single.arguments,
      <String, Object?>{
        'path': '/app/cache/update.apk',
        'mimeType': apkMimeType,
      },
    );
  });

  test('native permission result maps to waitingForPermission', () async {
    nativeResult = 'waitingForPermission';
    final installer = _productionInstaller(channel: channel);

    final outcome = await installer.install('/app/cache/update.apk');

    expect(outcome, InstallerOutcomeContract.waitingForPermission);
    expect(calls.single.method, 'installApk');
    expect(
      (calls.single.arguments as Map<Object?, Object?>)['path'],
      '/app/cache/update.apk',
    );
  });

  test('missing native channel maps to unsupported for the sole fallback path',
      () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    final installer = _productionInstaller(channel: channel);

    final outcome = await installer.install('/app/cache/update.apk');

    expect(outcome, InstallerOutcomeContract.unsupported);
  });
}
