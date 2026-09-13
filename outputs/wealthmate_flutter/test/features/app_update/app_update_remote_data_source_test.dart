import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:wealthmate_flutter/data/api_client.dart';
import 'package:wealthmate_flutter/features/app_update/data/app_update_remote_data_source.dart';

class CapturingClient extends http.BaseClient {
  Uri? requestUri;
  Map<String, String>? requestHeaders;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requestUri = request.url;
    requestHeaders = request.headers;
    return http.StreamedResponse(
      Stream<List<int>>.fromIterable([
        utf8.encode(jsonEncode({
          'latest_version': '1.0.0',
          'latest_build': 3,
          'minimum_supported_version': '1.0.0',
          'minimum_supported_build': 3,
          'force_update': false,
          'download_url': null,
          'release_notes': '',
        })),
      ]),
      200,
      headers: const {'content-type': 'application/json'},
    );
  }
}

void main() {
  test('fetch requests public version metadata without Authorization',
      () async {
    final client = CapturingClient();
    final api = ApiClient(
      baseUrl: 'https://api.example.invalid',
      token: 'must-not-be-sent',
      client: client,
    );

    final version = await AppUpdateRemoteDataSource(api: api).fetch();

    expect(client.requestUri?.path, '/app/version');
    expect(client.requestHeaders?['authorization'], isNull);
    expect(version.latestBuild, 3);
  });
}
