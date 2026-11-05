/// Date text helpers shared by the ledger, quick-entry and storage layers.
///
/// The wire/storage contract is `YYYY-MM-DD`. Older quick-entry drafts could
/// persist human date text such as `2026年11月4日`; these helpers parse that
/// legacy text so an existing row is not silently dropped from the ledger.
library;

final RegExp _isoDatePattern = RegExp(r'^[0-9]{4}-[0-9]{2}-[0-9]{2}$');
final RegExp _dashDatePattern =
    RegExp(r'^([0-9]{4})-([0-9]{1,2})-([0-9]{1,2})(?:[T\s].*)?$');
final RegExp _slashDatePattern =
    RegExp(r'^([0-9]{4})/([0-9]{1,2})/([0-9]{1,2})(?:[T\s].*)?$');
final RegExp _dotDatePattern =
    RegExp(r'^([0-9]{4})\.([0-9]{1,2})\.([0-9]{1,2})(?:[T\s].*)?$');
final RegExp _chineseDatePattern =
    RegExp(r'^([0-9]{4})年([0-9]{1,2})月([0-9]{1,2})日?$');
final RegExp _compactDatePattern = RegExp(r'^([0-9]{4})([0-9]{2})([0-9]{2})$');

bool isIsoDate(Object? value) {
  if (value is! String || !_isoDatePattern.hasMatch(value)) return false;
  return DateTime.tryParse(value) != null;
}

/// Parses the common date forms the app has seen in local drafts and sync
/// payloads. Returns a local [DateTime] at midnight, or null when the text is
/// not a real calendar date.
DateTime? parseLooseDate(Object? value) {
  if (value is! String) return null;
  final text = value.trim();
  if (text.isEmpty) return null;

  final match = _dashDatePattern.firstMatch(text) ??
      _slashDatePattern.firstMatch(text) ??
      _dotDatePattern.firstMatch(text) ??
      _chineseDatePattern.firstMatch(text) ??
      _compactDatePattern.firstMatch(text);
  if (match == null) return null;

  final year = int.parse(match.group(1)!);
  final month = int.parse(match.group(2)!);
  final dayOfMonth = int.parse(match.group(3)!);
  if (year < 1 || month < 1 || month > 12 || dayOfMonth < 1 || dayOfMonth > 31) {
    return null;
  }
  final parsed = DateTime(year, month, dayOfMonth);
  // DateTime normalizes overflow (2026-02-30 -> 2026-03-02); reject it.
  if (parsed.year != year || parsed.month != month || parsed.day != dayOfMonth) {
    return null;
  }
  return parsed;
}

/// `YYYY-MM-DD` for a parseable date text, or null when it cannot be parsed.
String? normalizeDateText(Object? value) {
  final parsed = parseLooseDate(value);
  return parsed == null ? null : formatIsoDate(parsed);
}

String formatIsoDate(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-'
    '${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')}';
