/// Exact six-decimal CNY arithmetic for server-issued amount strings.
///
/// The calibration contract always speaks six-decimal strings. Parsing them
/// through `double` would reintroduce the representation noise the token was
/// introduced to remove, so the client keeps them as integer micro-units and
/// only converts to `double` at the UI boundary.
class CnyAmount {
  const CnyAmount._(this.micros);

  final BigInt micros;

  static final BigInt _scale = BigInt.from(1000000);
  static final RegExp _pattern = RegExp(r'^(-?)(\d+)(?:\.(\d{1,6}))?$');

  /// Parses `-?123.456789` (or a bare integer). Returns null for invalid input.
  static CnyAmount? tryParse(Object? raw) {
    if (raw is! String) return null;
    final value = raw.trim();
    final match = _pattern.firstMatch(value);
    if (match == null) return null;
    final fraction = (match.group(3) ?? '').padRight(6, '0');
    var micros = BigInt.parse(match.group(2)!) * _scale +
        BigInt.parse(fraction.isEmpty ? '0' : fraction);
    if (match.group(1) == '-') micros = -micros;
    return CnyAmount._(micros);
  }

  /// Converts a two-decimal UI target without accumulating binary noise.
  factory CnyAmount.fromDouble(double value) {
    if (!value.isFinite) {
      throw ArgumentError.value(value, 'value', '必须是有限数');
    }
    final cents = BigInt.from((value * 100).round());
    return CnyAmount._(cents * BigInt.from(10000));
  }

  double get asDouble => micros.toDouble() / 1000000;

  bool get isZero => micros == BigInt.zero;

  CnyAmount operator -(CnyAmount other) => CnyAmount._(micros - other.micros);

  String toFixed6() {
    final negative = micros.isNegative;
    final absolute = micros.abs();
    final whole = absolute ~/ _scale;
    final fraction = (absolute % _scale).toString().padLeft(6, '0');
    return '${negative ? '-' : ''}$whole.$fraction';
  }

  @override
  bool operator ==(Object other) =>
      other is CnyAmount && other.micros == micros;

  @override
  int get hashCode => micros.hashCode;
}
