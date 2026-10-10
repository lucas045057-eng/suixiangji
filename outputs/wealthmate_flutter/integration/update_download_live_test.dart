import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wealthmate_flutter/features/app_update/data/app_update_downloader.dart';

// Read-only public APK acceptance; never connects to finance/auth endpoints.
void main() {
  const url = String.fromEnvironment('UPDATE_APK_URL');
  const directory = String.fromEnvironment('UPDATE_ACCEPTANCE_DIRECTORY');
  const expectedBytes = int.fromEnvironment('UPDATE_APK_BYTES');
  if (url.isEmpty || directory.isEmpty || expectedBytes <= 0) {
    test(
        'live APK checks require explicit URL, directory and byte count', () {},
        skip: true);
    return;
  }
  final uri = Uri.parse(url);
  final destination = Directory(directory);
  setUpAll(() async {
    expect(uri.scheme, 'https');
    expect(uri.host, 'github.com');
    await destination.create(recursive: true);
    HttpOverrides.global = null;
  });

  test('legacy V1.0.4 Dart HttpClient downloads the entire public APK',
      () async {
    final client = HttpClient();
    try {
      final request = await client.getUrl(uri);
      final response = await request.close();
      expect(response.statusCode, 200);
      expect(response.contentLength, expectedBytes);
      final file = File('${destination.path}/legacy-v104.apk');
      final sink = file.openWrite();
      var received = 0;
      try {
        await for (final chunk in response) {
          sink.add(chunk);
          received += chunk.length;
        }
      } finally {
        await sink.close();
      }
      expect(received, expectedBytes);
      expect(await file.length(), expectedBytes);
    } finally {
      client.close(force: true);
    }
  }, timeout: const Timeout(Duration(minutes: 5)));

  test('current streaming APK downloader completes progress and file',
      () async {
    final downloader =
        AppUpdateDownloader(destinationDirectory: () async => destination);
    var received = 0;
    try {
      final path = await downloader.download(uri, onProgress: (count, total) {
        received = count;
        expect(total, expectedBytes);
      });
      expect(received, expectedBytes);
      expect(await File(path).length(), expectedBytes);
      expect(
          destination.listSync().where((file) => file.path.endsWith('.part')),
          isEmpty);
    } finally {
      downloader.close();
    }
  }, timeout: const Timeout(Duration(minutes: 5)));
}
