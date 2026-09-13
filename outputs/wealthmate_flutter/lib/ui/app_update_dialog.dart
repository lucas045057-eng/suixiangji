import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../features/app_update/domain/app_version.dart';

typedef AppUpdateLauncher = Future<bool> Function(Uri uri);

class AppUpdateDialog extends StatelessWidget {
  const AppUpdateDialog({
    required this.version,
    required this.forceUpdate,
    required this.onLaunch,
    super.key,
  });

  final AppVersion version;
  final bool forceUpdate;
  final AppUpdateLauncher onLaunch;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(forceUpdate ? '需要更新' : '发现新版本'),
      content: Text(
        [
          '版本 ${version.latestVersion} (${version.latestBuild})',
          if (version.releaseNotes.isNotEmpty) version.releaseNotes,
        ].join('\n\n'),
      ),
      actions: [
        if (!forceUpdate)
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('稍后'),
          ),
        FilledButton(
          onPressed: () => _launch(context),
          child: const Text('立即更新'),
        ),
      ],
    );
  }

  Future<void> _launch(BuildContext context) async {
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
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: !forceUpdate,
    builder: (_) => AppUpdateDialog(
      version: version,
      forceUpdate: forceUpdate,
      onLaunch: onLaunch,
    ),
  );
}

Future<bool> _launchExternal(Uri uri) =>
    launchUrl(uri, mode: LaunchMode.externalApplication);
