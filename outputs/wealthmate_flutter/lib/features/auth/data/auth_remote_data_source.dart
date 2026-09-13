import '../../../core/network/api_session.dart';
import '../../../core/network/api_transport.dart';
import '../../../domain/models.dart';

class AuthRemoteDataSource {
  AuthRemoteDataSource({required this.api});

  final ApiSession api;

  Future<Map<String, Object?>> login(String username, String password) async {
    final generation = api.beginSession();
    final result = await requestMapWithSession(
      api,
      'POST',
      '/auth/login',
      body: {'username': username, 'password': password},
      includeAuth: false,
    );
    api.requireSession(generation);
    final accessToken =
        result['access_token'] as String? ?? result['token'] as String?;
    if (accessToken == null || accessToken.isEmpty) {
      throw const ApiFailure(ApiFailureKind.server, '登录响应中没有访问令牌');
    }
    await api.saveToken(accessToken);
    return result;
  }

  Future<Map<String, Object?>> register({
    required String username,
    required String password,
    String? displayName,
    required String inviteCode,
  }) async {
    final generation = api.beginSession();
    final result = await requestMapWithSession(
      api,
      'POST',
      '/auth/register',
      includeAuth: false,
      body: {
        'username': username.trim(),
        'password': password,
        if (displayName != null && displayName.trim().isNotEmpty)
          'display_name': displayName.trim(),
        'invite_code': inviteCode.trim(),
      },
    );
    api.requireSession(generation);
    final accessToken = result['access_token'] as String?;
    if (accessToken == null || accessToken.isEmpty) {
      throw const ApiFailure(ApiFailureKind.server, '注册响应异常，请尝试登录');
    }
    await api.saveToken(accessToken);
    return result;
  }

  Future<void> deleteAccount(String currentPassword) async {
    final result = await requestMapWithSession(
      api,
      'DELETE',
      '/auth/me',
      body: {'current_password': currentPassword},
      allowStaleSuccess: true,
    );
    if (result['deleted'] != true) {
      throw const ApiFailure(ApiFailureKind.server, '未能确认删除结果，请稍后重试');
    }
  }

  Future<UserProfile> fetchProfile() async {
    final generation = api.sessionGeneration;
    final json = await requestMapWithSession(api, 'GET', '/auth/me');
    api.requireSession(generation);
    final profile = UserProfile.fromJson(json);
    if (profile.id.trim().isEmpty) {
      throw const ApiFailure(ApiFailureKind.server, '无法确认账户身份，请重新登录');
    }
    await api.saveLastVerifiedUserId(profile.id);
    api.requireSession(generation);
    return profile;
  }

  Future<UserProfile> updateProfile({
    String? displayName,
    String? username,
    List<QuickMemory>? quickMemories,
  }) async {
    final generation = api.sessionGeneration;
    final json = await requestMapWithSession(api, 'PATCH', '/auth/me', body: {
      if (displayName != null) 'display_name': displayName,
      if (username != null) 'username': username,
      if (quickMemories != null)
        'quick_memories': quickMemories.map((item) => item.toJson()).toList(),
    });
    final accessToken = json['access_token'] as String?;
    if (accessToken != null && accessToken.isNotEmpty) {
      await api.saveToken(accessToken, newSession: false);
    }
    api.requireSession(generation);
    return UserProfile.fromJson(json);
  }

  Future<UserProfile> changePassword(
      String currentPassword, String newPassword) async {
    final generation = api.sessionGeneration;
    final json = await requestMapWithSession(api, 'POST', '/auth/password',
        body: {
      'current_password': currentPassword,
      'new_password': newPassword,
    });
    final accessToken = json['access_token'] as String?;
    if (accessToken != null && accessToken.isNotEmpty) {
      await api.saveToken(accessToken, newSession: false);
    }
    api.requireSession(generation);
    return UserProfile.fromJson(json);
  }

  Future<void> logout() => api.logout();
}
