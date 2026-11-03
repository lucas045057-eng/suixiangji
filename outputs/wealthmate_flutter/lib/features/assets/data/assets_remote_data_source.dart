import '../../../core/network/api_response.dart';
import '../../../core/network/api_session.dart';
import '../../../core/network/api_transport.dart';
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

  /// Issues a short-lived server-signed proof of the account's CNY book
  /// balance at [effectiveOn]. The token, not a client replay, becomes the
  /// calibration basis.
  Future<BalanceBasis> fetchBalanceBasis({
    required String accountId,
    required String effectiveOn,
  }) async {
    final json = await requestMapWithSession(
      api,
      'GET',
      '/assets/accounts/$accountId/balance-basis?effective_on=$effectiveOn',
    );
    try {
      final basis = BalanceBasis.fromJson(json);
      if (basis.basisToken.isEmpty || basis.balanceCny.isEmpty) {
        throw const ApiFailure(ApiFailureKind.server, '校准基准数据无效，请稍后重试');
      }
      return basis;
    } on ApiFailure {
      rethrow;
    } catch (_) {
      throw const ApiFailure(ApiFailureKind.server, '校准基准数据无效，请稍后重试');
    }
  }

  /// Creates an immutable balance adjustment through the dedicated endpoint.
  ///
  /// When [basisToken] is present the server ignores [expectedCurrentCny]
  /// entirely. The numeric fallback is kept for servers that predate the
  /// basis endpoint.
  Future<FinanceTransaction> calibrate({
    required String accountId,
    required String clientOpId,
    required String adjustmentId,
    required String targetCny,
    required String effectiveOn,
    String? basisToken,
    String? expectedCurrentCny,
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
        if (basisToken != null) 'basis_token': basisToken,
        if (basisToken == null && expectedCurrentCny != null)
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

  /// V2 wealth view with explicit date replay. Pending accounts keep
  /// `cny_balance == null`; callers must render them as "待换算", not zero.
  Future<WealthView> fetchWealthSnapshot({String? asOfDate}) async {
    final json = await fetchWealth(asOfDate: asOfDate);
    try {
      return WealthView.fromJson(json);
    } catch (_) {
      throw const ApiFailure(ApiFailureKind.server, '净值数据无法识别');
    }
  }
}
