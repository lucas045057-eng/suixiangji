import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../data/api_client.dart';
import '../../../domain/models.dart';
import '../data/auth_repository.dart';
import '../domain/auth_session.dart';

class AuthStore extends ChangeNotifier {
  AuthStore({required this.repository}) {
    repository.remote.api.onAuthExpired = _handleAuthExpired;
  }

  final AuthRepository repository;
  AuthSession _session = const AuthSession();
  String? _message;
  FutureOr<void> Function()? onAuthExpired;

  UserProfile? get profile => _session.profile;

  bool get isAuthenticated =>
      repository.remote.api.token?.isNotEmpty == true &&
      _session.isAuthenticated;

  String? get message => _message;

  Future<bool> login(String username, String password) async {
    try {
      _session =
          AuthSession(profile: await repository.login(username, password));
      _message = null;
      notifyListeners();
      return true;
    } on ApiFailure catch (failure) {
      _message = failure.message;
      notifyListeners();
      return false;
    }
  }

  Future<bool> loadProfile() async {
    if (repository.remote.api.token?.isNotEmpty != true) return false;
    try {
      _session = AuthSession(profile: await repository.fetchProfile());
      _message = null;
      notifyListeners();
      return true;
    } on ApiFailure catch (failure) {
      _message = failure.message;
      notifyListeners();
      return false;
    }
  }

  Future<bool> updateProfile({
    String? displayName,
    String? username,
    List<QuickMemory>? quickMemories,
  }) async {
    try {
      _session = AuthSession(
        profile: await repository.updateProfile(
          displayName: displayName,
          username: username,
          quickMemories: quickMemories,
        ),
      );
      _message = '用户资料已更新';
      notifyListeners();
      return true;
    } on ApiFailure catch (failure) {
      _message = failure.message;
      notifyListeners();
      return false;
    }
  }

  Future<bool> changePassword(
      String currentPassword, String nextPassword) async {
    try {
      _session = AuthSession(
        profile: await repository.changePassword(currentPassword, nextPassword),
      );
      _message = '密码已更新，其他设备需要重新登录';
      notifyListeners();
      return true;
    } on ApiFailure catch (failure) {
      _message = failure.message;
      notifyListeners();
      return false;
    }
  }

  Future<void> logout() async {
    await repository.logout();
    clearSession();
  }

  void clearSession() {
    _session = const AuthSession();
    _message = null;
    notifyListeners();
  }

  Future<void> _handleAuthExpired() async {
    clearSession();
    await onAuthExpired?.call();
  }
}
