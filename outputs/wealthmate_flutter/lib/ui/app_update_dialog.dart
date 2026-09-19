import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../features/app_update/domain/app_version.dart';
import '../features/app_update/state/app_update_store.dart';

typedef AppUpdateLauncher = Future<bool> Function(Uri uri);

class AppUpdateDialog extends StatelessWidget {
  const AppUpdateDialog({
    required this.version,
    required this.forceUpdate,
    required this.onLaunch,
    this.updates,
    super.key,
  });

  final AppVersion version;
  final bool forceUpdate;
  final AppUpdateLauncher onLaunch;
  final AppUpdateStore? updates;

  @override
  Widget build(BuildContext context) {
    final store = updates;
    if (store == null) return _buildLegacy(context);
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) => _buildStateful(context, store),
    );
  }

  Widget _buildLegacy(BuildContext context) {
    return AlertDialog(
      title: Text(forceUpdate ? '需要更新' : '发现新版本'),
      content: Text(_versionText()),
      actions: [
        if (!forceUpdate)
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('稍后'),
          ),
        FilledButton(
          onPressed: () => _launchExternal(context),
          child: const Text('立即更新'),
        ),
      ],
    );
  }

  Widget _buildStateful(BuildContext context, AppUpdateStore store) {
    final statusText = switch (store.status) {
      AppUpdateStatus.downloading => '下载中 ${(store.progress * 100).round()}%',
      AppUpdateStatus.downloaded => '安装文件已准备好',
      AppUpdateStatus.installing => '正在安装更新',
      AppUpdateStatus.waitingForPermission => '请允许随想记安装应用更新',
      AppUpdateStatus.failed => store.error ?? '下载失败，请检查网络后重试',
      _ => _versionText(),
    };
    final busy = store.status == AppUpdateStatus.installing;
    final actionText = switch (store.status) {
      AppUpdateStatus.downloading => '取消下载',
      AppUpdateStatus.downloaded => '安装更新',
      AppUpdateStatus.installing => '正在安装更新',
      AppUpdateStatus.waitingForPermission => '继续安装',
      AppUpdateStatus.failed => '重试',
      _ => '立即更新',
    };

    return AlertDialog(
      title: Text(forceUpdate ? '需要更新' : '发现新版本'),
      content: Text(statusText),
      actions: [
        if (!forceUpdate &&
            store.status != AppUpdateStatus.installing &&
            store.status != AppUpdateStatus.downloading)
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('稍后'),
          ),
        FilledButton(
          onPressed: busy ? null : () => _runPrimary(context, store),
          child: Text(actionText),
        ),
      ],
    );
  }

  String _versionText() => [
        '版本 ${version.latestVersion} (${version.latestBuild})',
        if (version.releaseNotes.isNotEmpty) version.releaseNotes,
      ].join('\n\n');

  Future<void> _runPrimary(
    BuildContext context,
    AppUpdateStore store,
  ) async {
    try {
      switch (store.status) {
        case AppUpdateStatus.downloading:
          await store.cancelDownload();
        case AppUpdateStatus.downloaded:
          await store.install();
        case AppUpdateStatus.waitingForPermission:
          await store.resumeInstall();
        case AppUpdateStatus.failed:
          await store.retry();
        case AppUpdateStatus.available:
        case AppUpdateStatus.idle:
        case AppUpdateStatus.checking:
          await store.download();
        case AppUpdateStatus.installing:
        case AppUpdateStatus.upToDate:
          return;
      }
    } catch (_) {
      // AppUpdateStore retains a user-readable failure state.
    }
    if (!context.mounted) return;
    if (store.status == AppUpdateStatus.failed) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(store.error ?? '下载失败，请检查网络后重试')),
      );
    }
  }

  Future<void> _launchExternal(BuildContext context) async {
    final value = version.downloadUrl;
    if (value == null) return;
    final opened = await onLaunch(Uri.parse(value));
    if (!context.mounted) return;
    if (opened) {
      Navigator.of(context).pop();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('无法打开更新地址，请稍后重试')),
      );
    }
  }
}

Future<void> showAppUpdateDialog(
  BuildContext context, {
  required AppVersion version,
  required bool forceUpdate,
  AppUpdateLauncher onLaunch = _launchExternal,
  AppUpdateStore? updates,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: !forceUpdate,
    builder: (_) => AppUpdateDialog(
      version: version,
      forceUpdate: forceUpdate,
      onLaunch: onLaunch,
      updates: updates,
    ),
  );
}

Future<bool> _launchExternal(Uri uri) =>
    launchUrl(uri, mode: LaunchMode.externalApplication);
