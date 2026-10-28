import 'dart:convert';

/// Small, dependency-free helpers for the `/agent/drafts` wire contract.
/// Money crosses the wire as decimal strings, never as binary floats.
final RegExp _moneyPattern = RegExp(r'^[0-9]{1,20}(?:\.[0-9]{1,6})?$');
final RegExp _isoDatePattern = RegExp(r'^[0-9]{4}-[0-9]{2}-[0-9]{2}$');

double? parseMoneyText(Object? value) {
  if (value is! String || !_moneyPattern.hasMatch(value)) return null;
  return double.tryParse(value);
}

String moneyText(double value) {
  final safe = value.isFinite ? value : 0.0;
  return safe.toStringAsFixed(2);
}

/// Exact value of a wire money string, scaled by 10^6 (the finest fraction the
/// contract allows). Null when the text is not a wire money string.
///
/// The contract requires Decimal semantics (`132.50 - 0.00 - 45.00` must equal
/// `87.50` exactly), so arithmetic never goes through `double`.
BigInt? moneyUnits(Object? value) {
  if (value is! String || !_moneyPattern.hasMatch(value)) return null;
  final dot = value.indexOf('.');
  final whole = dot < 0 ? value : value.substring(0, dot);
  final fraction = dot < 0 ? '' : value.substring(dot + 1);
  return BigInt.parse(whole) * BigInt.from(1000000) +
      BigInt.parse(fraction.padRight(6, '0'));
}

bool isIsoDate(Object? value) {
  if (value is! String || !_isoDatePattern.hasMatch(value)) return false;
  return DateTime.tryParse(value) != null;
}

String dateKey(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';

/// Unicode code point length. The wire contract uses code point offsets while
/// Dart string indices are UTF-16 code units, so offsets must be converted
/// before a slice is compared with the quote.
int codePointLength(String text) => text.runes.length;

String codePointSlice(String text, int start, int end) {
  if (start < 0 || end < start) return '';
  return String.fromCharCodes(text.runes.skip(start).take(end - start));
}

/// Stable, non-cryptographic 64-bit fingerprint used only to detect that the
/// ledger aggregate changed. The server treats it as an opaque string.
String aggregateFingerprint(String canonicalJson) {
  final mask = (BigInt.one << 64) - BigInt.one;
  var hash = BigInt.parse('cbf29ce484222325', radix: 16);
  final prime = BigInt.parse('100000001b3', radix: 16);
  for (final byte in utf8.encode(canonicalJson)) {
    hash = ((hash ^ BigInt.from(byte)) * prime) & mask;
  }
  return 'fnv1a64:${hash.toRadixString(16).padLeft(16, '0')}';
}
