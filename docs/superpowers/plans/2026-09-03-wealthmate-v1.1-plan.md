# WealthMate V1.1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Improve WealthMate V1 performance and visual clarity while adding custom categories/accounts, transaction details, editable shared budgets with reminders, period-based charts, account detail editing, and working exchange-rate management.

**Architecture:** Keep Flutter + Drift/SQLite as the offline-first client and FastAPI + PostgreSQL as the shared source of truth. Extend the existing account, transaction, category, budget, statistics, and exchange interfaces; then connect them through focused client store methods and page-level listeners. Use programmatic aggregates for every chart and reminder, preserving `client_op_id` idempotency and historical exchange-rate snapshots.

**Tech Stack:** Flutter 3.47.2, Dart, Drift/SQLite, FastAPI, SQLAlchemy, PostgreSQL 16, Docker Compose, existing custom Flutter chart widgets, Android and Windows release builds.

**Spec:** `docs/superpowers/specs/2026-09-03-wealthmate-v1.1-design.md`

## Global Constraints

- Preserve the V1 offline-first flow: local SQLite/Drift first, server sync second, no duplicate operations.
- Keep CNY as the default display currency.
- Fund/investment accounts record total value only; do not add holdings, market prices, trades, or investment advice.
- Program code calculates all amounts, aggregates, thresholds, and chart data; AI only explains structured results.
- Missing exchange rates must display `待补充汇率` and must never be guessed.
- Historical monthly snapshots must not be rewritten when a current exchange rate changes.
- Referenced categories and accounts are archived rather than physically deleted.
- The current workspace is not a Git repository, so each task uses test/build checkpoints instead of commits.

---

### Task 1: Extend shared data contracts and migrations

**Files:**
- Modify: `outputs/wealthmate_backend/app/models.py`
- Modify: `outputs/wealthmate_backend/app/schemas.py`
- Modify: `outputs/wealthmate_backend/app/api.py`
- Modify: `outputs/wealthmate_flutter/lib/domain/models.dart`
- Modify: `outputs/wealthmate_flutter/lib/data/drift_database.dart`
- Regenerate: `outputs/wealthmate_flutter/lib/data/drift_database.g.dart`
- Test: `outputs/wealthmate_backend/tests/test_domain.py`
- Test: `outputs/wealthmate_backend/tests/test_api.py`
- Test: `outputs/wealthmate_flutter/test/finance_rules_test.dart`

**Interfaces:**
- Produces `Account.accountKind` with values `cash`, `bank_card`, `wechat`, `alipay`, `foreign`, `fund_investment`, `credit_card`, `loan`, and `other`.
- Produces `FinanceTransaction.occurredAt` as an ISO-8601 string while retaining the existing day field for compatibility.
- Produces `Budget` server payloads with `id`, `month`, `category_id`, `limit`, `active`, `server_version`, and `updated_at`.
- Produces period aggregate fields `period_start`, `period_end`, `expense_total`, `expense_by_category`, `expense_by_account`, `expense_series`, `income_total`, and `net_worth_change`.

- [ ] **Step 1: Write failing contract tests**

Add backend tests that post an account with `account_kind: "fund_investment"`, post a transaction with `occurred_at`, and assert those fields survive the response. Add a budget round-trip test that creates a budget, updates its limit, and reads the updated value. Add a stats test that requests `period=week` and asserts `expense_series` contains one entry per day with category aggregates.

Add Flutter tests that construct `Account(accountKind: AccountKind.fundInvestment)` and `FinanceTransaction(occurredAt: ...)`, serialize them, and assert `fromJson(toJson(value))` preserves both fields.

- [ ] **Step 2: Run the focused tests and confirm failure**

Run from `outputs/wealthmate_backend`:

```powershell
python -m unittest tests.test_domain tests.test_api -v
```

Run from `outputs/wealthmate_flutter`:

```powershell
E:\flutter\bin\flutter.bat test test/finance_rules_test.dart
```

Expected result: the new fields and budget/statistics responses are missing before implementation.

- [ ] **Step 3: Implement compatible fields and schema migration**

