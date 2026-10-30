import '../../domain/models.dart';

String money(double value) =>
    '¥${value.toStringAsFixed(value.truncateToDouble() == value ? 0 : 2)}';

/// '10月30日', with the year only when it is not the current year.
String ledgerDate(String isoDate, {DateTime? now}) {
  final parsed = DateTime.tryParse(isoDate);
  if (parsed == null) return isoDate;
  final monthDay = '${parsed.month}月${parsed.day}日';
  return parsed.year == (now ?? DateTime.now()).year
      ? monthDay
      : '${parsed.year}年$monthDay';
}

/// '2026年10月30日' — the detail page always shows the full date.
String ledgerFullDate(String isoDate) {
  final parsed = DateTime.tryParse(isoDate);
  if (parsed == null) return isoDate;
  return '${parsed.year}年${parsed.month}月${parsed.day}日';
}

/// Recorded clock time ('HH:mm'), or null when the record carries only a date.
///
/// Writers stamp midnight when no real time was captured, so 00:00 is treated
/// as "not recorded" rather than shown as a made-up time.
String? recordedTime(String? occurredAt) {
  if (occurredAt == null || occurredAt.isEmpty) return null;
  String hourMinute;
  if (occurredAt.length >= 16 && occurredAt[10] == 'T') {
    hourMinute = occurredAt.substring(11, 16);
  } else {
    final parsed = DateTime.tryParse(occurredAt);
    if (parsed == null) return null;
    final local = parsed.toLocal();
    hourMinute = '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
  }
  return hourMinute == '00:00' ? null : hourMinute;
}

String categoryName(FinanceState state, String? id) {
  return state.categories
          .where((item) => item.id == id)
          .map((item) => item.name)
          .firstOrNull ??
      '待确认';
}

String accountName(FinanceState state, String? id) {
  return state.accounts
          .where((item) => item.id == id)
          .map((item) => item.name)
          .firstOrNull ??
      '请选择账户';
}
