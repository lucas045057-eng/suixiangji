import '../../../domain/models.dart';

class AuthSession {
  const AuthSession({this.profile});

  final UserProfile? profile;

  bool get isAuthenticated => profile != null;
}