Add nullable database columns for `accounts.account_kind` and `transactions.occurred_at`, defaulting old accounts to `other` and old transactions to their existing date at `00:00:00`. Add the budget table or equivalent persisted model and keep `server_version` on all shared mutable records. Extend Pydantic payloads and JSON serializers without removing existing field names.

- [ ] **Step 4: Regenerate Drift and run focused tests**

Run:

```powershell
dart run build_runner build --delete-conflicting-outputs
python -m unittest tests.test_domain tests.test_api -v
E:\flutter\bin\flutter.bat test test/finance_rules_test.dart
```

Expected result: all new contract tests pass and existing V1 tests remain green.

### Task 2: Add category management and account editing

**Files:**
- Modify: `outputs/wealthmate_backend/app/api.py`
- Modify: `outputs/wealthmate_backend/app/schemas.py`
- Modify: `outputs/wealthmate_flutter/lib/data/api_client.dart`
- Modify: `outputs/wealthmate_flutter/lib/data/finance_repository.dart`
- Modify: `outputs/wealthmate_flutter/lib/state/finance_store.dart`
- Modify: `outputs/wealthmate_flutter/lib/ui/wealth_page.dart`
- Create: `outputs/wealthmate_flutter/lib/ui/category_management_page.dart`
- Create: `outputs/wealthmate_flutter/lib/ui/account_detail_page.dart`
- Test: `outputs/wealthmate_backend/tests/test_api.py`
- Test: `outputs/wealthmate_flutter/test/finance_store_test.dart`

**Interfaces:**
- `ApiClient.createCategory({required String name, required TransactionType type})` returns `Category`.
- `ApiClient.updateCategory(String categoryId, {required String name, required bool active})` returns `Category`.
- `ApiClient.updateAccount(Account account)` returns `Account` through `PATCH /accounts/{account_id}`.
- `FinanceStore.addCategory`, `FinanceStore.updateCategory`, `FinanceStore.archiveCategory`, and `FinanceStore.updateAccount` update local state, enqueue an idempotent sync operation, persist the queue, and notify only affected page sections.

- [ ] **Step 1: Add failing tests for custom names and archive behavior**

Test that a custom category is available in new transaction forms, a renamed category keeps its ID, and an archived category is absent from new forms but remains resolvable for historical transactions. Test that updating an account name and `accountKind` persists locally and creates one `accounts` upsert operation.

- [ ] **Step 2: Add server category CRUD and account payload support**

Implement authenticated `POST /categories`, `PATCH /categories/{category_id}`, and `POST /categories/{category_id}/archive`. Reject physical deletion of referenced categories. Extend account PATCH validation to accept `account_kind` and retain existing `is_liquid` and `is_default_payment` fields.

- [ ] **Step 3: Add client API/store methods**

Implement the exact methods listed under Interfaces. Reuse the existing `SyncQueue` entity names `categories` and `accounts`; use `client_op_id` values that include entity, ID, and timestamp. Preserve local-first behavior when the server is unavailable.

- [ ] **Step 4: Build the management screens**

Add a category management page with add, rename, archive, and restore actions. Make every wealth account card tappable. Add an account detail page with account name, account kind, asset/liability type, currency, opening balance, liquid-asset toggle, default-payment toggle, archive action, and a read-only calculated current balance. Add a “余额调整” action that creates a transaction rather than overwriting the calculated balance.

- [ ] **Step 5: Run focused tests**

Run:

```powershell
python -m unittest tests.test_api -v
E:\flutter\bin\flutter.bat test test/finance_store_test.dart
```

Expected result: category and account changes work offline, serialize correctly, and are ready for later sync.

### Task 3: Make budgets shared, editable, and alerting

**Files:**
- Modify: `outputs/wealthmate_backend/app/models.py`
- Modify: `outputs/wealthmate_backend/app/schemas.py`
- Modify: `outputs/wealthmate_backend/app/api.py`
- Modify: `outputs/wealthmate_flutter/lib/data/api_client.dart`
- Modify: `outputs/wealthmate_flutter/lib/state/finance_store.dart`
- Modify: `outputs/wealthmate_flutter/lib/ui/budgets_page.dart`
- Modify: `outputs/wealthmate_flutter/lib/ui/widgets/progress_row.dart`
- Test: `outputs/wealthmate_backend/tests/test_api.py`
- Test: `outputs/wealthmate_flutter/test/finance_store_test.dart`

