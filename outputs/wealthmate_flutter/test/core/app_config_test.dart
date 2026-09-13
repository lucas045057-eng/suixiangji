import 'package:flutter_test/flutter_test.dart';
import 'package:wealthmate_flutter/core/config/app_config.dart';

void main() {
  test('production rejects a non-HTTPS API base URL', () {
    final config = AppConfig.forTesting(
      environment: AppEnvironment.production,
      apiBaseUrl: 'http://127.0.0.1:18000',
    );

    expect(config.configurationError, contains('HTTPS'));
  });

  test('development accepts a local HTTP API base URL', () {
    final config = AppConfig.forTesting(
      environment: AppEnvironment.development,
      apiBaseUrl: 'http://127.0.0.1:18000',
    );

    expect(config.configurationError, isNull);
  });

  test('missing production domain remains usable as offline configuration', () {
    final config = AppConfig.forTesting(
      environment: AppEnvironment.production,
      apiBaseUrl: '',
    );

    expect(config.configurationError, isNull);
    expect(config.apiBaseUrl, isNull);
  });

  test('production accepts a configured HTTPS API base URL', () {
    final config = AppConfig.forTesting(
      environment: AppEnvironment.production,
      apiBaseUrl: 'https://api.example.invalid',
    );

    expect(config.configurationError, isNull);
    expect(config.apiBaseUrl, 'https://api.example.invalid');
  });
}
