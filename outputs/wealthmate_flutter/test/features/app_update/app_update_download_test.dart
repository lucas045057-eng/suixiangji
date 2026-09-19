import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

typedef DownloadProgress = void Function(int receivedBytes, int? totalBytes);
typedef AppUpdateDownloaderBuilder = AppUpdateDownloaderContract Function({
  required HttpClient client,
  required Future<Directory> Function() destinationDirectory,
});

/// Compile-time contract for the production downloader introduced by V1.0.4.
///
/// This declaration intentionally has no implementation. Task 7 binds these
/// tests to the production downloader after the RED contract is established.
abstract interface class AppUpdateDownloaderContract {
  Future<String> download(
    Uri uri, {
    required DownloadProgress onProgress,
  });

  Future<void> cancel();
}

AppUpdateDownloaderContract _productionDownloader({
  required HttpClient client,
  required Future<Directory> Function() destinationDirectory,
}) {
  throw TestFailure(
    'AppUpdateDownloader is not implemented. V1.0.4 must bind the injected '
    'HttpClient and app-specific destination to the production downloader.',
  );
}

class FakeHttpClient implements HttpClient {
  FakeHttpClient(this.response);

  final HttpClientResponse response;
  final List<Uri> openedUrls = <Uri>[];

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async {
    openedUrls.add(url);
    return FakeHttpClientRequest(response);
  }

  @override
  void close({bool force = false}) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeHttpClientRequest implements HttpClientRequest {
  FakeHttpClientRequest(this.response);

  final HttpClientResponse response;

  @override
  Future<HttpClientResponse> close() async => response;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeHttpClientResponse extends Stream<List<int>>
    implements HttpClientResponse {
  FakeHttpClientResponse({
    required this.statusCode,
    required this.contentLength,
    required Stream<List<int>> body,
  }) : _body = body;

  factory FakeHttpClientResponse.bytes(
    List<List<int>> chunks, {
    int statusCode = HttpStatus.ok,
    int? contentLength,
  }) {
    return FakeHttpClientResponse(
      statusCode: statusCode,
      contentLength: contentLength ??
          chunks.fold<int>(0, (sum, chunk) => sum + chunk.length),
      body: Stream<List<int>>.fromIterable(chunks),
    );
  }

  final Stream<List<int>> _body;

  @override
  final int statusCode;

  @override
  final int contentLength;

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return _body.listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<List<String>> _filesUnder(Directory directory) async {
  return directory
      .list(recursive: true)
      .where((entity) => entity is File)
      .map((entity) => entity.path)
      .toList();
}

void main() {
  late Directory appCache;

  setUp(() async {
    appCache = await Directory.systemTemp.createTemp('app-update-download-');
  });

  tearDown(() async {
    if (await appCache.exists()) {
      await appCache.delete(recursive: true);
    }
  });

  test('download rejects non-HTTPS URLs before opening a connection', () async {
    final client = FakeHttpClient(FakeHttpClientResponse.bytes(<List<int>>[
      <int>[1],
    ]));
    final downloader = _productionDownloader(
      client: client,
      destinationDirectory: () async => appCache,
    );

    await expectLater(
      downloader.download(
        Uri.parse('http://download.invalid/app.apk'),
        onProgress: (_, __) {},
      ),
      throwsA(anyOf(isA<ArgumentError>(), isA<FormatException>())),
    );
    expect(client.openedUrls, isEmpty);
  });

  test('download streams progress and atomically publishes an app-owned APK',
      () async {
    final client = FakeHttpClient(FakeHttpClientResponse.bytes(<List<int>>[
      <int>[1, 2],
      <int>[3, 4],
    ]));
    final progress = <double>[];
    final downloader = _productionDownloader(
      client: client,
      destinationDirectory: () async => appCache,
    );

    final path = await downloader.download(
      Uri.parse('https://download.invalid/releases/app.apk'),
      onProgress: (received, total) => progress.add(received / total!),
    );

    expect(client.openedUrls.single.scheme, 'https');
    expect(path, startsWith(appCache.path));
    expect(path, endsWith('.apk'));
    expect(await File(path).readAsBytes(), <int>[1, 2, 3, 4]);
    expect(progress, <double>[0.5, 1.0]);
    expect(await _filesUnder(appCache), isNot(contains(endsWith('.part'))));
  });

  test('a non-2xx response fails and removes every partial file', () async {
    final downloader = _productionDownloader(
      client: FakeHttpClient(FakeHttpClientResponse.bytes(
        <List<int>>[
          <int>[1, 2],
        ],
        statusCode: HttpStatus.serviceUnavailable,
      )),
      destinationDirectory: () async => appCache,
    );

    await expectLater(
      downloader.download(
        Uri.parse('https://download.invalid/app.apk'),
        onProgress: (_, __) {},
      ),
      throwsA(isA<Exception>()),
    );
    expect(await _filesUnder(appCache), isEmpty);
  });

  test('a response shorter than Content-Length fails and removes .part',
      () async {
    final downloader = _productionDownloader(
      client: FakeHttpClient(FakeHttpClientResponse.bytes(
        <List<int>>[
          <int>[1, 2],
        ],
        contentLength: 4,
      )),
      destinationDirectory: () async => appCache,
    );

    await expectLater(
      downloader.download(
        Uri.parse('https://download.invalid/app.apk'),
        onProgress: (_, __) {},
      ),
      throwsA(isA<Exception>()),
    );
    expect(await _filesUnder(appCache), isEmpty);
  });

  test('cancelling an active download fails the task and removes .part',
      () async {
    final body = StreamController<List<int>>();
    final downloader = _productionDownloader(
      client: FakeHttpClient(FakeHttpClientResponse(
        statusCode: HttpStatus.ok,
        contentLength: 4,
        body: body.stream,
      )),
      destinationDirectory: () async => appCache,
    );

    final task = downloader.download(
      Uri.parse('https://download.invalid/app.apk'),
      onProgress: (_, __) {},
    );
    body.add(<int>[1, 2]);
    await Future<void>.delayed(Duration.zero);
    await downloader.cancel();
    await body.close();

    await expectLater(task, throwsA(isA<Exception>()));
    expect(await _filesUnder(appCache), isEmpty);
  });
}
