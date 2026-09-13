import 'package:http/http.dart' as http;

enum HttpTransportKind {
  cronet,
  packageHttp,
}

typedef HttpClientBuilder = http.Client Function();

abstract interface class HttpClientFactory {
  HttpTransportKind get transportKind;

  http.Client create();
}

class PlatformHttpClientFactory implements HttpClientFactory {
  PlatformHttpClientFactory({
    required this.transportKind,
    required HttpClientBuilder clientBuilder,
  }) : _clientBuilder = clientBuilder;

  @override
  final HttpTransportKind transportKind;
  final HttpClientBuilder _clientBuilder;
  http.Client? _client;

  @override
  http.Client create() => _client ??= _clientBuilder();
}
