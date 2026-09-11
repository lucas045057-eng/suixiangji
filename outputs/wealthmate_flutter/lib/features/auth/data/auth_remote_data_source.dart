import '../../../data/api_client.dart';
import '../../../domain/models.dart';

class AuthRemoteDataSource {
  AuthRemoteDataSource({required this.api});

  final ApiClient api;

  Future<Map<String, Object?>> login(String username, String password) =>
      api.login(username, password);

  Future<Map<String, Object?>> register({
    required String username,
    required String password,
    String? displayName,
    required String inviteCode,
  }) =>
      api.register(
        username: username,
        password: password,
        displayName: displayName,
        inviteCode: inviteCode,
      );

  Future<void> deleteAccount(String currentPassword) =>
      api.deleteAccount(currentPassword);

  Future<UserProfile> fetchProfile() => api.fetchProfile();

  Future<UserProfile> updateProfile({
    String? displayName,
    String? username,
    List<QuickMemory>? quickMemories,
  }) =>
      api.updateProfile(
        displayName: displayName,
        username: username,
        quickMemories: quickMemories,
      );

  Future<UserProfile> changePassword(
          String currentPassword, String newPassword) =>
      api.changePassword(currentPassword, newPassword);

  Future<void> logout() => api.logout();
}
