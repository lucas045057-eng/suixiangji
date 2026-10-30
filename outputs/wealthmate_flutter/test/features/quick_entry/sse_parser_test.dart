import 'package:flutter_test/flutter_test.dart';
import 'package:wealthmate_flutter/core/network/sse_parser.dart';

void main() {
  test('a data line split across chunks is not lost', () {
    final parser = SseParser();
    expect(parser.feed('event: item.preview\ndata: {"a":'), isEmpty);
    final frames = parser.feed('1}\n\n');
    expect(frames, hasLength(1));
    expect(frames.single.event, 'item.preview');
    expect(frames.single.data, '{"a":1}');
  });

  test('keeps a partial trailing line until its newline arrives', () {
    final parser = SseParser();
    parser.feed('id: r:1\nevent: completed\ndata: {"x"');
    final frames = parser.feed(':1}\n\n');
    expect(frames.single.data, '{"x":1}');
    expect(frames.single.id, 'r:1');
  });

  test('CRLF line endings and comment heartbeats', () {
    final parser = SseParser();
    final frames = parser.feed(': keep-alive\r\n\r\nevent: error\r\ndata: {}\r\n\r\n');
    expect(frames, hasLength(1));
    expect(frames.single.event, 'error');
    expect(frames.single.data, '{}');
  });

  test('multiple data lines join with newlines', () {
    final parser = SseParser();
    final frames = parser.feed('data: line1\ndata: line2\n\n');
    expect(frames.single.data, 'line1\nline2');
  });

  test('a comment-only block produces no frame', () {
    final parser = SseParser();
    expect(parser.feed(': keep-alive\n\n'), isEmpty);
  });

  test('several frames in one chunk are all returned in order', () {
    final parser = SseParser();
    final frames = parser.feed(
        'event: a\ndata: 1\n\nevent: b\ndata: 2\n\n');
    expect(frames.map((f) => f.event), ['a', 'b']);
    expect(frames.map((f) => f.data), ['1', '2']);
  });

  test('a field without a colon is treated as an empty value', () {
    final parser = SseParser();
    final frames = parser.feed('data\n\n');
    expect(frames.single.data, '');
  });
}
