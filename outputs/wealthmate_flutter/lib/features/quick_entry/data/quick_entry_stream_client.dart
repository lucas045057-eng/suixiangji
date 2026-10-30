import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../core/network/api_transport.dart';
import '../../../core/network/sse_parser.dart';
import '../domain/quick_entry_stream.dart';

/// `POST /agent/drafts/stream` over SSE.
///
/// Uses the shared client and one [http.AbortableRequest] per generation.
/// Closing the shared client would kill every concurrent request (cronet_http
/// `close()` shuts the engine), so cancellation is abort-only.
class QuickEntryStreamClient {
  QuickEntryStreamClient({
    required this.baseUrl,
    required this.client,
    required this.tokenProvider,
    this.onAuthExpired,
    this.path = '/agent/drafts/stream',
    this.idleTimeout = const Duration(seconds: 90),
  });

  final String? baseUrl;
  final http.Client client;
  final TokenProvider tokenProvider;
  final FutureOr<void> Function()? onAuthExpired;
  final String path;

  /// Server heartbeats every 12s; a longer silence means a dead connection.
  final Duration idleTimeout;

  Stream<QuickEntryStreamEvent> open(
    Map<String, Object?> body, {
    required String requestId,
    required Future<void> abortTrigger,
  }) async* {
    final root = baseUrl?.trim();
    if (root == null || root.isEmpty) {
      throw const ApiFailure(ApiFailureKind.configuration, '同步服务尚未配置');
    }
    final uri = Uri.parse(root.endsWith('/')
        ? '${root.substring(0, root.length - 1)}$path'
        : '$root$path');
    final token = tokenProvider();
    var aborted = false;
    unawaited(abortTrigger.then((_) => aborted = true));

    final request = http.AbortableRequest('POST', uri, abortTrigger: abortTrigger);
    request.headers['content-type'] = 'application/json';
    request.headers['accept'] = 'text/event-stream';
    request.headers['cache-control'] = 'no-cache';
    if (token != null && token.isNotEmpty) {
      request.headers['authorization'] = 'Bearer $token';
    }
    request.body = jsonEncode(body);

    http.StreamedResponse response;
    try {
      response = await client.send(request);
    } on http.RequestAbortedException {
      throw const QuickEntryStreamCancelled();
    } on ApiFailure {
      rethrow;
    } on Object {
      if (aborted) throw const QuickEntryStreamCancelled();
      throw const ApiFailure(ApiFailureKind.network, '暂时无法连接同步服务');
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      final text = await response.stream.bytesToString();
      if (response.statusCode == 401 &&
          token != null &&
          token.isNotEmpty &&
          tokenProvider() == token) {
        await onAuthExpired?.call();
      }
      throw ApiTransport.failureForResponse(
        response.statusCode,
        path,
        body: text,
        headers: response.headers,
      );
    }

    final parser = SseParser();
    final guard = QuickEntryStreamEnvelopeGuard(requestId: requestId);
    try {
      await for (final chunk
          in response.stream.timeout(idleTimeout).transform(utf8.decoder)) {
        for (final frame in parser.feed(chunk)) {
          final event = guard.accept(frame);
          if (event == null) continue;
          yield event;
          if (event.isTerminal) return;
        }
      }
    } on QuickEntryStreamProtocolError {
      rethrow;
    } on TimeoutException {
      throw const QuickEntryStreamFailure('stream_interrupted');
    } on http.RequestAbortedException {
      throw const QuickEntryStreamCancelled();
    } on Object {
      if (aborted) throw const QuickEntryStreamCancelled();
      throw const QuickEntryStreamFailure('stream_interrupted');
    }
    if (!guard.sawTerminal) {
      if (aborted) throw const QuickEntryStreamCancelled();
      throw const QuickEntryStreamFailure('stream_interrupted');
    }
  }
}
