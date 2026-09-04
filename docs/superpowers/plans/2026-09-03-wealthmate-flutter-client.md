# WealthMate Flutter Client Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deliver a complete Android + Windows Flutter client source baseline for WealthMate with local-first data, explicit Agent confirmation, and an API/sync boundary ready for the existing backend contract.

**Architecture:** Use a dependency-light Flutter application with immutable-ish JSON models, a local JSON repository that can later be replaced by Drift, an `ApiClient` boundary for backend resources, and a `FinanceStore` that owns derived state and sync status. Android and Windows share domain/services and use responsive navigation shells; local demo mode is explicit when API configuration is absent.

**Tech Stack:** Dart, Flutter Material 3, `http` for optional API calls, `shared_preferences` for the initial local repository, Flutter test, and platform builds only when the corresponding SDKs are installed.

**Spec:** `docs/superpowers/specs/2026-09-03-wealthmate-dual-track-design.md`

## Global Constraints

- Android uses five tabs：首页、账本、统计、财富、我的；Windows uses left navigation + list/detail content.
- Agent confidence `>= 0.85` may be confirmed; lower confidence remains a draft requiring correction/confirmation.
- Transfer transactions never affect income or expense totals.
- Missing default account must produce “请选择支付账户”; unknown facts display “不会/待确认”.
- No external LLM or push provider is invoked without explicit configuration.
- If Flutter/Android/Visual Studio tooling is unavailable, source delivery proceeds but build status is BLOCKED.

---

### Task 1: Flutter project skeleton and failing domain tests

**Files:**
- Create: `outputs/wealthmate_flutter/pubspec.yaml`
- Create: `outputs/wealthmate_flutter/analysis_options.yaml`
- Create: `outputs/wealthmate_flutter/lib/main.dart`
- Create: `outputs/wealthmate_flutter/lib/domain/models.dart`
- Create: `outputs/wealthmate_flutter/lib/domain/finance_rules.dart`
- Create: `outputs/wealthmate_flutter/test/finance_rules_test.dart`

**Interfaces:**
- `Account`, `Category`, `Transaction`, `Budget`, `Goal`, `FinanceState` expose JSON serialization and stable IDs.
- `FinanceRules.deriveMetrics(FinanceState state, String monthKey)` returns `FinanceMetrics`.
- `FinanceRules.parseNaturalLanguage(String text, {required DateTime now, String? defaultAccountId})` returns `AgentDraft`.
- `FinanceRules.canPostDraft(AgentDraft draft)` returns false when confidence is below `0.85`, amount is missing, or account selection is missing.

- [ ] **Step 1: Create the Flutter package metadata**

  Define a Dart package named `wealthmate_flutter`, minimum Dart SDK compatible with the installed Flutter stable toolchain, and only the dependencies needed for HTTP and local preferences. Do not add generated code or UI packages.

- [ ] **Step 2: Write the failing domain tests**

  Add tests covering these exact behaviors: an asset income increases balance; a liability expense increases liability balance; a transfer changes source/destination balances but leaves income and expense at zero; 80% and 100% budget thresholds produce `warning` and `over`; the phrase `今天中午外卖 32 元，支付宝` returns amount 32, expense, 餐饮, and confidence at least 0.85; a no-account draft cannot post; a 0.72 draft cannot post.

- [ ] **Step 3: Run the tests and verify the expected RED state**

  Run `flutter test test/finance_rules_test.dart`. Expected: FAIL because the domain models and rules are not yet implemented. If Flutter is unavailable, record the exact executable-not-found result in the verification log and continue source implementation without claiming test success.

- [ ] **Step 4: Implement the minimal domain models and rules**

  Implement JSON-safe models and pure functions. Use integer cents internally where practical, or preserve decimal amounts consistently; document the choice in code. Keep transfer logic explicit with `fromAccountId` and `toAccountId`. Implement keyword classification and amount/date parsing without an external LLM.

- [ ] **Step 5: Run the focused tests again**

  Run `flutter test test/finance_rules_test.dart`. Expected: all focused domain tests pass when Flutter is installed; otherwise retain BLOCKED status with the source ready for later execution.

### Task 2: Local repository, API client, and sync queue

**Files:**
- Create: `outputs/wealthmate_flutter/lib/data/local_repository.dart`
- Create: `outputs/wealthmate_flutter/lib/data/api_client.dart`
- Create: `outputs/wealthmate_flutter/lib/data/sync_queue.dart`
- Create: `outputs/wealthmate_flutter/lib/data/finance_repository.dart`
- Create: `outputs/wealthmate_flutter/test/data_repository_test.dart`

