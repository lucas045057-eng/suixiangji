import '../../../core/network/api_session.dart';
import '../../../domain/models.dart';
import '../domain/quick_entry_stream.dart';
import 'quick_entry_stream_client.dart';

class QuickEntryRemoteDataSource {
  QuickEntryRemoteDataSource({this.api});

  final ApiSession? api;

  /// Streaming needs a configured session; fakes and offline builds keep the
  /// single-response endpoint.
  bool get supportsStreaming => api != null;

  /// Multi-card parse. The response is returned raw on purpose: only the
  /// client-side whitelist may turn it into candidate cards.
  Future<Map<String, Object?>> createDrafts(
      Map<String, Object?> body) async {
    final session = api;
    if (session == null) throw StateError('同步服务未配置');
    return requestMapWithSession(session, 'POST', '/agent/drafts', body: body);
  }

  /// Same request body as [createDrafts], delivered as validated SSE events.
  Stream<QuickEntryStreamEvent> createDraftsStream(
    Map<String, Object?> body, {
    required String requestId,
    required Future<void> abortTrigger,
  }) {
    final session = api;
    if (session == null) throw StateError('同步服务未配置');
    return QuickEntryStreamClient(
      baseUrl: session.transport.baseUrl,
      client: session.transport.client,
      tokenProvider: () => session.token,
      onAuthExpired: session.onAuthExpired,
    ).open(body, requestId: requestId, abortTrigger: abortTrigger);
  }

  Future<AgentDraft> createDraft(String text) async {
    final session = api;
    if (session == null) throw StateError('同步服务未配置');
    final json = await requestMapWithSession(
      session,
      'POST',
      '/agent/draft',
      body: {'text': text},
    );
    return AgentDraft(
      amount: (json['amount'] as num?)?.toDouble() ?? 0,
      type: transactionTypeFromJson(json['type']),
      categoryId: json['category_id'] as String?,
      accountId: json['account_id'] as String?,
      date: json['date'] as String? ?? '',
      note: json['note'] as String? ?? text,
      currency: json['currency'] as String? ?? 'CNY',
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0,
      missingFacts:
          (json['missing_facts'] as List<Object?>?)?.cast<String>() ??
              const <String>[],
    );
  }
}
