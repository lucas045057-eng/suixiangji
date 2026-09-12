# Task 3 — Phase 2 Ledger Report

## Result

`DONE_WITH_CONCERNS`

Task 3 is implemented on `refactor/modular-monolith`. Flutter Ledger ownership now lives behind `LedgerRemoteDataSource`, `LedgerRepository`, `LedgerRules`, and `LedgerStore`; the compatibility `FinanceStore`/`FinanceRepository` entry points delegate to those boundaries. Backend Category and Transaction routes, schemas, domain normalization, response mapping, validation, and persistence are extracted under `app/ledger`, with the router registered by `app/main.py`. `app/models.py` is unchanged.

## Commits

- Starting commit: `33fab80` (`test(auth): document baseline exchange rate UI`)
- Implementation commit: `a571eed` (`refactor(ledger): extract ledger module`)

## RED evidence

1. The inherited Ledger test-first work initially failed to compile. `flutter test test\features\ledger\ledger_store_test.dart test\transaction_flow_test.dart test\data_repository_test.dart` reported missing `SyncOperation`/`SyncOperationType`, a Flutter/domain `Category` import collision, and incomplete nullable compatibility wiring in `TransactionForm`.
2. After compile repair, the same focused Flutter command failed `natural language composer keeps a draft until confirmation`: the form listened only to `LedgerStore`, so a draft mutation notified `FinanceStore` without rebuilding the form.
3. Backend discovery initially produced 29 failures, all rooted in extracted `/categories` and `/transactions` routes returning 404 because `ledger.router` was not registered.
4. The first full Flutter gate exposed the unchanged pending-create queue contract: expected `pending-edit-op`, received a newly generated `edit-*` operation ID. The implementation was corrected to retain a pending create's operation identity while replacing its payload; synced edits still receive a new operation ID.
5. The first full Flutter gate also failed `delayed A local save cannot populate B or overwrite B queue`: expected B's transactions to be empty, but a late A Ledger completion republished A state. `LedgerStore` now discards completion publication when `LocalStateSession` has rebound to another local partition.

## GREEN evidence

- Focused Flutter gate: 17/17 passed.
- Ledger/queue/owner-switch regression set: 19/19 passed.
- Full Flutter suite: 202/202 passed.
- Flutter analyzer: no issues found.
- Focused backend API/domain suites: 32/32 API and 5/5 domain tests passed.
- Full backend pytest suite: 118/118 passed.
- `git diff --check`: passed before the implementation commit.
- Boundary audit: no page performs direct HTTP, database, `LocalRepository.save`, `repository.save`, or `queue.enqueue` calls; Ledger aggregate/queue mutations call `LocalStateSession.write`; `app/models.py` has no diff and remains the only ORM model definition.

## Tests run

```text
flutter test test\features\ledger\ledger_store_test.dart test\transaction_flow_test.dart test\data_repository_test.dart
flutter test test\v1_session_partition_test.dart test\pending_create_edit_queue_consistency_test.dart test\features\ledger\ledger_store_test.dart
flutter test --reporter compact
flutter analyze
python -m unittest discover -s tests -p 'test_api.py' -v
python -m unittest discover -s tests -p 'test_domain.py' -v
python -m pytest -q --basetemp E:\codex\pytest-task3-20260911
```

## Changed files

