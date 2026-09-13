import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:wealthmate_flutter/core/network/http_client_factory.dart';

class _TrackedClient extends http.BaseClient {
  var sendCalls = 0;
  var closeCalls = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    sendCalls++;
    return http.StreamedResponse(
      Stream<List<int>>.value(<int>[]),
      200,
    );
  }

  @override
  void close() {
    closeCalls++;
    super.close();
  }
}

void main() {
  test('Android selects one Cronet client for the factory lifetime', () {
    final cronetClient = _TrackedClient();
    final packageHttpClient = _TrackedClient();
    var cronetBuilds = 0;
    var packageHttpBuilds = 0;
    final factory = createPlatformHttpClientFactory(
      isAndroid: true,
      cronetClientBuilder: () {
        cronetBuilds++;
        return cronetClient;
      },
      packageHttpClientBuilder: () {
        packageHttpBuilds++;
        return packageHttpClient;
      },
    );

    expect(factory.transportKind, HttpTransportKind.cronet);
    expect(factory.create(), same(cronetClient));
    expect(factory.create(), same(cronetClient));
    expect(cronetBuilds, 1);
    expect(packageHttpBuilds, 0);
  });

  test('non-Android selects one package:http client for the factory lifetime',
      () {
    final cronetClient = _TrackedClient();
    final packageHttpClient = _TrackedClient();
    var cronetBuilds = 0;
    var packageHttpBuilds = 0;
    final factory = createPlatformHttpClientFactory(
      isAndroid: false,
      cronetClientBuilder: () {
        cronetBuilds++;
        return cronetClient;
      },
      packageHttpClientBuilder: () {
        packageHttpBuilds++;
        return packageHttpClient;
      },
    );

    expect(factory.transportKind, HttpTransportKind.packageHttp);
    expect(factory.create(), same(packageHttpClient));
    expect(factory.create(), same(packageHttpClient));
    expect(cronetBuilds, 0);
    expect(packageHttpBuilds, 1);
  });
}
