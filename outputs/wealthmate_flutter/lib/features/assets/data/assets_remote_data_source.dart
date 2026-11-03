import '../../../core/network/api_response.dart';
import '../../../core/network/api_session.dart';
import '../../../domain/models.dart';

class AssetsRemoteDataSource {
  AssetsRemoteDataSource({required this.api});

  final ApiSession api;

  Future<List<Account>> fetchAccounts() async {
    final json = await requestMapWithSession(api, 'GET', '/accounts');
    return responseItems(json).map((item) => Account.fromJson(item)).toList();
  }

  Future<Account> updateAccount(Account account) async {
    final json = await requestMapWithSession(
      api,
      'PATCH',
      '/accounts/${account.id}',
      body: account.toJson(),
    );
    return Account.fromJson(json);
  }

  Future<Map<String, Object?>> fetchExchangeRate(String base,
      {String quote = 'CNY'}) {
    return requestMapWithSession(
      api,
      'GET',
      '/exchange/rates?base=$base&quote=$quote',
    );
  }

  Future<Map<String, Object?>> saveExchangeRate(Map<String, Object?> rate) {
    return requestMapWithSession(
      api,
      'POST',
      '/exchange/rates',
      body: rate,
    );
  }

  /// Creates an immutable balance adjustment through the dedicated endpoint.
  ///
  /// [expectedCurrentCny] is the raw six-decimal basis the client replayed;
  /// the server rejects the command with `balance_changed` when it no longer
  /// matches, so a stale target can never be applied silently.
  Future<FinanceTransaction> calibrate({
    required String accountId,
    required String clientOpId,
    required String adjustmentId,
    required String targetCny,
    required String effectiveOn,
    required String expectedCurrentCny,
  }) async {
    final json = await requestMapWithSession(
      api,
      'POST',
      '/assets/accounts/$accountId/calibration',
      body: {
        'client_op_id': clientOpId,
        'adjustment_id': adjustmentId,
        'target_cny': targetCny,
        'effective_on': effectiveOn,
        'expected_current_cny': expectedCurrentCny,
      },
    );
    return FinanceTransaction.fromJson(json);
  }

  Future<FinanceTransaction> reverseCalibration({
    required String accountId,
    required String transactionId,
    required String clientOpId,
    required String adjustmentId,
    required String effectiveOn,
  }) async {
    final json = await requestMapWithSession(
      api,
      'POST',
      '/assets/accounts/$accountId/calibrations/$transactionId/reverse',
      body: {
        'client_op_id': clientOpId,
        'adjustment_id': adjustmentId,
        'effective_on': effectiveOn,
      },
    );
    return FinanceTransaction.fromJson(json);
  }

  Future<Map<String, Object?>> fetchWealth({String? asOfDate}) =>
      requestMapWithSession(
        api,
        'GET',
        asOfDate == null ? '/wealth' : '/wealth?as_of_date=$asOfDate',
      );
}
