# 智能快捷记与账户配置 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将快捷记改为“自然语言自动补齐、可修改、一键确认”，并让账户名称、用户昵称、登录用户名和密码可安全编辑。

**Architecture:** 客户端先用用户自定义分类/账户、默认账户和已确认交易历史完成本地补齐；确认后的修正记录会形成可复用的快捷记忆，并通过当前用户资料接口同步到同一账号的其他设备。草稿始终是可编辑的临时对象，只有用户点击“确认入账”才进入正式账本。账户显示名称保持稳定 ID，用户资料和密码由 FastAPI 服务端校验并保存。

**Tech Stack:** Flutter/Dart, SQLite/Drift local state, FastAPI, SQLAlchemy, PostgreSQL/SQLite test database, JWT, PBKDF2 password hashing, Flutter widget tests, Python unittest.

**Spec:** 本次对话中用户确认的“自动补齐后留修改选项”设计，以及此前确认的账户名称、用户昵称、用户名和密码编辑设计。

## Global Constraints

- 快捷记自动补齐后必须保留“修改”和“确认入账”两个操作。
- 金额、账户、分类和日期不确定时不能绕过用户确认写入正式账本。
- 账户 ID 不变，修改账户名称不能破坏历史账目。
- 密码只保存哈希，不在客户端持久化明文密码。
- 修改用户名或密码后客户端使用新凭证，其他设备需要重新登录。
- 旧版本本地 JSON 缺少新字段时必须正常读取。
- 不能加入支付、银行自动扣款或投资交易功能。

---

### Task 1: 自动补齐规则与快捷记忆

**Files:**
- Modify: `outputs/wealthmate_flutter/lib/domain/models.dart`
- Modify: `outputs/wealthmate_flutter/lib/domain/finance_rules.dart`
- Modify: `outputs/wealthmate_flutter/test/finance_rules_test.dart`

**Interfaces:**
- Produces `QuickMemory` and `FinanceRules.completeNaturalLanguageDraft(...)` for the store and editor UI.

- [ ] **Step 1: Write failing tests**

Add tests proving that a custom account/category and the most recent confirmed account are used to complete “今天吃饭 30 元”, and that a corrected choice can be represented as a `QuickMemory` round-trip in `FinanceState`.

- [ ] **Step 2: Run the focused Flutter tests and observe the expected failure**

Run `E:\flutter\bin\flutter.bat test test/finance_rules_test.dart -r expanded` from `outputs/wealthmate_flutter`.

- [ ] **Step 3: Implement the minimum domain behavior**

Add backward-compatible `QuickMemory` serialization, state storage, text-key normalization, custom-name matching, account-history fallback, and missing-field recomputation. Keep `parseNaturalLanguage` available for existing tests.

- [ ] **Step 4: Run focused tests to green**

Run the same focused test command and confirm the new tests and existing finance-rule tests pass.

### Task 2: Editable draft confirmation flow

**Files:**
- Modify: `outputs/wealthmate_flutter/lib/state/finance_store.dart`
- Modify: `outputs/wealthmate_flutter/lib/ui/widgets/draft_confirmation_card.dart`
- Modify: `outputs/wealthmate_flutter/lib/ui/widgets/transaction_form.dart`
- Create: `outputs/wealthmate_flutter/lib/ui/widgets/draft_editor.dart`
- Modify: `outputs/wealthmate_flutter/test/finance_store_test.dart`
- Modify: `outputs/wealthmate_flutter/test/transaction_flow_test.dart`

**Interfaces:**
- Produces `FinanceStore.updateDraft`, `FinanceStore.rememberDraftChoice`, and a `showDraftEditor` dialog returning an edited `AgentDraft`.

- [ ] **Step 1: Write failing tests**

Add store and widget tests asserting that editing amount/category/account/date updates the draft, that the confirmation button remains visible, and that confirming an edited draft appends only the edited values.

- [ ] **Step 2: Run focused tests and observe failure**

Run `E:\flutter\bin\flutter.bat test test/finance_store_test.dart test/transaction_flow_test.dart -r expanded`.

- [ ] **Step 3: Implement the compact editor**

Add an always-visible `修改` action beside `确认入账`; open a compact editor with amount, type, category, account, date, currency, and note controls; recalculate missing facts and confidence after save; remember the source text after confirmation.