- `outputs/wealthmate_flutter/lib/features/ledger/data/ledger_repository.dart`
- `outputs/wealthmate_flutter/lib/features/ledger/data/ledger_remote_data_source.dart`
- `outputs/wealthmate_flutter/lib/features/ledger/domain/ledger_rules.dart`
- `outputs/wealthmate_flutter/lib/features/ledger/state/ledger_store.dart`
- `outputs/wealthmate_flutter/test/features/ledger/ledger_store_test.dart`
- `outputs/wealthmate_flutter/lib/ui/ledger_page.dart`
- `outputs/wealthmate_flutter/lib/ui/transaction_detail_page.dart`
- `outputs/wealthmate_flutter/lib/ui/category_management_page.dart`
- `outputs/wealthmate_flutter/lib/ui/dashboard_page.dart`
- `outputs/wealthmate_flutter/lib/ui/widgets/transaction_form.dart`
- `outputs/wealthmate_flutter/lib/state/finance_store.dart`
- `outputs/wealthmate_flutter/lib/data/finance_repository.dart`
- `outputs/wealthmate_flutter/lib/data/api_client.dart`
- `outputs/wealthmate_backend/app/ledger/router.py`
- `outputs/wealthmate_backend/app/ledger/service.py`
- `outputs/wealthmate_backend/app/ledger/schemas.py`
- `outputs/wealthmate_backend/app/ledger/domain.py`
- `outputs/wealthmate_backend/app/api.py`
- `outputs/wealthmate_backend/app/main.py`

## Concerns

- The brief's literal backend command, `python -m unittest tests.test_api tests.test_domain -v`, cannot import the repository's existing absolute `test_sync_acceptance` module from the backend root. Equivalent discovery invocations pass all 37 requested tests without modifying test expectations or import behavior.
- The full backend suite passes with one pre-existing LangGraph pending-deprecation warning about `allowed_objects`.

No migrations, production database changes, push, PR, deployment, generated product artifacts, or unrelated cleanup were performed.

---

# Task 3 Fix Round 1

## Result

`DONE_WITH_CONCERNS`

Both Important review findings are corrected. `DashboardPage` no longer imports, accepts, or reads `FinanceStore`; `AppShell` supplies the Ledger read model plus the existing non-Ledger projections and actions needed to preserve sync, budget-alert, draft-confirmation, and composer behavior. `FinanceRepository` now retains its public compatibility entry points while delegating transaction save, category save, and transaction delete directly to one injected `LedgerRepository`. Ledger state reconstruction and the corresponding sync-operation construction now live under `features/ledger`.

## Commits

- Task 3 implementation commit: `a571eed` (`refactor(ledger): extract ledger module`)
- Task 3 report commit: `3aef7c2` (`docs(ledger): record task 3 verification`)
- Fix Round 1 implementation commit: `894aec1` (`fix(ledger): enforce dashboard and repository boundaries`)

## RED evidence

### Finding 1 — Dashboard universal-store boundary

The existing dashboard widget test was first changed to construct `DashboardPage` from Ledger and narrow non-Ledger inputs, before changing production code.

```text
Command:
flutter test test\transaction_flow_test.dart --plain-name "dashboard renders the cash-flow metrics"

Output:
test\transaction_flow_test.dart:37:7: Error: No named parameter with the name 'budgetAlerts'.
      budgetAlerts: store.budgetAlerts,
      ^^^^^^^^^^^^
lib\ui\dashboard_page.dart:15:3: Context: Found this candidate, but the arguments don't match.
  DashboardPage(
  ^^^^^^^^^^^^^
00:00 +0 -1: Failed to load ".../test/transaction_flow_test.dart": Compilation failed for testPath=.../test/transaction_flow_test.dart
00:00 +0 -1: Some tests failed.
Exit code: 1
```

This was the expected boundary failure: the production widget still exposed the old universal-store constructor instead of the required narrow inputs.

### Finding 2 — FinanceRepository compatibility delegation

A sentinel `LedgerRepository` test double was added first. It returns an identity-distinct state from each Ledger mutation method, allowing the test to prove that every FinanceRepository compatibility method delegates rather than reconstructing state or operations itself.

```text
Command:
flutter test test\features\ledger\ledger_store_test.dart --plain-name "FinanceRepository delegates Ledger mutation compatibility methods"

Output:
test\features\ledger\ledger_store_test.dart:155:7: Error: No named parameter with the name 'ledgerRepository'.
      ledgerRepository:
      ^^^^^^^^^^^^^^^^
lib\data\finance_repository.dart:9:3: Context: Found this candidate, but the arguments don't match.
  FinanceRepository({
  ^^^^^^^^^^^^^^^^^
00:00 +0 -1: Failed to load ".../test/features/ledger/ledger_store_test.dart": Compilation failed for testPath=.../test/features/ledger/ledger_store_test.dart
00:00 +0 -1: Some tests failed.
Exit code: 1
```

