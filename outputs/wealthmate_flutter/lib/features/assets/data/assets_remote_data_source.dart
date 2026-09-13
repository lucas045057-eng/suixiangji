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

  Future<Map<String, Object?>> fetchWealth() =>
      requestMapWithSession(api, 'GET', '/wealth');
}
