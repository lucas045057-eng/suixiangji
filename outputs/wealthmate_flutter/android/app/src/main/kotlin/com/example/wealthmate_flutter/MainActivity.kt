package com.example.wealthmate_flutter

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private val channelName = "com.example.wealthmate_flutter/app_update"
    private val apkMimeType = "application/vnd.android.package-archive"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                if (call.method != "installApk") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val path = call.argument<String>("path")
                val mimeType = call.argument<String>("mimeType")
                if (path.isNullOrBlank() || mimeType != apkMimeType) {
                    result.error("invalid_argument", "Invalid APK install request", null)
                    return@setMethodCallHandler
                }

                val apk = File(path).canonicalFile
                val allowedRoots = listOf(cacheDir.canonicalFile, filesDir.canonicalFile)
                val isOwned = allowedRoots.any { root ->
                    apk.path == root.path || apk.path.startsWith(root.path + File.separator)
                }
                if (!isOwned || !apk.isFile) {
                    result.error("invalid_path", "APK must be an app-owned regular file", null)
                    return@setMethodCallHandler
                }

                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
                    !packageManager.canRequestPackageInstalls()
                ) {
                    startActivity(
                        Intent(
                            Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                            Uri.parse("package:$packageName"),
                        ),
                    )
                    result.success("waitingForPermission")
                    return@setMethodCallHandler
                }

                val apkUri = FileProvider.getUriForFile(
                    this,
                    "$packageName.fileprovider",
                    apk,
                )
                val intent = Intent(Intent.ACTION_VIEW).apply {
                    setDataAndType(apkUri, apkMimeType)
                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
                if (intent.resolveActivity(packageManager) == null) {
                    result.success("unsupported")
                    return@setMethodCallHandler
                }
                startActivity(intent)
                result.success("started")
            }
    }
}
