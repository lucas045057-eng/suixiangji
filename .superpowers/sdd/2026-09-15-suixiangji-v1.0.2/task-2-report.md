# Task 2 report - income/expense category coupling

## Scope

Implemented Task 2 only in the requested files:

- `outputs/wealthmate_flutter/lib/features/ledger/domain/ledger_rules.dart`
- `outputs/wealthmate_flutter/lib/ui/widgets/transaction_form.dart`
- `outputs/wealthmate_flutter/lib/ui/widgets/draft_editor.dart`
- `outputs/wealthmate_flutter/test/features/ledger/ledger_store_test.dart`
- `outputs/wealthmate_flutter/test/transaction_form_category_test.dart`
- `outputs/wealthmate_backend/app/ledger/service.py`
- `outputs/wealthmate_backend/tests/test_category_type_coupling.py`

No agents were spawned. No remote, production, dependency, migration, metadata, amount parsing, sync coordinator, asset, or dashboard navigation files were changed.

## TDD red evidence

### Flutter red

Command:

```powershell
flutter test test/features/ledger/ledger_store_test.dart test/transaction_form_category_test.dart
```

Result: failed as expected before production edits.

Observed counts: `+3 -4`, `Some tests failed`.

Expected missing behavior proven:

- `LedgerStore rejects non-transfer transactions using the opposite category type` failed because the async save completed instead of throwing.
- `TransactionForm resets category when the type changes` failed because the transaction was not saved by the off-screen submit tap in the initial harness and the behavior was not present.
- `TransactionForm keeps an archived matching category while editing` failed because archived matching category was not available in the dropdown.
- `DraftEditor resets category when the type changes` failed because saved draft kept `food` after switching to income instead of selecting `salary`.

Flutter was not blocked. No `BLOCKED: Windows Developer Mode / symlink requirement` condition occurred.

### Backend red

Command:

```powershell
python -m pytest tests/test_category_type_coupling.py
```

Result: failed as expected before `app/ledger/service.py` edits.

Observed counts: `3 failed, 1 passed, 1 warning`.

Expected missing behavior proven:

- HTTP create accepted an expense using an income category: expected 422, got 200.
- Direct `save_transaction` accepted an expense using an income category: expected `HTTPException`, none raised.
- Sync push accepted an expense using an income category: expected 422, got 200.
- Transfer semantics remained accepted in the red test.

## Implementation summary

### Flutter

- Added shared `LedgerRules` category helpers:
  - active same-type category candidates;
  - first active same-type default category;
  - valid category selection preserving archived matching categories;
  - non-transfer transaction category type validation.
- `LedgerRules.upsertTransaction` now rejects non-transfer transactions whose category exists and has the opposite type before local persistence/queueing.
- `TransactionForm` now initializes and displays only valid same-type category candidates, keeps an archived matching category while editing, and resets category to the first active category of the newly selected type or empty when none exists.
- `DraftEditor` now applies the same candidate/default/reset behavior and does not keep a hidden opposite-type category after type changes.

### Backend

- `save_transaction` now validates `Category.kind` against non-transfer transaction `kind` after ownership/existence checks.
- Mismatch raises the existing `HTTPException(status_code=422, detail=...)` style.
- Because `_save_tx = save_transaction`, HTTP CRUD and `/sync/push` share the same boundary.
- Transfer category behavior remains unchanged.

## Green verification evidence

### Focused Flutter green

Command:

```powershell
flutter test test/features/ledger/ledger_store_test.dart test/transaction_form_category_test.dart
```

Result: `7 passed`.

### Focused backend green

Command:

```powershell
python -m pytest tests/test_category_type_coupling.py
```

Result: `4 passed, 1 warning`.

### Flutter transaction acceptance sweep

Command:

```powershell
flutter test test/transaction_flow_test.dart test/features/ledger/ledger_store_test.dart test/transaction_form_category_test.dart
```

Result after formatting: `10 passed`.

### Backend category plus sync/API acceptance sweep

Initial command:

```powershell
python -m pytest tests/test_category_type_coupling.py tests/test_api.py
```

Initial result after formatting: `4 passed, 1 warning, 33 errors`.

NOT VERIFIED fact for that initial combined run: failures were test isolation errors, not category coupling failures. `test_category_type_coupling.py` cleaned up its temporary SQLite directory while the imported app engine remained cached; then `test_api.py` attempted to reuse the deleted database path and failed with `sqlite3.OperationalError: unable to open database file`.

Fix made inside scoped new test file: stopped cleaning up that temporary directory in `tearDownClass` so later tests in the same pytest process are not poisoned by the cached app engine.

Rerun command:

```powershell
python -m pytest tests/test_category_type_coupling.py tests/test_api.py
```

Final result: `37 passed, 2 warnings`.

## Warnings / blocked facts

- Flutter was executable; no symlink block occurred.
- `flutter test` reported dependency-update notices only; no Flutter test warnings remained in the final run.
- Backend green runs reported existing third-party deprecation warnings:
  - Starlette `anyio.abc.BlockingPortal` deprecation warning.
  - LangGraph `allowed_objects` pending deprecation warning during `test_api.py`.
- Full repository test suites were NOT VERIFIED because the user requested stopping with tests already run and avoiding further long-running commands.

## Commit

Commit subject requested:

```text
fix: couple transaction categories to type
```