This was the expected façade failure: FinanceRepository had no injectable Ledger delegate and still owned the implementation.

## GREEN evidence

```text
Command:
flutter test test\transaction_flow_test.dart --plain-name "dashboard renders the cash-flow metrics"
Output: 00:01 +1: All tests passed!

Command:
flutter test test\features\ledger\ledger_store_test.dart --plain-name "FinanceRepository delegates Ledger mutation compatibility methods"
Output: 00:00 +1: All tests passed!

Command:
flutter test test\features\ledger\ledger_store_test.dart test\transaction_flow_test.dart test\data_repository_test.dart test\pending_create_edit_queue_consistency_test.dart test\v1_session_partition_test.dart
Output: 00:02 +35: All tests passed!

Command:
flutter test test\transaction_flow_test.dart test\dashboard_stale_state_diagnostic_test.dart test\overview_pages_test.dart
Output: 00:02 +16: All tests passed!

Command:
flutter test --reporter compact
Output: 00:08 +203: All tests passed!

Command:
flutter analyze
First output: 1 info issue, `use_super_parameters`, in the new test sentinel constructor.
Correction: converted the test constructor to a super parameter.
Final output: No issues found! (ran in 2.7s)

Command:
python -m unittest discover -s tests -p test_api.py -v
Output: Ran 32 tests in 4.172s — OK

Command:
python -m unittest discover -s tests -p test_domain.py -v
Output: Ran 5 tests in 0.001s — OK

Command:
python -m pytest -q --basetemp E:\codex\pytest-task3-fix1-20260912
Output: 118 passed, 1 warning in 37.29s

Command:
git diff --check
Output: no whitespace errors
```

Boundary audit results:

- `DashboardPage` has no `FinanceStore`, `financeStore`, or `store:` reference. It reads Ledger state/metrics from `LedgerStore` and receives existing cross-feature values/actions explicitly.
- `AppShell` remains the composition root and supplies those narrow inputs. Normal and smart transaction composers retain their previous Ledger and draft-only wiring.
- `FinanceRepository.applyLocalTransaction`, `applyLocalCategory`, and `softDelete` are direct `_ledgerRepository` delegations.
- Transaction/category state reconstruction and sync-operation creation are in `features/ledger/data/ledger_repository.dart`.
- All Ledger aggregate/queue writes continue through `LocalStateSession.write`; no page performs a direct local/queue write.
- Backend files and `app/models.py` are unchanged in this fix round.

## Changed files

- `outputs/wealthmate_flutter/lib/ui/dashboard_page.dart`
- `outputs/wealthmate_flutter/lib/ui/app_shell.dart`
- `outputs/wealthmate_flutter/lib/data/finance_repository.dart`
- `outputs/wealthmate_flutter/lib/features/ledger/data/ledger_repository.dart`
- `outputs/wealthmate_flutter/lib/features/ledger/state/ledger_store.dart`
- `outputs/wealthmate_flutter/test/transaction_flow_test.dart`
- `outputs/wealthmate_flutter/test/dashboard_stale_state_diagnostic_test.dart`
- `outputs/wealthmate_flutter/test/features/ledger/ledger_store_test.dart`
- `.superpowers/sdd/2026-09-10-suixiangji-modular-monolith/task-3-report.md`

## Concerns

- The brief's literal backend command, `python -m unittest tests.test_api tests.test_domain -v`, still cannot import the repository's existing absolute `test_sync_acceptance` module from the backend root. Equivalent discovery invocations pass all 37 requested tests without changing test imports.
- The full backend suite remains green with one pre-existing LangGraph pending-deprecation warning about `allowed_objects`.

No migration, production database access, push, PR, deployment, generated artifact, or unrelated cleanup was performed in Fix Round 1.
