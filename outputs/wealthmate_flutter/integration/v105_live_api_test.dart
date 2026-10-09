import 'dart:io';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:wealthmate_flutter/data/api_client.dart';
import 'package:wealthmate_flutter/data/drift_database.dart';
import 'package:wealthmate_flutter/data/finance_repository.dart';
import 'package:wealthmate_flutter/data/local_repository.dart';
import 'package:wealthmate_flutter/data/sync_queue.dart';
import 'package:wealthmate_flutter/domain/models.dart';
import 'package:wealthmate_flutter/state/finance_store.dart';
import '../test/core/two_device_sync_test.dart' show SyncTokenStore;

class NetworkSwitch extends http.BaseClient {
  final http.Client inner = http.Client();
  bool offline = false;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    if (offline) throw const SocketException('Synthetic offline interval');
    return inner.send(request);
  }

  @override
  void close() => inner.close();
}

void main() {
  test(
      'real Flutter SQLite clients close offline, FX, archive, budget, auth and isolation loops against WSL PostgreSQL',
      () async {
    final url = Platform.environment['WEALTHMATE_LIVE_API'];
    if (url != 'http://127.0.0.1:18765')
      throw StateError('Only the isolated local acceptance service is allowed');
    final tag = DateTime.now().microsecondsSinceEpoch.toString();
    final username = 'flutter_v105_$tag';
    const password = 'synthetic-v105-password';
    final directory =
        await Directory.systemTemp.createTemp('suixiangji-live-client-');
    final clients = <ApiClient>[],
        networks = <NetworkSwitch>[],
        databases = <AppDatabase>[],
        stores = <FinanceStore>[];
    var firstClosed = false;
    Future<FinanceStore> device(String name,
        {bool register = false, String? otherUser}) async {
      final network = NetworkSwitch();
      networks.add(network);
      final api = ApiClient(
          baseUrl: url, client: network, tokenStore: SyncTokenStore());
      clients.add(api);
      if (register) {
        await api.authDataSource.register(
            username: otherUser ?? username,
            password: password,
            inviteCode: 'V105-LOCAL-ONLY-20261009',
            displayName: '隔离验收');
      } else {
        await api.authDataSource.login(username, password);
      }
      final profile = await api.authDataSource.fetchProfile();
      final database =
          AppDatabase(NativeDatabase(File('${directory.path}/$name.sqlite')));
      databases.add(database);
      final repo = FinanceRepository(
          local: LocalRepository(DriftKeyValueStore(database)),
          queue: SyncQueue(),
          api: api);
      await repo.ensureLocalOwner(profile.id);
      final state = await repo.load() ?? const FinanceState();
      final store = FinanceStore(repository: repo, initialState: state);
      stores.add(store);
      await store.sync();
      return store;
    }

    try {
      final a = await device('a', register: true), b = await device('b');
      final owner = (await clients[0].authDataSource.fetchProfile()).id;
      await a.assets.addAccount(
          name: '现金-$tag', type: AccountType.asset, openingBalance: 100);
      await a.sync();
      await b.sync();
      final cash = a.state.accounts
          .firstWhere((r) => r.isActive && r.type == AccountType.asset);
      final food = a.state.categories
          .firstWhere((r) => r.active && r.type == TransactionType.expense);
      networks[0].offline = true;
      await a.ledger.addTransaction(FinanceTransaction(
          id: 'offline-$tag',
          date: '2026-10-09',
          type: TransactionType.expense,
          amount: 16,
          accountId: cash.id,
          categoryId: food.id,
          note: '午饭中文离线'));
      await a.sync();
      expect(a.repository.queue.pending(), isNotEmpty);
      final queuedId = a.repository.queue.pending().last.clientOpId;
      a.dispose();
      await databases[0].close();
      firstClosed = true;
      networks[0].close();
      final reopened = await device('a');
      await b.sync();
      expect(b.state.transactions.single.amount, 16);
      expect(reopened.state.transactions.single.clientOpId, queuedId);
      expect(reopened.repository.queue.pending(), isEmpty);
      await reopened.assets.addAccount(
          name: 'HKD-$tag',
          type: AccountType.asset,
          openingBalance: 100,
          currency: 'HKD');
      await reopened.assets.addAccount(
          name: 'USD-$tag',
          type: AccountType.asset,
          openingBalance: 50,
          currency: 'USD');
      await reopened.assets.saveManualExchangeRate(
          baseCurrency: 'HKD',
          rate: .9,
          rateDate: '2026-10-09',
          source: 'synthetic receipt');
      await reopened.assets.saveManualExchangeRate(
          baseCurrency: 'USD',
          rate: 7,
          rateDate: '2026-10-09',
          source: 'synthetic receipt');
      await reopened.sync();
      await b.sync();
      final hkd = b.state.accounts.firstWhere((r) => r.name == 'HKD-$tag');
      expect(hkd.openingBalance, 100);
      expect(hkd.openingCnyAmount, 90);
      expect(
          b.state.accounts
              .firstWhere((r) => r.name == 'USD-$tag')
              .openingCnyAmount,
          350);
      await b.assets.updateAccount(hkd.copyWith(note: '用途'));
      await b.assets.archiveAccount(hkd.id);
      await b.sync();
      await reopened.sync();
      expect(
          reopened.state.accounts.firstWhere((r) => r.id == hkd.id).archivedAt,
          isNotNull);
      await reopened.assets.restoreAccount(hkd.id);
      await reopened.budget
          .upsertBudget(month: '2026-10', categoryId: '__total__', limit: 100);
      await reopened.sync();
      await b.sync();
      expect(b.state.budgets.single.limit, 100);
      expect(b.state.accounts.firstWhere((r) => r.id == hkd.id).note, '用途');
      final bill = b.state.transactions.single;
      await b.ledger.updateTransaction(bill.copyWith(note: '第二端修改'));
      await b.sync();
      await reopened.sync();
      expect(reopened.state.transactions.single.note, '第二端修改');
      final other =
          await device('other', register: true, otherUser: 'other_v105_$tag');
      expect(other.state.transactions, isEmpty);
      final code = await clients
          .lastWhere((r) => identical(r, reopened.repository.api))
          .authDataSource
          .generateRecoveryCode(password);
      await clients[1]
          .authDataSource
          .recoverPassword(username, code, 'synthetic-v105-new-password');
      await expectLater(
          clients[1].authDataSource.fetchProfile(), throwsA(isA<ApiFailure>()));
      final api = reopened.repository.api!;
      await api.authDataSource.login(username, 'synthetic-v105-new-password');
      final recovered = await api.authDataSource.fetchProfile();
      expect(recovered.id, owner);
      await reopened.repository.ensureLocalOwner(owner);
      await reopened.sync();
      expect(reopened.state.transactions.single.amount, 16);
      expect(reopened.state.budgets.single.limit, 100);
      await reopened.ledger.deleteTransaction(bill.id);
      await reopened.sync();
      await clients[1]
          .authDataSource
          .login(username, 'synthetic-v105-new-password');
      await b.repository.ensureLocalOwner(owner);
      await b.sync();
      expect(b.state.transactions.single.deletedAt, isNotNull);
      expect(reopened.repository.queue.pending(), isEmpty);
      await api.authDataSource.deleteAccount('synthetic-v105-new-password');
      await other.repository.api!.authDataSource.deleteAccount(password);
    } finally {
      for (final store in stores.skip(firstClosed ? 1 : 0)) {
        store.dispose();
      }
      for (final database in databases.skip(firstClosed ? 1 : 0)) {
        await database.close();
      }
      for (final network in networks) {
        network.close();
      }
      await directory.delete(recursive: true);
    }
  });
}
