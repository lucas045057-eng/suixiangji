import 'dart:io';

import 'package:path_provider/path_provider.dart';

typedef AppUpdateProgress = void Function(int receivedBytes, int? totalBytes);

class AppUpdateDownloader {
  AppUpdateDownloader({
    HttpClient? client,
    Future<Directory> Function()? destinationDirectory,
  })  : _client = client ?? HttpClient(),
        _destinationDirectory = destinationDirectory ?? getTemporaryDirectory;

  final HttpClient _client;
  final Future<Directory> Function() _destinationDirectory;
  HttpClientRequest? _activeRequest;
  bool _cancelRequested = false;

  Future<String> download(
    Uri uri, {
    required AppUpdateProgress onProgress,
  }) async {
    if (uri.scheme.toLowerCase() != 'https' || uri.host.isEmpty) {
      throw ArgumentError.value(uri, 'uri', '更新地址必须使用 HTTPS');
    }
    if (_activeRequest != null) {
      throw StateError('已有更新下载正在进行');
    }

    final directory = await _destinationDirectory();
    await directory.create(recursive: true);
    final stamp = DateTime.now().microsecondsSinceEpoch;
    final finalFile = File('${directory.path}/suixiangji-update-$stamp.apk');
    final partialFile = File('${finalFile.path}.part');
    _cancelRequested = false;

    try {
      if (await partialFile.exists()) await partialFile.delete();
      final request = await _client.openUrl('GET', uri);
      _activeRequest = request;
      final response = await request.close();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException(
          '更新下载失败：HTTP ${response.statusCode}',
          uri: uri,
        );
      }

      final sink = partialFile.openWrite();
      var received = 0;
      try {
        await for (final chunk in response) {
          if (_cancelRequested) {
            throw const HttpException('更新下载已取消');
          }
          sink.add(chunk);
          received += chunk.length;
          onProgress(
            received,
            response.contentLength >= 0 ? response.contentLength : null,
          );
        }
      } finally {
        await sink.close();
      }

      if (_cancelRequested) throw const HttpException('更新下载已取消');
      if (response.contentLength >= 0 && received != response.contentLength) {
        throw const HttpException('更新下载内容不完整');
      }
      if (await finalFile.exists()) await finalFile.delete();
      await partialFile.rename(finalFile.path);
      return finalFile.path;
    } catch (_) {
      if (await partialFile.exists()) await partialFile.delete();
      if (await finalFile.exists()) await finalFile.delete();
      rethrow;
    } finally {
      _activeRequest = null;
      _cancelRequested = false;
    }
  }

  Future<void> cancel() async {
    _cancelRequested = true;
    final request = _activeRequest;
    if (request != null) {
      try {
        request.abort(const HttpException('更新下载已取消'));
      } catch (_) {}
    }
    // The active IOSink may still own the file handle. The download task's
    // catch/finally path closes that sink first, then removes the .part file.
  }

  void close() => _client.close(force: true);
}
