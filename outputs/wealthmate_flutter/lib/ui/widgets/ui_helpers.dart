import '../../domain/models.dart';

String money(double value) =>
    '¥${value.toStringAsFixed(value.truncateToDouble() == value ? 0 : 2)}';

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

extension FirstOrNullExtension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
