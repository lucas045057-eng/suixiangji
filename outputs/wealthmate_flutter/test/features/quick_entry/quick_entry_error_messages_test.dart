import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:wealthmate_flutter/core/database/local_state_session.dart';
import 'package:wealthmate_flutter/data/api_client.dart';
import 'package:wealthmate_flutter/data/local_repository.dart';
import 'package:wealthmate_flutter/data/sync_queue.dart';
import 'package:wealthmate_flutter/data/token_store.dart';
import 'package:wealthmate_flutter/domain/models.dart';
import 'package:wealthmate_flutter/features/quick_entry/data/quick_entry_remote_data_source.dart';
import 'package:wealthmate_flutter/features/quick_entry/data/quick_entry_repository.dart';
import 'package:wealthmate_flutter/features/quick_entry/domain/quick_entry_batch.dart';

const _text = '跟昨天差不多，吃饭32元';

class _AtomicStore implements AtomicKeyValueStore {
  final Map<String, String> values = <String, String>{};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;

  @override
  Future<void> writeBatch(Map<String, String> batch) async =>
      values.addAll(batch);
}

class _MemoryTokens implements TokenStore {
  String? value = 'token';

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String token) async => value = token;

  @override
  Future<void> clear() async => value = null;

  @override
  Future<String?> readLastVerifiedUserId() async => null;

  @override
  Future<void> writeLastVerifiedUserId(String userId) async {}

  @override
  Future<void> clearLastVerifiedUserId() async {}
}

/// Throws whatever the test handed in, and counts the calls so "no automatic
/// retry" stays observable.
class _ThrowingRemote extends QuickEntryRemoteDataSource {
  _ThrowingRemote(this.failure);

  final Object failure;
  int calls = 0;

  @override
  Future<Map<String, Object?>> createDrafts(Map<String, Object?> body) async {
    calls += 1;
    throw failure;
  }
}

FinanceState _state() => const FinanceState(
      preferredCurrency: 'CNY',
      defaultAccountId: 'alipay',
      accounts: [
        Account(id: 'alipay', name: '支付宝', type: AccountType.asset),
      ],
      categories: [Category(id: 'food', name: '餐饮')],
    );

QuickEntryRepository _repository(QuickEntryRemoteDataSource remote) =>
    QuickEntryRepository(
      session: LocalStateSession(
        local: LocalRepository(_AtomicStore()),
        queue: SyncQueue(),
      ),
      remote: remote,
    );

Future<String> _degradation(ApiFailure failure) async {
  final remote = _ThrowingRemote(failure);
  final repository = _repository(remote);
  final batch =
      await repository.createBatch(_text, _state(), now: DateTime(2026, 10, 28));
  expect(remote.calls, 1, reason: '云端失败不得自动重试');
  expect(batch.mode, QuickEntryParseMode.local);
  expect(batch.candidates, hasLength(1));
  expect(batch.candidates.single.draft.isInferred, isFalse);
  expect(batch.notices.first.code, 'cloud_unavailable');
  expect(batch.notices.first.message, repository.lastBatchDegradation);
  return repository.lastBatchDegradation!;
}

