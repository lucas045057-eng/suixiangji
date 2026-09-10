import '../../../domain/models.dart';
import 'auth_remote_data_source.dart';

class AuthRepository {
  AuthRepository({required this.remote});

  final AuthRemoteDataSource remote;

  Future<UserProfile> login(String username, String password) async {
    await remote.login(username, password);
    return fetchProfile();
  }

  Future<UserProfile> fetchProfile() => remote.fetchProfile();

  Future<UserProfile> updateProfile({
    String? displayName,
    String? username,
    List<QuickMemory>? quickMemories,
  }) =>
      remote.updateProfile(
        displayName: displayName,
        username: username,
        quickMemories: quickMemories,
      );

  Future<UserProfile> changePassword(
          String currentPassword, String newPassword) =>
      remote.changePassword(currentPassword, newPassword);

  Future<void> logout() => remote.logout();
}
