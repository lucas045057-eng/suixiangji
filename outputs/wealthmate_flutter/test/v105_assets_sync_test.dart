import 'package:flutter_test/flutter_test.dart';
import 'package:wealthmate_flutter/domain/models.dart';
import 'core/two_device_sync_test.dart' as harness;

void main() {
  test(
      'two devices retain independent HKD/USD snapshots through pull, restart and archive restoration',
      () async {
    final server = harness.MemorySyncServer();
    const hkd = Account(
        id: 'hkd',
        name: '港币',
        type: AccountType.asset,
        currency: 'HKD',
        openingBalance: 100,
        serverVersion: 1);
    const usd = Account(
        id: 'usd',
        name: '美元',
        type: AccountType.asset,
        currency: 'USD',
        openingBalance: 50,
        serverVersion: 2);
    server.records['accounts']!.clear();
    server.records['accounts']!['hkd'] = hkd.toJson();
    server.records['accounts']!['usd'] = usd.toJson();
    const bill = FinanceTransaction(
        id: 'bill',
        date: '2026-09-01',
        type: TransactionType.expense,
        amount: 10,
        currency: 'HKD',
        cnyAmount: 9,
        accountId: 'hkd',
        serverVersion: 2);
    server.records['transactions']!['bill'] = bill.toJson();
    const seed = FinanceState(
        accounts: [hkd, usd],
        transactions: [bill],
        syncState: SyncState(serverVersion: 2));
    final memory = harness.SyncMemory();
    final a = await harness.syncDevice(server, memory: memory, initial: seed);
    final b = await harness.syncDevice(server, initial: seed);
    addTearDown(a.dispose);
    addTearDown(b.dispose);
    await a.assets.saveManualExchangeRate(
        baseCurrency: 'HKD', rate: .9, rateDate: '2026-10-09', source: '用户凭证');
    await a.sync();
    await a.assets.saveManualExchangeRate(
        baseCurrency: 'USD', rate: 7, rateDate: '2026-10-09', source: '用户凭证');
    await a.sync();
    await b.sync();
    expect(b.assets.accounts.firstWhere((a) => a.id == 'hkd').openingCnyAmount,
        90);
    expect(b.assets.accounts.firstWhere((a) => a.id == 'usd').openingCnyAmount,
        350);
    final reopened = await harness.syncDevice(server, memory: memory);
    addTearDown(reopened.dispose);
    expect(
        reopened.assets.accounts
            .firstWhere((a) => a.id == 'hkd')
            .openingBalance,
        100);
    expect(
        reopened.assets.accounts
            .firstWhere((a) => a.id == 'hkd')
            .openingCnyAmount,
        90);
    await a.assets.updateAccount(a.assets.accounts
        .firstWhere((a) => a.id == 'hkd')
        .copyWith(note: '工资卡'));
    await a.assets.archiveAccount('hkd');
    await a.sync();
    await b.sync();
    expect(b.assets.activeAccounts.map((a) => a.id), ['usd']);
    expect(b.state.transactions.single.accountId, 'hkd');
    await b.assets.restoreAccount('hkd');
    await b.sync();
    await a.sync();
    expect(a.assets.activeAccounts, hasLength(2));
    expect(a.assets.accounts.firstWhere((a) => a.id == 'hkd').note, '工资卡');
    expect(a.state.transactions.single.cnyAmount, 9);
    expect(a.repository.queue.pending(), isEmpty);
  });
}
