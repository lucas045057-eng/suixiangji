enum AppEnvironment { development, test, production }

const kProductVersion = '1.0.3';
const kProductBuild = 6;

class AppConfig {
  const AppConfig._({
    required this.environment,
    required this.apiBaseUrl,
    String? environmentError,
  }) : _environmentError = environmentError;

  factory AppConfig.fromEnvironment() {
    const environmentName = String.fromEnvironment(
      'WEALTHMATE_ENVIRONMENT',
      defaultValue: 'development',
    );
    const rawBaseUrl = String.fromEnvironment('WEALTHMATE_API_BASE_URL');
    final environment = _parseEnvironment(environmentName);
    return AppConfig._(
      environment: environment ?? AppEnvironment.development,
      apiBaseUrl: _normalizeBaseUrl(rawBaseUrl),
      environmentError: environment == null
          ? 'WEALTHMATE_ENVIRONMENT 必须是 development、test 或 production'
          : null,
    );
  }

  factory AppConfig.forTesting({
    required AppEnvironment environment,
    required String apiBaseUrl,
  }) {
    return AppConfig._(
      environment: environment,
      apiBaseUrl: _normalizeBaseUrl(apiBaseUrl),
    );
  }

  final AppEnvironment environment;
  final String? apiBaseUrl;
  final String? _environmentError;

  bool get isProduction => environment == AppEnvironment.production;

  String? get configurationError {
    if (_environmentError != null) return _environmentError;
    final value = apiBaseUrl;
    if (value == null) return null;
    final uri = Uri.tryParse(value);
    if (uri == null || uri.host.isEmpty) {
      return 'WEALTHMATE_API_BASE_URL 必须是包含主机名的完整 URL';
    }
    final scheme = uri.scheme.toLowerCase();
    if (scheme != 'http' && scheme != 'https') {
      return 'WEALTHMATE_API_BASE_URL 必须使用 HTTP 或 HTTPS';
    }
    if (isProduction && scheme != 'https') {
      return '正式环境的 WEALTHMATE_API_BASE_URL 必须使用 HTTPS';
    }
    return null;
  }

  static AppEnvironment? _parseEnvironment(String value) {
    return switch (value.trim().toLowerCase()) {
      'development' => AppEnvironment.development,
      'test' => AppEnvironment.test,
      'production' => AppEnvironment.production,
      _ => null,
    };
  }

  static String? _normalizeBaseUrl(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}
