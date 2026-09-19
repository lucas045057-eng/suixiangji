import 'package:flutter/services.dart';

const appUpdateChannelName = 'com.example.wealthmate_flutter/app_update';
const apkMimeType = 'application/vnd.android.package-archive';

enum InstallOutcome { started, waitingForPermission, unsupported, failed }

abstract interface class AppUpdateInstaller {
  Future<InstallOutcome> install(String apkPath);
}

class MethodChannelAppUpdateInstaller implements AppUpdateInstaller {
  MethodChannelAppUpdateInstaller({
    MethodChannel? channel,
  }) : _channel = channel ?? const MethodChannel(appUpdateChannelName);

  final MethodChannel _channel;

  @override
  Future<InstallOutcome> install(String apkPath) async {
    try {
      final result = await _channel.invokeMethod<Object?>(
        'installApk',
        <String, Object?>{'path': apkPath, 'mimeType': apkMimeType},
      );
      return switch (result?.toString()) {
        'started' => InstallOutcome.started,
        'waitingForPermission' => InstallOutcome.waitingForPermission,
        'unsupported' => InstallOutcome.unsupported,
        _ => InstallOutcome.failed,
      };
    } on MissingPluginException {
      return InstallOutcome.unsupported;
    } on PlatformException catch (error) {
      if (error.code == 'unsupported') return InstallOutcome.unsupported;
      return InstallOutcome.failed;
    } catch (_) {
      return InstallOutcome.failed;
    }
  }
}
