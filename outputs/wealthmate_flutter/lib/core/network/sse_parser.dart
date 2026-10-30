/// Minimal Server-Sent Events parser.
///
/// Line buffered on purpose: a `data:` line can be split across network
/// chunks (measured as the top framing bug in the P0 probe), so a partial
/// trailing line is kept until its newline arrives.
library;

class SseFrame {
  const SseFrame({this.id, this.event, required this.data});

  final String? id;
  final String? event;
  final String data;
}

class SseParser {
  final StringBuffer _pending = StringBuffer();
  String? _id;
  String? _event;
  final List<String> _data = <String>[];

  /// Consumes one decoded chunk and returns every frame it completed.
  List<SseFrame> feed(String chunk) {
    if (chunk.isEmpty) return const <SseFrame>[];
    _pending.write(chunk);
    final text = _pending.toString();
    var start = 0;
    final frames = <SseFrame>[];
    while (true) {
      final index = text.indexOf('\n', start);
      if (index < 0) break;
      var line = text.substring(start, index);
      start = index + 1;
      if (line.endsWith('\r')) line = line.substring(0, line.length - 1);
      final frame = _consumeLine(line);
      if (frame != null) frames.add(frame);
    }
    _pending
      ..clear()
      ..write(text.substring(start));
    return frames;
  }

  SseFrame? _consumeLine(String line) {
    if (line.isEmpty) {
      if (_data.isEmpty) {
        _id = null;
        _event = null;
        return null;
      }
      final frame =
          SseFrame(id: _id, event: _event, data: _data.join('\n'));
      _id = null;
      _event = null;
      _data.clear();
      return frame;
    }
    // `: keep-alive` — a comment, never business progress.
    if (line.startsWith(':')) return null;
    final colon = line.indexOf(':');
    final field = colon < 0 ? line : line.substring(0, colon);
    var value = colon < 0 ? '' : line.substring(colon + 1);
    if (value.startsWith(' ')) value = value.substring(1);
    switch (field) {
      case 'id':
        _id = value;
      case 'event':
        _event = value;
      case 'data':
        _data.add(value);
      default:
        break; // `retry:` and unknown fields are ignored.
    }
    return null;
  }
}
