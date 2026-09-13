import '../../../core/network/api_session.dart';
import '../../../domain/models.dart';

class QuickEntryRemoteDataSource {
  QuickEntryRemoteDataSource({this.api});

  final ApiSession? api;

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
