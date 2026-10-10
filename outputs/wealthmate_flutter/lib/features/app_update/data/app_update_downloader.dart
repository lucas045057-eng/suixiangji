import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../../../core/network/http_client_factory.dart';

typedef AppUpdateProgress = void Function(int receivedBytes, int? totalBytes);

class AppUpdateDownloader {
  AppUpdateDownloader({
    http.Client? client,
    HttpClientFactory? clientFactory,
    Future<Directory> Function()? destinationDirectory,
  })  : _client = client,
        _clientFactory = clientFactory ?? createPlatformHttpClientFactory(),
        _destinationDirectory = destinationDirectory ?? getTemporaryDirectory;

  http.Client? _client;
  final HttpClientFactory _clientFactory;
  final Future<Directory> Function() _destinationDirectory;
  Completer<void>? _activeAbort;
  bool _cancelRequested = false;

  Future<String> download(
    Uri uri, {
    required AppUpdateProgress onProgress,
  }) async {
    if (uri.scheme.toLowerCase() != 'https' || uri.host.isEmpty) {
      throw ArgumentError.value(uri, 'uri', '更新地址必须使用 HTTPS');
    }
    if (_activeAbort != null) {
      throw StateError('已有更新下载正在进行');
    }

    final abort = Completer<void>();
    _activeAbort = abort;
    File? partialFile, finalFile;
    _cancelRequested = false;

    try {
      final directory = await _destinationDirectory();
      await directory.create(recursive: true);
      final stamp = DateTime.now().microsecondsSinceEpoch;
      finalFile = File('${directory.path}/suixiangji-update-$stamp.apk');
      partialFile = File('${finalFile.path}.part');
      if (await partialFile.exists()) await partialFile.delete();
      if (_cancelRequested) throw const HttpException('更新下载已取消');
      final request =
          http.AbortableRequest('GET', uri, abortTrigger: abort.future);
      final response = await (_client ??= _clientFactory.create())
          .send(request)
          .timeout(const Duration(seconds: 30));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException(
          '更新下载失败：HTTP ${response.statusCode}',
          uri: uri,
        );
      }

      final sink = partialFile.openWrite();
      var received = 0;
      try {
        await for (final chunk
            in response.stream.timeout(const Duration(seconds: 60))) {
          if (_cancelRequested) {
            throw const HttpException('更新下载已取消');
          }
          sink.add(chunk);
          received += chunk.length;
          onProgress(
            received,
            response.contentLength,
          );
        }
      } finally {
        await sink.close();
      }

      if (_cancelRequested) throw const HttpException('更新下载已取消');
      if (response.contentLength != null &&
          received != response.contentLength) {
        throw const HttpException('更新下载内容不完整');
      }
      if (await finalFile.exists()) await finalFile.delete();
      await partialFile.rename(finalFile.path);
      return finalFile.path;
    } catch (_) {
      if (partialFile != null && await partialFile.exists())
        await partialFile.delete();
      if (finalFile != null && await finalFile.exists())
        await finalFile.delete();
      rethrow;
    } finally {
      if (!abort.isCompleted) abort.complete();
      _activeAbort = null;
      _cancelRequested = false;
    }
  }

  Future<void> cancel() async {
    _cancelRequested = true;
    final abort = _activeAbort;
    if (abort != null && !abort.isCompleted) abort.complete();
    // The active IOSink may still own the file handle. The download task's
    // catch/finally path closes that sink first, then removes the .part file.
  }

  void close() {
    unawaited(cancel());
    _client?.close();
  }
}