void main() {
  group('§5.4 machine codes become specific, safe messages', () {
    const messages = <String, String>{
      'invalid_context': '解析上下文有误',
      'text_too_large': '文本过长，请缩短后重试',
      'validation_error': '未通过云端校验',
      'rate_limited': '请求过于频繁',
      'llm_bad_response': '云端返回内容不可信',
      'llm_unavailable': '云端解析暂时不可用',
      'llm_timeout': '云端解析超时',
      'internal_error': '云端解析出现未预期错误',
    };

    for (final entry in messages.entries) {
      test('maps ${entry.key} to its own message', () async {
        final message = await _degradation(ApiFailure(
          ApiFailureKind.server,
          '云端不可用',
          statusCode: 502,
          code: entry.key,
        ));
        expect(message, contains(entry.value));
      });
    }

    test('rate_limited quotes the Retry-After delay', () async {
      final message = await _degradation(const ApiFailure(
        ApiFailureKind.validation,
        '操作太频繁，请稍后再试',
        statusCode: 429,
        code: 'rate_limited',
        retryAfter: Duration(seconds: 60),
      ));
      expect(message, contains('请求过于频繁，请稍后再试'));
      expect(message, contains('约 60 秒'));
    });

    test('rate_limited without a usable Retry-After omits the delay',
        () async {
      final message = await _degradation(const ApiFailure(
        ApiFailureKind.validation,
        '操作太频繁，请稍后再试',
        statusCode: 429,
        code: 'rate_limited',
      ));
      expect(message, contains('请求过于频繁'));
      expect(message, isNot(contains('秒')));
    });

    test('falls back to the status code when no code is present', () async {
      final tooLarge = await _degradation(const ApiFailure(
        ApiFailureKind.server,
        '同步服务暂时不可用',
        statusCode: 413,
      ));
      expect(tooLarge, contains('文本过长，请缩短后重试'));

      final limited = await _degradation(const ApiFailure(
        ApiFailureKind.validation,
        '操作太频繁，请稍后再试',
        statusCode: 429,
      ));
      expect(limited, contains('请求过于频繁'));
    });

    test('keeps the transport fallbacks for plain network failures', () async {
      final message = await _degradation(
          const ApiFailure(ApiFailureKind.network, '暂时无法连接同步服务'));
      expect(message, contains('暂时无法连接云端解析'));
    });

    test('shows a sanitized detail only when no machine code is known',
        () async {
      final withDetail = await _degradation(const ApiFailure(
        ApiFailureKind.server,
        '同步服务暂时不可用',
        statusCode: 400,
        detail: '日期与本地不一致',
      ));
      expect(withDetail, contains('日期与本地不一致'));

      final unknownCode = await _degradation(const ApiFailure(
        ApiFailureKind.server,
        '同步服务暂时不可用',
        statusCode: 500,
        code: 'some_future_code',
        detail: '内部细节',
      ));
      expect(unknownCode, isNot(contains('内部细节')));
    });
  });

  group('api transport extracts the error contract', () {
    QuickEntryRemoteDataSource remoteFor(
      int status,
      String body, {
      Map<String, String> headers = const {},
    }) =>
        QuickEntryRemoteDataSource(
          api: ApiClient(
            baseUrl: 'http://quick-entry.test',
            token: 'token',
            tokenStore: _MemoryTokens(),
            client: MockClient((request) async => http.Response(
                  body,
                  status,
                  headers: {
                    'content-type': 'application/json; charset=utf-8',
                    ...headers,
                  },
                )),
          ),
        );

    test('429 keeps the code and the Retry-After header', () async {
      final remote = remoteFor(
        429,
        '{"detail":"请求过多","code":"rate_limited"}',
        headers: {'retry-after': '60'},
      );
      final failure = await remote
          .createDrafts(const {})
          .then<Object?>((_) => null, onError: (Object error) => error);
      expect(failure, isA<ApiFailure>());
      final api = failure! as ApiFailure;
      expect(api.statusCode, 429);
      expect(api.code, 'rate_limited');
      expect(api.retryAfter, const Duration(seconds: 60));
      expect(api.detail, '请求过多');
    });

    test('413 keeps text_too_large', () async {
      final remote = remoteFor(
          413, '{"detail":"正文太长","code":"text_too_large"}');
      await expectLater(
        remote.createDrafts(const {}),
        throwsA(isA<ApiFailure>()
            .having((item) => item.code, 'code', 'text_too_large')
            .having((item) => item.statusCode, 'status', 413)),
      );
    });

    test('a non-JSON error body stays free of raw text', () async {
      final remote = remoteFor(500, '<html>boom</html>');
      await expectLater(
        remote.createDrafts(const {}),
        throwsA(isA<ApiFailure>()
            .having((item) => item.code, 'code', isNull)
            .having((item) => item.detail, 'detail', isNull)
            .having((item) => item.statusCode, 'status', 500)),
      );
    });

    test('rejects unsafe codes and sanitizes control characters', () async {
      final remote = remoteFor(
        400,
        '{"detail":"第一行\\n\\u0000第二行","code":"Not A Code"}',
      );
      await expectLater(
        remote.createDrafts(const {}),
        throwsA(isA<ApiFailure>()
            .having((item) => item.code, 'code', isNull)
            .having((item) => item.detail, 'detail', '第一行 第二行')),
      );
    });

    test('the repository turns a real 429 into the retry message', () async {
      final remote = remoteFor(
        429,
        '{"detail":"请求过多","code":"rate_limited"}',
        headers: {'retry-after': '30'},
      );
      final repository = _repository(remote);
      final batch = await repository.createBatch(_text, _state(),
          now: DateTime(2026, 10, 28));
      expect(repository.lastBatchDegradation, contains('约 30 秒'));
      expect(batch.mode, QuickEntryParseMode.local);
      expect(batch.candidates, hasLength(1));
    });
  });
}
