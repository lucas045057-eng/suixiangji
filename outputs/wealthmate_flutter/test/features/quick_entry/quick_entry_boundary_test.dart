import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wealthmate_flutter/core/database/local_state_session.dart';
import 'package:wealthmate_flutter/data/local_repository.dart';
import 'package:wealthmate_flutter/data/sync_queue.dart';
import 'package:wealthmate_flutter/domain/models.dart';
import 'package:wealthmate_flutter/features/ledger/data/ledger_repository.dart';
import 'package:wealthmate_flutter/features/ledger/state/ledger_store.dart';
import 'package:wealthmate_flutter/features/quick_entry/data/quick_entry_repository.dart';
import 'package:wealthmate_flutter/features/quick_entry/state/quick_entry_store.dart';
import 'package:wealthmate_flutter/ui/dashboard_page.dart';
import 'package:wealthmate_flutter/ui/theme.dart';

class _BoundaryMemory implements KeyValueStore {
  final Map<String, String> values = <String, String>{};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;
}

void main() {
  testWidgets('formal dashboard reads draft state from QuickEntryStore',
      (tester) async {
    final state = FinanceState(
      currentMonth: '2026-09',
      defaultAccountId: 'wallet',
      accounts: const [
        Account(id: 'wallet', name: '钱包', type: AccountType.asset),
      ],
      categories: const [Category(id: 'food', name: '餐饮')],
    );
    final session = LocalStateSession(
      local: LocalRepository(_BoundaryMemory()),
      queue: SyncQueue(),
    );
    final ledger = LedgerStore(
      repository: LedgerRepository(session: session),
      initialState: state,
    );
    final quickEntry = QuickEntryStore(
      repository: QuickEntryRepository(session: session),
      initialState: state,
    );
    await quickEntry.createDraft('今天吃饭 30 元', now: DateTime(2026, 9, 4, 10));

    await tester.pumpWidget(MaterialApp(
      theme: wealthMateTheme(),
      home: DashboardPage(
        ledger: ledger,
        quickEntry: quickEntry,
        isDemoMode: true,
        openComposer: (_, {smart = false}) {},
        openBudgets: () {},
      ),
    ));

    expect(find.text('已整理成待确认草稿'), findsOneWidget);
    expect(find.text('确认入账'), findsOneWidget);
  });
}