- [ ] **Step 4: Run focused tests to green**

Run the same focused command and confirm draft editing and confirmation tests pass.

### Task 3: Server-backed user profile and password changes

**Files:**
- Modify: `outputs/wealthmate_backend/app/models.py`
- Modify: `outputs/wealthmate_backend/app/db.py`
- Modify: `outputs/wealthmate_backend/app/schemas.py`
- Modify: `outputs/wealthmate_backend/app/api.py`
- Modify: `outputs/wealthmate_flutter/lib/data/api_client.dart`
- Modify: `outputs/wealthmate_flutter/lib/domain/models.dart`
- Modify: `outputs/wealthmate_flutter/lib/state/finance_store.dart`
- Modify: `outputs/wealthmate_backend/tests/test_api.py`

**Interfaces:**
- Adds `GET /auth/me`, `PATCH /auth/me`, and `POST /auth/password`.
- `ApiClient.fetchProfile`, `ApiClient.updateProfile`, and `ApiClient.changePassword` return validated profile data and refreshed access tokens.

- [ ] **Step 1: Write failing API tests**

Add tests for reading profile, changing display name/username, rejecting duplicate username and weak/current-password-invalid changes, and accepting a valid password change followed by login with the new credentials.

- [ ] **Step 2: Run backend API tests and observe failure**

Run `python -m unittest tests.test_api.ApiContractTest -v` from `outputs/wealthmate_backend`.

- [ ] **Step 3: Implement additive schema and endpoints**

Add `display_name` and JSON quick memories to `User`, additive schema checks, authenticated profile endpoints, username uniqueness validation, and PBKDF2 password updates. Change login to verify the stored user hash while retaining first-run environment bootstrap.

- [ ] **Step 4: Implement client API/profile state**

Add `UserProfile`, API client methods, refreshed-token handling, and store methods for profile and password operations. Never persist the raw password.

- [ ] **Step 5: Run backend and Dart tests to green**

Run `python -m unittest discover -s tests -v` and the focused Flutter tests.

### Task 4: Account and profile settings UI

**Files:**
- Create: `outputs/wealthmate_flutter/lib/ui/profile_settings_page.dart`
- Modify: `outputs/wealthmate_flutter/lib/ui/settings_page.dart`
- Modify: `outputs/wealthmate_flutter/lib/ui/account_detail_page.dart`
- Modify: `outputs/wealthmate_flutter/lib/state/finance_store.dart`
- Modify: `outputs/wealthmate_backend/app/api.py`
- Modify: `outputs/wealthmate_backend/tests/test_api.py`
- Modify: `outputs/wealthmate_flutter/test/overview_pages_test.dart`

**Interfaces:**
- Settings page links to per-account configuration and profile settings.
- Account detail saves a non-empty unique display name without changing the stable account ID.

- [ ] **Step 1: Write failing widget tests**

Add tests for the visible “账户名称与账户配置” entry, profile page fields, masked password inputs, and save actions.

- [ ] **Step 2: Run focused widget tests and observe failure**

Run `E:\flutter\bin\flutter.bat test test/overview_pages_test.dart -r expanded`.

- [ ] **Step 3: Implement UI and validation**

Add the account list shortcut, profile editor, separate save actions, clear error messages, and post-change login-state handling. Keep existing account detail editing as the canonical account-name editor.

- [ ] **Step 4: Run focused widget tests to green**

Run the same focused command.

### Task 5: Full verification and delivery packages

**Files:**
- Modify: `outputs/WEALTHMATE-V1-DEPLOYMENT.md`
- Modify: `outputs/ACCEPTANCE-STATUS.md`

- [ ] **Step 1: Run all backend tests and compile checks**

Run `python -m unittest discover -s tests -v` and `python -m compileall -q app tests`.

- [ ] **Step 2: Run all Flutter checks**

Run `E:\flutter\bin\flutter.bat analyze` and `E:\flutter\bin\flutter.bat test`.

- [ ] **Step 3: Build Android and Windows releases**

Build with `--dart-define=WEALTHMATE_API_BASE_URL=http://192.168.1.15:18000`, then replace the APK and Windows ZIP in `outputs`.

- [ ] **Step 4: Update delivery documentation**

Document the new shortcut flow, editable fields, memory behavior, account/profile settings, and the requirement to use the Flutter Windows client rather than the local Web/PWA demo.

