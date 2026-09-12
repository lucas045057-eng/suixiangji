import '../../../data/api_client.dart';
import '../../../domain/models.dart';

class AssetsRemoteDataSource {
  AssetsRemoteDataSource({required this.api});

  final ApiClient api;

  Future<Account> updateAccount(Account account) => api.updateAccount(account);

  Future<Map<String, Object?>> fetchExchangeRate(String base,
          {String quote = 'CNY'}) =>
      api.fetchExchangeRate(base, quote: quote);

  Future<Map<String, Object?>> saveExchangeRate(Map<String, Object?> rate) =>
      api.saveExchangeRate(rate);

  Future<Map<String, Object?>> fetchWealth() => api.fetchWealth();
}