**Interfaces:**
- `LocalRepository.load()` and `save(FinanceState state)` persist JSON under a versioned key.
- `ApiClient` exposes `login`, `fetchAccounts`, `fetchCategories`, `fetchTransactions`, `fetchStats`, `fetchWealth`, `fetchBudgets`, `postAgentDraft`, `push`, and `pull` methods and throws typed `ApiFailure` values for 401/409/422/network failures.
- `SyncQueue.enqueue(SyncOperation operation)`, `deduplicate()`, and `pending()` preserve `clientOpId` idempotency.
- `FinanceRepository.applyLocal`, `pushPending`, and `pullChanges` coordinate local-first writes and server-version conflict records.

- [ ] **Step 1: Write the failing repository and sync tests**

  Test that saving/loading preserves an account and transaction, enqueuing the same `clientOpId` twice leaves one pending operation, a soft-delete operation remains replayable, and a stale server version becomes a conflict instead of silently overwriting local data.

- [ ] **Step 2: Run the focused tests and verify RED**

  Run `flutter test test/data_repository_test.dart`. Expected: FAIL because the repository and queue types do not exist. If Flutter is missing, log BLOCKED.

- [ ] **Step 3: Implement the local repository and queue**

  Use an injected storage interface so tests can use an in-memory map and production can use `SharedPreferences`. Store only JSON, include `schemaVersion`, and never log transaction notes. Queue operations with generated `clientOpId`, entity ID, operation type, payload, and created timestamp.

- [ ] **Step 4: Implement the API boundary**

  Build request paths around the handoff resources. Add bearer auth only when a token exists. Convert missing base URL/token to `ApiFailure.configuration` and let the store remain in explicit local demo mode. Map response status codes to typed failures.

- [ ] **Step 5: Implement repository sync methods**

  Apply a local write before network push; send pending operations in order; skip duplicate `clientOpId`s; pull changes after push; record stale updates under `conflicts`; mark successful operations completed. Do not resolve conflicts automatically.

- [ ] **Step 6: Run all focused tests**

  Run `flutter test test/finance_rules_test.dart test/data_repository_test.dart`. Expected: PASS when Flutter exists, otherwise the verification log must state BLOCKED.

### Task 3: Finance store, theme, and navigation shell

**Files:**
- Create: `outputs/wealthmate_flutter/lib/state/finance_store.dart`
- Create: `outputs/wealthmate_flutter/lib/ui/theme.dart`
- Create: `outputs/wealthmate_flutter/lib/ui/app_shell.dart`
- Modify: `outputs/wealthmate_flutter/lib/main.dart`
- Create: `outputs/wealthmate_flutter/test/finance_store_test.dart`

**Interfaces:**
- `FinanceStore.load()`, `addTransaction()`, `deleteTransaction()`, `confirmDraft()`, `refresh()`, and `sync()` expose state transitions to the UI.
- `AppShell` selects five mobile tabs and a Windows three-pane layout based on available width.
- Theme tokens reproduce the Web product’s dark forest, cream, mint, lavender, and peach surfaces.

- [ ] **Step 1: Write store tests**

  Test that `confirmDraft()` refuses a low-confidence draft, accepted drafts append a transaction and update metrics, `deleteTransaction()` creates a soft-delete queue item, and `sync()` reports local demo mode when API configuration is absent.

- [ ] **Step 2: Run store tests to verify RED**

  Run `flutter test test/finance_store_test.dart`. Expected: FAIL because the store and UI shell do not exist; record BLOCKED if the Flutter executable is unavailable.

- [ ] **Step 3: Implement the store**

  Keep the current state, selected month, draft, toast/message, sync status, and conflicts in one store. Persist every local mutation through `FinanceRepository`. Expose derived `FinanceMetrics` rather than duplicating calculations in widgets.

- [ ] **Step 4: Implement theme and responsive shell**

  Add Material 3 color scheme and typography. Use a bottom `NavigationBar` for narrow widths and a `NavigationRail`/row layout for Windows widths; reserve a detail panel on wide windows.

- [ ] **Step 5: Run store and domain tests**

  Run `flutter test`. Expected: PASS when toolchain exists.

### Task 4: Dashboard, ledger, and transaction flows

**Files:**
- Create: `outputs/wealthmate_flutter/lib/ui/dashboard_page.dart`
- Create: `outputs/wealthmate_flutter/lib/ui/ledger_page.dart`
- Create: `outputs/wealthmate_flutter/lib/ui/widgets/metric_card.dart`
- Create: `outputs/wealthmate_flutter/lib/ui/widgets/transaction_form.dart`
- Create: `outputs/wealthmate_flutter/lib/ui/widgets/draft_confirmation_card.dart`
- Modify: `outputs/wealthmate_flutter/lib/ui/app_shell.dart`
- Create: `outputs/wealthmate_flutter/test/transaction_flow_test.dart`

**Interfaces:**
- Dashboard renders income, expense, savings rate, net worth, budgets, and recent transactions.
- Ledger supports month/type/category/search filters, manual form, edit, and soft delete.
- `DraftConfirmationCard` displays confidence and requires an explicit confirmation action.

