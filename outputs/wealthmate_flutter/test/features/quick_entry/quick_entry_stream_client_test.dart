import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:wealthmate_flutter/core/network/api_transport.dart';
import 'package:wealthmate_flutter/features/quick_entry/data/quick_entry_stream_client.dart';
import 'package:wealthmate_flutter/features/quick_entry/domain/quick_entry_stream.dart';

const _requestId = 'sxj-test-request';

String _frame(
  int seq,
  String type, {
  int attempt = 1,
  Map<String, Object?> data = const {},
  String requestId = _requestId,
}) =>
    'id: $requestId:$seq\n'
    'event: $type\n'
    'data: ${jsonEncode({
          'stream_version': 1,
          'request_id': requestId,
          'seq': seq,
          'attempt': attempt,
          'type': type,
          'data': data,
        })}\n\n';

class _FakeClient extends http.BaseClient {
  _FakeClient(this.respond);

  final http.StreamedResponse Function(http.BaseRequest request) respond;
  int closes = 0;
  final List<String> paths = <String>[];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    paths.add(request.url.path);
    return respond(request);
  }

  @override
  void close() {
    closes += 1;
  }
}

Future<List<QuickEntryStreamEvent>> _collect(
  Stream<QuickEntryStreamEvent> stream,
) =>
    stream.toList();

