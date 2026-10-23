import 'package:http/http.dart' as http;

typedef HttpClientBuilder = http.Client Function();

abstract interface class HttpClientFactory {
  http.Client create();
}

class PlatformHttpClientFactory implements HttpClientFactory {
  PlatformHttpClientFactory({
    required HttpClientBuilder clientBuilder,
  }) : _clientBuilder = clientBuilder;

  final HttpClientBuilder _clientBuilder;
  http.Client? _client;

  @override
  http.Client create() => _client ??= _clientBuilder();
}