- [ ] **Step 1: Write widget tests**

  Test that the dashboard renders seed metrics; submitting a manual expense updates the visible expense; entering natural language renders a draft without changing transaction count; tapping “确认入账” changes transaction count; low confidence shows “待确认” and disables direct posting.

- [ ] **Step 2: Run the widget tests and verify RED**

  Run `flutter test test/transaction_flow_test.dart`. Expected: FAIL because the pages and widgets are absent, or BLOCKED if Flutter is missing.

- [ ] **Step 3: Implement dashboard and ledger widgets**

  Use `Consumer`/`AnimatedBuilder` only if the chosen store implementation needs it; otherwise keep a simple `ListenableBuilder`. Render all strings in Chinese, format currency as ¥, and keep all forms keyboard-accessible.

- [ ] **Step 4: Implement manual and natural-language flows**

  Manual form validates amount/date/category/account. Natural language calls pure parsing first; if backend Agent is configured, it may enrich the draft but the UI still requires confirmation and shows “不会/待确认” for missing facts. Default account is used only when explicitly configured; otherwise show account selection.

- [ ] **Step 5: Run focused widget tests**

  Run `flutter test test/transaction_flow_test.dart`. Expected: PASS when Flutter exists.

### Task 5: Statistics, wealth, budgets, and settings pages

**Files:**
- Create: `outputs/wealthmate_flutter/lib/ui/stats_page.dart`
- Create: `outputs/wealthmate_flutter/lib/ui/wealth_page.dart`
- Create: `outputs/wealthmate_flutter/lib/ui/budgets_page.dart`
- Create: `outputs/wealthmate_flutter/lib/ui/settings_page.dart`
- Create: `outputs/wealthmate_flutter/lib/ui/widgets/line_chart.dart`
- Create: `outputs/wealthmate_flutter/lib/ui/widgets/progress_row.dart`
- Create: `outputs/wealthmate_flutter/test/overview_pages_test.dart`

**Interfaces:**
- Stats page renders monthly income/expense/savings and category distribution.
- Wealth page renders asset/liability cards, net worth, emergency-fund target, and selected liquid-asset scope.
- Budgets page renders progress and 80%/100% states and allows local budget edits.
- Settings page exposes API base URL/token status, default payment account, sync status, restore demo data, and JSON export.

- [ ] **Step 1: Write overview widget tests**

  Cover asset/liability/net-worth labels, emergency-fund progress, 80% and over-budget labels, missing API configuration text, and the explicit “恢复演示数据” action.

- [ ] **Step 2: Run overview tests and verify RED**

  Run `flutter test test/overview_pages_test.dart`. Expected: FAIL before page implementations, or BLOCKED without Flutter.

- [ ] **Step 3: Implement the pages and reusable progress/chart widgets**

  Keep charts dependency-free using `CustomPainter`. Charts are summary visuals only and are not a source of extra facts. If a period or report value is undefined by the handoff, show “不会/待确认”.

- [ ] **Step 4: Implement settings actions**

  Add local API configuration storage, default account selection, sync status, demo reset, and user-initiated JSON export. Never surface the JWT value in the UI after saving.

- [ ] **Step 5: Run all widget tests**

  Run `flutter test`. Expected: PASS when Flutter exists.

### Task 6: Formatting, verification matrix, and platform status

**Files:**
- Modify: `outputs/wealthmate_flutter/lib/**/*.dart` as needed for formatter/analyzer findings.
- Create: `outputs/wealthmate_flutter/README.md`
- Create: `FLUTTER-DELIVERY.md`

**Interfaces:**
- README contains exact setup and configuration instructions, but does not claim backend/build success.
- Delivery matrix records each command, exit code, and PASS/BLOCKED/FAIL status.

- [ ] **Step 1: Run Dart formatting**

  Run `dart format --output=none --set-exit-if-changed .` from `outputs/wealthmate_flutter`. If Dart is unavailable, mark BLOCKED. If formatting changes are needed, run `dart format .` and rerun the check.

- [ ] **Step 2: Run static analysis and tests**

  Run `flutter analyze` and `flutter test`. Record complete output summaries and do not convert missing-tool results to PASS.

- [ ] **Step 3: Attempt platform builds**

  Run `flutter build apk --debug` and `flutter build windows --debug` only if the Flutter executable exists. Record Android SDK and Visual Studio C++ workload failures as BLOCKED with the exact reason from the tool output.

- [ ] **Step 4: Write the final setup/readme**

  Document `flutter pub get`, `flutter run -d windows`, `flutter run -d <android-device>`, API base URL configuration, local demo mode, sync conflict handling, and the current platform/toolchain matrix.

- [ ] **Step 5: Review against the handoff line by line**

  Check client scope, confirmation gate, transfer semantics, account types, emergency-fund validation, sync idempotency/conflicts, no-fabrication copy, and all unavailable build/push claims. Leave any unverified item as BLOCKED.
