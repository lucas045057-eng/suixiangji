# Task 1 report - Chinese amount parsing

Scope completed:

- Backend quick-entry parser now supports Chinese amount forms including `16块86`, `16元8角6分`, `16元8毛6`, `两元`, `两块`, `两块五`, `2块5`, `16.86元`, and `32元`.
- Backend drafts still require confirmation and continue exposing `missing_fields`.
- Backend drafts now also expose `missing_facts` so Flutter remote mapping preserves missing information.
- Flutter `FinanceRules.parseNaturalLanguage` uses equivalent amount parsing semantics and retains `confirmationThreshold` / `canPostDraft` checks.
- Unparseable amount text returns no invented amount: backend returns `None`; Flutter draft amount remains `0` with `请输入金额` in `missingFacts`.

TDD red runs:

1. Backend red command:

   `python -m pytest tests/test_quick_entry_module.py -q`

   Result: expected red, exit code 1.

   Summary:

   - `3 failed, 1 passed`
   - `16块86` was parsed as `16.00` instead of `16.86`.
   - `missing_facts` was absent and raised `KeyError`.

2. Flutter red command:

   `flutter test test/finance_rules_test.dart`

   Result: expected red, exit code 1.

   Summary:

   - `13 passed, 2 failed`
   - `16块86` was parsed as `16.0` instead of `16.86`.
   - Unparseable amount text did not include `请输入金额` in `missingFacts`.

Green / verification runs:

1. Backend focused command:

   `python -m pytest tests/test_quick_entry_module.py tests/test_domain.py -q`

   Result: pass, exit code 0.

   Summary: `9 passed in 1.33s`.

2. Flutter finance-rules focused command:

   `flutter test test/finance_rules_test.dart`

   Result: pass, exit code 0.

   Summary: `15 tests passed`.

3. Flutter Quick Entry focused command:

   `flutter test test/features/quick_entry/quick_entry_store_test.dart test/features/quick_entry/quick_entry_boundary_test.dart`

   Result: pass, exit code 0.

   Summary: `12 tests passed`.

Blocked facts:

- None.
- Windows Developer Mode / symlink requirement did not block Flutter tests.

Not verified:

- Full backend suite was not run.
- Full Flutter suite was not run.
- No push, tag, release, deploy, or upload was performed.

## Fix round 1 report

Review issues addressed:

- Malformed Chinese numeral grammar such as `十百元` is rejected instead of parsed as `110`.
- Invalid decimal input such as `16.860元` no longer falls through to a substring amount.
- `0元` is treated as a missing amount in both backend and Flutter, preserving confirmation safety.

TDD red runs:

1. Backend regression red command:

   `python -m pytest tests/test_quick_entry_module.py -q`

   Result: expected red, exit code 1.

   Summary:

   - `1 failed, 3 passed`
   - `十百元` returned `Decimal('110.00')` instead of no amount.

2. Flutter regression red command:

   `flutter test test/finance_rules_test.dart`

   Result: expected red, exit code 1.

   Summary:

   - `14 passed, 1 failed`
   - `十百元` returned `110.0` instead of no amount.

Implementation check run:

1. Backend focused regression command after first implementation pass:

   `python -m pytest tests/test_quick_entry_module.py -q`

   Result: failed, exit code 1.

   Summary:

   - `2 failed, 2 passed`
   - The backend missing-field loop compared the account string with `0`, raising `TypeError`; fixed without broadening scope.

Green / verification runs:

1. Backend regression command:

   `python -m pytest tests/test_quick_entry_module.py -q`

   Result: pass, exit code 0.

   Summary: `4 passed in 0.55s`.

2. Backend focused command:

   `python -m pytest tests/test_quick_entry_module.py tests/test_domain.py -q`

   Result: pass, exit code 0.

   Summary: `9 passed in 0.63s`.

3. Flutter finance-rules focused command:

   `flutter test test/finance_rules_test.dart`

   Result: pass, exit code 0.

   Summary: `15 tests passed`.

4. Flutter Quick Entry focused command:

   `flutter test test/features/quick_entry/quick_entry_store_test.dart test/features/quick_entry/quick_entry_boundary_test.dart`

   Result: pass, exit code 0.

   Summary: `12 tests passed`.

Blocked facts:

- None.

Not verified:

- Full backend suite was not run.
- Full Flutter suite was not run.
- No push, tag, release, deploy, or upload was performed.