void main() {
  late StreamController<List<int>> body;

  setUp(() => body = StreamController<List<int>>());

  tearDown(() {
    // A controller nobody listened to never completes its `done` future, so
    // awaiting close here would hang the test.
    if (!body.isClosed) unawaited(body.close());
  });

  QuickEntryStreamClient clientWith(http.Client client) =>
      QuickEntryStreamClient(
        baseUrl: 'https://quick-entry.test',
        client: client,
        tokenProvider: () => 'token',
      );

  test('splits frames across chunks and keeps order', () async {
    final fake = _FakeClient((_) => http.StreamedResponse(body.stream, 200));
    final client = clientWith(fake);
    final future = _collect(client.open(
      const {'schema_version': 1},
      requestId: _requestId,
      abortTrigger: Completer<void>().future,
    ));
    final text = _frame(1, 'session.started') +
        _frame(2, 'generation.started') +
        _frame(3, 'item.preview') +
        _frame(4, 'completed', data: {'result': <String, Object?>{}});
    // Deliberately split inside a data line.
    body.add(utf8.encode(text.substring(0, 20)));
    await pumpEventQueue();
    body.add(utf8.encode(text.substring(20)));
    await body.close();
    final events = await future;
    expect(events.map((e) => e.type),
        ['session.started', 'generation.started', 'item.preview', 'completed']);
    expect(events.map((e) => e.seq), [1, 2, 3, 4]);
    expect(fake.paths, ['/agent/drafts/stream']);
    expect(fake.closes, 0, reason: '共享 client 不允许被关闭');
  });

  test('heartbeats produce no events', () async {
    final fake = _FakeClient((_) => http.StreamedResponse(body.stream, 200));
    final future = _collect(clientWith(fake).open(
      const {},
      requestId: _requestId,
      abortTrigger: Completer<void>().future,
    ));
    body.add(utf8.encode(': keep-alive\n\n'));
    await pumpEventQueue();
    body.add(utf8.encode(_frame(1, 'session.started')));
    body.add(utf8.encode(_frame(2, 'completed', data: {'result': {}})));
    await body.close();
    final events = await future;
    expect(events.map((e) => e.type), ['session.started', 'completed']);
  });

  test('a terminal frame stops the stream without closing the client',
      () async {
    final fake = _FakeClient((_) => http.StreamedResponse(body.stream, 200));
    final events = <QuickEntryStreamEvent>[];
    final subscription = clientWith(fake)
        .open(const {}, requestId: _requestId, abortTrigger: Completer<void>().future)
        .listen(events.add);
    body.add(utf8.encode(_frame(1, 'completed', data: {'result': {}})));
    await pumpEventQueue();
    body.add(utf8.encode(_frame(2, 'session.started')));
    await pumpEventQueue();
    await subscription.cancel();
    expect(events.map((e) => e.type), ['completed']);
    expect(fake.closes, 0);
  });

  test('non-2xx keeps the machine code and Retry-After', () async {
    final fake = _FakeClient((_) => http.StreamedResponse(
          Stream<List<int>>.value(utf8.encode(
              '{"detail":"请求过多","code":"rate_limited"}')),
          429,
          headers: {'retry-after': '30'},
        ));
    await expectLater(
      _collect(clientWith(fake).open(const {},
          requestId: _requestId, abortTrigger: Completer<void>().future)),
      throwsA(isA<ApiFailure>()
          .having((e) => e.statusCode, 'status', 429)
          .having((e) => e.code, 'code', 'rate_limited')
          .having((e) => e.retryAfter, 'retry', const Duration(seconds: 30))),
    );
  });

  test('404 surfaces as ApiFailure so the caller can fall back once',
      () async {
    final fake = _FakeClient((_) => http.StreamedResponse(
          Stream<List<int>>.value(utf8.encode('{"detail":"Not Found"}')),
          404,
        ));
    await expectLater(
      _collect(clientWith(fake).open(const {},
          requestId: _requestId, abortTrigger: Completer<void>().future)),
      throwsA(isA<ApiFailure>()
          .having((e) => e.statusCode, 'status', 404)),
    );
  });

  test('a request_id mismatch is a protocol failure', () async {
    final fake = _FakeClient((_) => http.StreamedResponse(body.stream, 200));
    final future = _collect(clientWith(fake).open(const {},
        requestId: _requestId, abortTrigger: Completer<void>().future));
    body.add(utf8.encode(_frame(1, 'session.started', requestId: 'other-id')));
    await body.close();
    await expectLater(future,
        throwsA(isA<QuickEntryStreamProtocolError>()));
  });

  test('a seq gap is a protocol failure', () async {
    final fake = _FakeClient((_) => http.StreamedResponse(body.stream, 200));
    final future = _collect(clientWith(fake).open(const {},
        requestId: _requestId, abortTrigger: Completer<void>().future));
    body.add(utf8.encode(_frame(1, 'session.started')));
    body.add(utf8.encode(_frame(3, 'generation.started')));
    await body.close();
    await expectLater(future,
        throwsA(isA<QuickEntryStreamProtocolError>()));
  });

  test('a duplicate seq (late replay) is a protocol failure', () async {
    final fake = _FakeClient((_) => http.StreamedResponse(body.stream, 200));
    final future = _collect(clientWith(fake).open(const {},
        requestId: _requestId, abortTrigger: Completer<void>().future));
    body.add(utf8.encode(_frame(1, 'session.started')));
    body.add(utf8.encode(_frame(1, 'session.started')));
    await body.close();
    await expectLater(future,
        throwsA(isA<QuickEntryStreamProtocolError>()));
  });

  test('an attempt regression is a protocol failure', () async {
    final fake = _FakeClient((_) => http.StreamedResponse(body.stream, 200));
    final future = _collect(clientWith(fake).open(const {},
        requestId: _requestId, abortTrigger: Completer<void>().future));
    body.add(utf8.encode(_frame(1, 'session.started')));
    body.add(utf8.encode(_frame(2, 'attempt.restarted', attempt: 2)));
    body.add(utf8.encode(_frame(3, 'generation.started', attempt: 1)));
    await body.close();
    await expectLater(future,
        throwsA(isA<QuickEntryStreamProtocolError>()));
  });

  test('an attempt jump without attempt.restarted is a protocol failure',
      () async {
    final fake = _FakeClient((_) => http.StreamedResponse(body.stream, 200));
    final future = _collect(clientWith(fake).open(const {},
        requestId: _requestId, abortTrigger: Completer<void>().future));
    body.add(utf8.encode(_frame(1, 'generation.started', attempt: 2)));
    await body.close();
    await expectLater(future,
        throwsA(isA<QuickEntryStreamProtocolError>()));
  });

  test('event and type must agree', () async {
    final fake = _FakeClient((_) => http.StreamedResponse(body.stream, 200));
    final future = _collect(clientWith(fake).open(const {},
        requestId: _requestId, abortTrigger: Completer<void>().future));
    body.add(utf8.encode(
        'id: $_requestId:1\nevent: item.preview\ndata: ${jsonEncode({
          'stream_version': 1,
          'request_id': _requestId,
          'seq': 1,
          'attempt': 1,
          'type': 'session.started',
          'data': <String, Object?>{},
        })}\n\n'));
    await body.close();
    await expectLater(future,
        throwsA(isA<QuickEntryStreamProtocolError>()));
  });

  test('a wrong stream_version is a protocol failure', () async {
    final fake = _FakeClient((_) => http.StreamedResponse(body.stream, 200));
    final future = _collect(clientWith(fake).open(const {},
        requestId: _requestId, abortTrigger: Completer<void>().future));
    body.add(utf8.encode(
        'event: session.started\ndata: ${jsonEncode({
          'stream_version': 2,
          'request_id': _requestId,
          'seq': 1,
          'attempt': 1,
          'type': 'session.started',
          'data': <String, Object?>{},
        })}\n\n'));
    await body.close();
    await expectLater(future,
        throwsA(isA<QuickEntryStreamProtocolError>()));
  });

  test('EOF without a terminal event is an interrupted stream', () async {
    final fake = _FakeClient((_) => http.StreamedResponse(body.stream, 200));
    final future = _collect(clientWith(fake).open(const {},
        requestId: _requestId, abortTrigger: Completer<void>().future));
    body.add(utf8.encode(_frame(1, 'generation.started')));
    await body.close();
    await expectLater(
      future,
      throwsA(isA<QuickEntryStreamFailure>()
          .having((e) => e.code, 'code', 'stream_interrupted')),
    );
  });

  test('cancel maps to QuickEntryStreamCancelled and never closes the client',
      () async {
    final fake = _FakeClient((_) => http.StreamedResponse(body.stream, 200));
    final abort = Completer<void>();
    final future = _collect(clientWith(fake).open(const {},
        requestId: _requestId, abortTrigger: abort.future));
    body.add(utf8.encode(_frame(1, 'generation.started')));
    await pumpEventQueue();
    abort.complete();
    body.addError(http.ClientException('aborted'));
    await expectLater(
        future, throwsA(isA<QuickEntryStreamCancelled>()));
    expect(fake.closes, 0);
  });

  test('an unconfigured base url fails before sending', () async {
    final fake = _FakeClient((_) => http.StreamedResponse(body.stream, 200));
    final client = QuickEntryStreamClient(
      baseUrl: '',
      client: fake,
      tokenProvider: () => null,
    );
    await expectLater(
      _collect(client.open(const {},
          requestId: _requestId, abortTrigger: Completer<void>().future)),
      throwsA(isA<ApiFailure>()
          .having((e) => e.kind, 'kind', ApiFailureKind.configuration)),
    );
    expect(fake.paths, isEmpty);
  });
}