**Interfaces:**
- `POST /budgets` creates a budget.
- `PATCH /budgets/{budget_id}` updates month, category, limit, or active state.
- `GET /budgets?month=YYYY-MM` returns shared budgets for the authenticated user.
- `FinanceStore.upsertBudget({String? id, required String month, required String categoryId, required double limit})` updates or creates a budget.
- `FinanceStore.checkBudgetAlerts()` returns deduplicated `BudgetAlert` values for 80%, 100%, and over-budget thresholds.

- [ ] **Step 1: Write failing tests**

Add tests for editing a budget limit, syncing the edited limit to a second client, and producing exactly one alert per budget/month/threshold. Assert 80% is `warning`, 100% is `exhausted`, and values above 100% are `over`.

- [ ] **Step 2: Implement server persistence and CRUD**

Replace the current `GET /budgets` empty response with database-backed results. Add authenticated create, update, list, and archive handlers, including `server_version` updates and conflict-safe operation handling.

- [ ] **Step 3: Implement client editing and alert state**

Wire the existing editor to pass an existing budget ID when editing. Persist seen alert keys locally as `budget:{budgetId}:{month}:{threshold}`. Run the alert check after local transaction confirmation, after sync, and when the budget page opens.

- [ ] **Step 4: Add reminder presentation**

Show an in-app warning banner at 80%, an exhausted banner at 100%, and an over-budget banner above 100%. Use a single local-notification adapter for Android and Windows; if the platform notification is unavailable, keep the in-app banner and do not fail the bookkeeping action.

- [ ] **Step 5: Run budget tests**

Run:

```powershell
python -m unittest tests.test_api -v
E:\flutter\bin\flutter.bat test test/finance_store_test.dart
```

### Task 4: Add period statistics, bar charts, and pie charts

**Files:**
- Modify: `outputs/wealthmate_backend/app/domain.py`
- Modify: `outputs/wealthmate_backend/app/api.py`
- Modify: `outputs/wealthmate_flutter/lib/domain/finance_rules.dart`
- Modify: `outputs/wealthmate_flutter/lib/ui/stats_page.dart`
- Create: `outputs/wealthmate_flutter/lib/ui/widgets/bar_chart.dart`
- Create: `outputs/wealthmate_flutter/lib/ui/widgets/pie_chart.dart`
- Test: `outputs/wealthmate_backend/tests/test_domain.py`
- Test: `outputs/wealthmate_backend/tests/test_api.py`
- Test: `outputs/wealthmate_flutter/test/finance_rules_test.dart`

**Interfaces:**
- `GET /stats?period=day|week|month|custom&start=YYYY-MM-DD&end=YYYY-MM-DD` returns the shared aggregate fields from the spec.
- `FinanceRules.periodExpenseSeries(FinanceState state, DateTimeRange range)` returns `List<PeriodPoint>`.
- `FinanceRules.expenseByCategory(FinanceState state, DateTimeRange range)` returns `Map<String, double>` sorted by the UI layer.

- [ ] **Step 1: Write failing aggregation tests**

Test day aggregation by hour, week aggregation by Monday–Sunday, month aggregation by calendar day, category totals, and exclusion of transfers and unconverted foreign-currency values. Test that pie percentages sum to 100% when there is at least one converted expense.

- [ ] **Step 2: Implement programmatic period aggregates**

Normalize `occurred_at` to the requested timezone and period bucket. Return zero-filled buckets so charts do not jump when a day has no transactions. Keep the existing monthly totals in the response for backward compatibility.

- [ ] **Step 3: Implement charts**

Add a period selector to `StatsPage`. Render a line chart for the period series, a horizontal category bar chart with the top six categories plus `其他`, and a pie chart with category legend and percentages. Put each chart in a bounded repaint region and show a clear empty state when there is no data.

- [ ] **Step 4: Add summary cards**

