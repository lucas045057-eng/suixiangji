import 'dart:io';

import 'package:cronet_http/cronet_http.dart';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;

import 'http_client_factory_base.dart';

PlatformHttpClientFactory createPlatformHttpClientFactory({
  bool? isAndroid,
  HttpClientBuilder? cronetClientBuilder,
  HttpClientBuilder? packageHttpClientBuilder,
}) {
  final useCronet = isAndroid ?? Platform.isAndroid;
  if (!useCronet) {
    return PlatformHttpClientFactory(
      transportKind: HttpTransportKind.packageHttp,
      clientBuilder: packageHttpClientBuilder ?? http.Client.new,
    );
  }
  return PlatformHttpClientFactory(
    transportKind: HttpTransportKind.cronet,
    clientBuilder: cronetClientBuilder ?? _buildCronetClient,
  );
}

http.Client _buildCronetClient() {
  WidgetsFlutterBinding.ensureInitialized();
  final engine = CronetEngine.build(
    cacheMode: CacheMode.disabled,
    enableHttp2: true,
    enableQuic: false,
  );
  return CronetClient.fromCronetEngine(engine, closeEngine: true);
}
