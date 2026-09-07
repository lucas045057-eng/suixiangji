import 'package:flutter_secure_storage/flutter_secure_storage.dart';

abstract class TokenStore {
  Future<String?> read();

  Future<void> write(String token);

  Future<void> clear();

  Future<String?> readLastVerifiedUserId() async => null;

  Future<void> writeLastVerifiedUserId(String userId) async {}

  Future<void> clearLastVerifiedUserId() async {}
}

class SecureTokenStore implements TokenStore {
  SecureTokenStore({FlutterSecureStorage? storage})
      : _storage = storage ?? FlutterSecureStorage();

  static const key = 'suixiangji.access_token';
  static const lastVerifiedUserIdKey = 'suixiangji.last_verified_user_id';
  final FlutterSecureStorage _storage;

  @override
  Future<String?> read() => _storage.read(key: key);

  @override
  Future<void> write(String token) => _storage.write(key: key, value: token);

  @override
  Future<void> clear() => _storage.delete(key: key);

  @override
  Future<String?> readLastVerifiedUserId() =>
      _storage.read(key: lastVerifiedUserIdKey);

  @override
  Future<void> writeLastVerifiedUserId(String userId) =>
      _storage.write(key: lastVerifiedUserIdKey, value: userId.trim());

  @override
  Future<void> clearLastVerifiedUserId() =>
      _storage.delete(key: lastVerifiedUserIdKey);
}
