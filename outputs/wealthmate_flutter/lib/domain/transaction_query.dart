import 'models.dart';

/// Shared ledger, chart and budget selection. Business date determines the
/// period; the optional timestamp supplies ordering/time within that date.
class TransactionQuery {
  const TransactionQuery(
      {this.start,
      this.end,
      this.type,
      this.categoryIds,
      this.accountId,
      this.search = ''});
  final DateTime? start;
  final DateTime? end;
  final TransactionType? type;
  final Set<String>? categoryIds;
  final String? accountId;
  final String search;

  List<FinanceTransaction> select(FinanceState state) {
    final needle = search.trim().toLowerCase();
    final rows = state.transactions.where((row) {
      if (row.deletedAt != null || (type != null && row.type != type))
        return false;
      final date = businessDate(row);
      if (date == null ||
          (start != null && date.isBefore(day(start!))) ||
          (end != null && date.isAfter(day(end!)))) return false;
      if (categoryIds != null &&
          !categoryIds!.contains(row.categoryId ?? 'uncategorized'))
        return false;
      if (accountId != null && (row.accountId ?? 'unknown') != accountId)
        return false;
      final category = state.categories
              .where((c) => c.id == row.categoryId)
              .firstOrNull
              ?.name ??
          '';
      final account = state.accounts
              .where((a) => a.id == row.accountId)
              .firstOrNull
              ?.name ??
          '';
      return needle.isEmpty ||
          '${row.note} $category $account ${row.currency} ${row.amount}'
              .toLowerCase()
              .contains(needle);
    }).toList();
    rows.sort((a, b) {
      final date = businessDate(b)!.compareTo(businessDate(a)!);
      if (date != 0) return date;
      final time = (b.occurredAt ?? '').compareTo(a.occurredAt ?? '');
      return time != 0 ? time : b.id.compareTo(a.id);
    });
    return rows;
  }
}

DateTime day(DateTime date) => DateTime(date.year, date.month, date.day);
DateTime? businessDate(FinanceTransaction row) => DateTime.tryParse(
    row.date.substring(0, row.date.length < 10 ? row.date.length : 10));
double? cnyAmount(FinanceTransaction row) =>
    row.currency == 'CNY' ? row.cnyAmount ?? row.amount : row.cnyAmount;
double knownTotal(Iterable<FinanceTransaction> rows) =>
    (rows.fold<double>(0, (sum, row) => sum + (cnyAmount(row) ?? 0)) * 100)
        .round() /
    100;
int averageDays(DateTime start, DateTime end, DateTime now) {
  final first = day(start), last = day(end), today = day(now);
  if (first.isAfter(today)) return 0;
  final effective = last.isAfter(today) ? today : last;
  return effective.isBefore(first) ? 0 : effective.difference(first).inDays + 1;
}

double dailyAverage(
    double expense, DateTime start, DateTime end, DateTime now) {
  final days = averageDays(start, end, now);
  return days == 0 ? 0 : expense / days;
}
