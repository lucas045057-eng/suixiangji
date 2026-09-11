import '../../../domain/models.dart';
import 'auth_remote_data_source.dart';

class AuthRepository {
  AuthRepository({required this.remote});

  final AuthRemoteDataSource remote;

  Future<UserProfile> login(String username, String password) async {
    await remote.login(username, password);
    return fetchProfile();
  }

  Future<UserProfile> register({
    required String username,
    required String password,
    String? displayName,
    required String inviteCode,
  }) async {
    await remote.register(
      username: username,
      password: password,
      displayName: displayName,
      inviteCode: inviteCode,
    );
    return fetchProfile();
  }

  Future<void> deleteAccount(String currentPassword) =>
      remote.deleteAccount(currentPassword);

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
