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
  int _sessionGeneration = 0;

  UserProfile? get profile => _session.profile;

  bool get isAuthenticated =>
      repository.remote.api.token?.isNotEmpty == true &&
      _session.isAuthenticated;

  String? get message => _message;

  Future<bool> login(String username, String password) async {
    final requestGeneration = ++_sessionGeneration;
    try {
      final profile = await repository.login(username, password);
      if (requestGeneration != _sessionGeneration) return false;
      _session = AuthSession(profile: profile);
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
    final requestGeneration = _sessionGeneration;
    try {
      final profile = await repository.fetchProfile();
      if (requestGeneration != _sessionGeneration) return false;
      _session = AuthSession(profile: profile);
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
    final requestGeneration = _sessionGeneration;
    try {
      final profile = await repository.updateProfile(
        displayName: displayName,
        username: username,
        quickMemories: quickMemories,
      );
      if (requestGeneration != _sessionGeneration) return false;
      _session = AuthSession(profile: profile);
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
    final requestGeneration = _sessionGeneration;
    try {
      final profile =
          await repository.changePassword(currentPassword, nextPassword);
      if (requestGeneration != _sessionGeneration) return false;
      _session = AuthSession(profile: profile);
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
    _sessionGeneration++;
    await repository.logout();
    _clearSession();
  }

  void clearSession() {
    _sessionGeneration++;
    _clearSession();
  }

  void _clearSession() {
    _session = const AuthSession();
    _message = null;
    notifyListeners();
  }

  Future<void> _handleAuthExpired() async {
    clearSession();
    await onAuthExpired?.call();
  }
}
