import '../../../data/api_client.dart';
import '../../../domain/models.dart';

class QuickEntryRemoteDataSource {
  QuickEntryRemoteDataSource({this.api});

  final ApiClient? api;

  Future<AgentDraft> createDraft(String text) {
    final client = api;
    if (client == null) throw StateError('同步服务未配置');
    return client.postAgentDraft(text);
  }
}