Display total expense, daily average, highest category, highest payment account, and comparison with the previous equivalent period. Use the same aggregate values as the charts.

- [ ] **Step 5: Run chart/statistics tests**

Run:

```powershell
python -m unittest tests.test_domain tests.test_api -v
E:\flutter\bin\flutter.bat test test/finance_rules_test.dart
```

### Task 5: Wire exchange-rate management

**Files:**
- Modify: `outputs/wealthmate_flutter/lib/data/api_client.dart`
- Modify: `outputs/wealthmate_flutter/lib/state/finance_store.dart`
- Modify: `outputs/wealthmate_flutter/lib/ui/wealth_page.dart`
- Create: `outputs/wealthmate_flutter/lib/ui/exchange_rates_page.dart`
- Modify: `outputs/wealthmate_backend/app/services/exchange.py`
- Modify: `outputs/wealthmate_backend/app/api.py`
- Test: `outputs/wealthmate_backend/tests/test_api.py`
- Test: `outputs/wealthmate_flutter/test/finance_store_test.dart`

**Interfaces:**
- `FinanceStore.refreshExchangeRate(String baseCurrency)` fetches `/exchange/rates?base=...&quote=CNY`, persists the verified snapshot, and refreshes current account conversion.
- `FinanceStore.saveManualExchangeRate({required String baseCurrency, required double rate, required String rateDate, required String source})` validates and persists a positive manual rate.

- [ ] **Step 1: Write failing tests**

Test that a successful fetched rate stores value, source, and date; a failed fetch leaves the previous verified rate unchanged; a missing rate leaves conversion status `pending`; and a new rate does not rewrite a stored monthly snapshot.

- [ ] **Step 2: Connect the existing server exchange service**

Keep Frankfurter behind the existing service interface. Validate positive rates and supported currency codes. Return a structured `rate`, `rate_date`, `source`, and `updated_at` response.

- [ ] **Step 3: Add client exchange screen**

List non-CNY currencies used by accounts or transactions. Show current rate, source, date, and status. Provide “获取汇率” and “手动录入” actions. Use `待补充汇率` for unavailable values.

- [ ] **Step 4: Run exchange tests**

Run:

```powershell
python -m unittest tests.test_api -v
E:\flutter\bin\flutter.bat test test/finance_store_test.dart
```

### Task 6: Redesign home, recent transactions, and responsive visuals

**Files:**
- Modify: `outputs/wealthmate_flutter/lib/ui/app_shell.dart`
- Modify: `outputs/wealthmate_flutter/lib/ui/dashboard_page.dart`
- Modify: `outputs/wealthmate_flutter/lib/ui/ledger_page.dart`
- Create: `outputs/wealthmate_flutter/lib/ui/transaction_detail_page.dart`
- Modify: `outputs/wealthmate_flutter/lib/ui/theme.dart`
- Modify: `outputs/wealthmate_flutter/lib/ui/widgets/transaction_form.dart`
- Test: `outputs/wealthmate_flutter/test/overview_pages_test.dart`
- Test: `outputs/wealthmate_flutter/test/transaction_flow_test.dart`

**Interfaces:**
- `DashboardPage` exposes exactly two home actions with labels `快捷记` and `记一笔`.
- `TransactionDetailPage` accepts `FinanceTransaction transaction` and `FinanceStore store`, displays all detail fields, and returns after edit/delete.

- [ ] **Step 1: Write failing UI tests**

Assert the dashboard contains exactly one `快捷记` and one `记一笔`, does not contain a home floating action button, and recent transaction tiles are tappable. Assert the detail page displays date/time, amount, category, account/platform, currency, CNY amount, note, and exchange status.

- [ ] **Step 2: Simplify home layout**

Remove the global home floating action button and duplicate dashboard action. Use two prominent action cards below the net-worth summary, followed by recent transactions and a compact month summary.

- [ ] **Step 3: Add transaction details**

Make recent transaction rows `InkWell`/`ListTile.onTap` targets. Show the exact `occurred_at` when available, the day-only fallback when not, and the account name as the payment platform. Reuse the existing transaction form for edit.

