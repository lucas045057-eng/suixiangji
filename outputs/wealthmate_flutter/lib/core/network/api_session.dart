import 'dart:async';

import 'api_transport.dart';

/// Session services shared by feature remote data sources.
abstract interface class ApiSession {
  ApiTransport get transport;
  String? get token;
  int get sessionGeneration;
  FutureOr<void> Function()? get onAuthExpired;
  set onAuthExpired(FutureOr<void> Function()? callback);

  int beginSession();
  void requireSession(int generation, [String? requestToken]);
  Future<void> saveToken(String value, {bool newSession = true});
  Future<void> saveLastVerifiedUserId(String userId);
  Future<void> logout();
}

Future<Map<String, Object?>> requestMapWithSession(
  ApiSession session,
  String method,
  String path, {
  Map<String, Object?>? body,
  bool includeAuth = true,
  bool allowStaleSuccess = false,
}) async {
  final generation = session.sessionGeneration;
  final requestToken = includeAuth ? session.token : null;
  final result = await session.transport.requestMap(
    method,
    path,
    body: body,
    includeAuth: includeAuth,
  );
  if (!allowStaleSuccess) session.requireSession(generation, requestToken);
  return result;
}
