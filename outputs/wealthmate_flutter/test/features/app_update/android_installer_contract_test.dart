import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wealthmate_flutter/features/app_update/data/app_update_installer.dart';

AppUpdateInstaller _productionInstaller({
  MethodChannel channel = const MethodChannel(appUpdateChannelName),
}) =>
    MethodChannelAppUpdateInstaller(channel: channel);

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

    expect(outcome, InstallOutcome.started);
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

    expect(outcome, InstallOutcome.waitingForPermission);
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

    expect(outcome, InstallOutcome.unsupported);
  });
}