- [ ] **Step 4: Apply visual system**

Reduce nested cards, use consistent 8-point spacing, strengthen typography hierarchy, use a single primary green and dedicated warning/error colors, and provide desktop two-column layout with mobile single-column layout.

- [ ] **Step 5: Run UI tests**

Run:

```powershell
E:\flutter\bin\flutter.bat test test/overview_pages_test.dart test/transaction_flow_test.dart
```

### Task 7: Reduce global rebuilds and verify performance

**Files:**
- Modify: `outputs/wealthmate_flutter/lib/state/finance_store.dart`
- Modify: `outputs/wealthmate_flutter/lib/ui/app_shell.dart`
- Modify: `outputs/wealthmate_flutter/lib/ui/dashboard_page.dart`
- Modify: `outputs/wealthmate_flutter/lib/ui/stats_page.dart`
- Modify: `outputs/wealthmate_flutter/lib/ui/wealth_page.dart`
- Modify: `outputs/wealthmate_flutter/lib/ui/ledger_page.dart`
- Test: `outputs/wealthmate_flutter/test/finance_store_test.dart`

**Interfaces:**
- `FinanceStore` exposes stable derived selectors for overview metrics, recent transactions, account balances, and selected-period aggregates.
- Page widgets subscribe only to the selector they render; changing a budget does not rebuild the transaction list or chart unless its input changed.

- [ ] **Step 1: Add rebuild-sensitive tests**

Keep existing behavior tests and add a store test that changing a budget preserves transaction data, changing a transaction preserves account metadata, and repeated reads of the same month use the same derived result until state changes.

- [ ] **Step 2: Split listeners by page responsibility**

Replace broad `ListenableBuilder` usage around whole pages with smaller listeners around metric cards, lists, chart regions, account sections, and sync banners. Cache derived metrics by state identity/current period.

- [ ] **Step 3: Make page construction stable**

Store the page list in the shell state or use a lazy page cache so `IndexedStack` does not recreate all page widgets on every shell rebuild. Keep already visited page state while avoiding initial construction of every heavy section.

- [ ] **Step 4: Run full client verification**

Run:

```powershell
E:\flutter\bin\flutter.bat analyze
E:\flutter\bin\flutter.bat test
```

Use Flutter profile mode to inspect frame timing while switching pages, opening account detail, changing periods, and scrolling the ledger. The release candidate must not introduce a visible blocking spinner for local operations.

### Task 8: Full regression, packaging, and deployment documentation

**Files:**
- Modify: `outputs/WEALTHMATE-V1-DEPLOYMENT.md`
- Modify: `outputs/ACCEPTANCE-STATUS.md`
- Create/refresh: `outputs/wealthmate-v1-android.apk`
- Create/refresh: `outputs/wealthmate-v1-windows-20260903.zip`

- [ ] **Step 1: Run backend verification**

Run from `outputs/wealthmate_backend`:

```powershell
python -m unittest discover -s tests -v
python -m compileall -q app tests
```

- [ ] **Step 2: Build Android and Windows clients**

Run from `outputs/wealthmate_flutter`:

```powershell
E:\flutter\bin\flutter.bat build apk --release --dart-define=WEALTHMATE_API_BASE_URL=http://192.168.1.15:18000
E:\flutter\bin\flutter.bat build windows --release --dart-define=WEALTHMATE_API_BASE_URL=http://192.168.1.15:18000
```

Copy the APK to `outputs/wealthmate-v1-android.apk` and package the complete Windows Release directory as `outputs/wealthmate-v1-windows-20260903.zip`.

- [ ] **Step 3: Verify cross-device contract**

Use the running server at `http://192.168.1.15:18000`. Verify login, custom category, account rename, budget edit, budget alert, exchange-rate update, period charts, offline create, reconnect sync, and duplicate prevention. If the phone cannot open `/health`, add the TCP 18000 inbound rule using an Administrator PowerShell.

- [ ] **Step 4: Update acceptance evidence**

Record test counts, build paths, current API address, known limitation that real phone hardware requires final manual installation, and the fact that Windows firewall creation requires administrator permission on this machine.
