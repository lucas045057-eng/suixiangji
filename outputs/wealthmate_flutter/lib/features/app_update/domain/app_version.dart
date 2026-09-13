class AppVersion {
  const AppVersion({
    required this.latestVersion,
    required this.latestBuild,
    required this.minimumSupportedVersion,
    required this.minimumSupportedBuild,
    required this.forceUpdate,
    required this.downloadUrl,
    required this.releaseNotes,
  });

  factory AppVersion.fromJson(Map<String, Object?> json) {
    final latestVersion = _requiredString(json, 'latest_version');
    final latestBuild = _requiredBuild(json, 'latest_build');
    final minimumSupportedVersion =
        _requiredString(json, 'minimum_supported_version');
    final minimumSupportedBuild =
        _requiredBuild(json, 'minimum_supported_build');
    final forceUpdate = json['force_update'];
    final releaseNotes = json['release_notes'];
    final downloadUrl = json['download_url'];

    if (!_isDisplayVersion(latestVersion) ||
        !_isDisplayVersion(minimumSupportedVersion)) {
      throw const FormatException('版本号必须使用 major.minor.patch 格式');
    }
    if (forceUpdate is! bool) {
      throw const FormatException('force_update 必须是布尔值');
    }
    if (releaseNotes is! String) {
      throw const FormatException('release_notes 必须是字符串');
    }

    String? normalizedDownloadUrl;
    if (downloadUrl != null) {
      if (downloadUrl is! String || downloadUrl.trim().isEmpty) {
        throw const FormatException('download_url 必须是 HTTPS URL 或 null');
      }
      final uri = Uri.tryParse(downloadUrl.trim());
      if (uri == null ||
          uri.scheme.toLowerCase() != 'https' ||
          uri.host.isEmpty) {
        throw const FormatException('download_url 必须使用 HTTPS');
      }
      normalizedDownloadUrl = uri.toString();
    }

    return AppVersion(
      latestVersion: latestVersion,
      latestBuild: latestBuild,
      minimumSupportedVersion: minimumSupportedVersion,
      minimumSupportedBuild: minimumSupportedBuild,
      forceUpdate: forceUpdate,
      downloadUrl: normalizedDownloadUrl,
      releaseNotes: releaseNotes,
    );
  }

  final String latestVersion;
  final int latestBuild;
  final String minimumSupportedVersion;
  final int minimumSupportedBuild;
  final bool forceUpdate;
  final String? downloadUrl;
  final String releaseNotes;

  bool isUpdateAvailable(int localBuild) => latestBuild > localBuild;

  bool requiresForceUpdate(int localBuild) {
    if (!isUpdateAvailable(localBuild) || downloadUrl == null) return false;
    return forceUpdate || localBuild < minimumSupportedBuild;
  }

  static String _requiredString(Map<String, Object?> json, String key) {
    final value = json[key];
    if (value is! String || value.trim().isEmpty) {
      throw FormatException('$key 必须是非空字符串');
    }
    return value.trim();
  }

  static int _requiredBuild(Map<String, Object?> json, String key) {
    final value = json[key];
    if (value is! num || value is double && value != value.truncateToDouble()) {
      throw FormatException('$key 必须是正整数');
    }
    final build = value.toInt();
    if (build < 1) throw FormatException('$key 必须是正整数');
    return build;
  }

  static bool _isDisplayVersion(String value) => RegExp(
        r'^(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)$',
      ).hasMatch(value);
}
