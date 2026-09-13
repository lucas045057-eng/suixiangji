import 'package:http/http.dart' as http;

import 'http_client_factory_base.dart';

PlatformHttpClientFactory createPlatformHttpClientFactory({
  bool? isAndroid,
  HttpClientBuilder? cronetClientBuilder,
  HttpClientBuilder? packageHttpClientBuilder,
}) {
  return PlatformHttpClientFactory(
    transportKind: HttpTransportKind.packageHttp,
    clientBuilder: packageHttpClientBuilder ?? http.Client.new,
  );
}
