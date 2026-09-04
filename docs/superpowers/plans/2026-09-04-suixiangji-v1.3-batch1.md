# 随想记 V1.3 Batch 1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在不改动同步协议、不进入下一批功能的前提下，完成登录状态安全持久化、SYNC-01~07 测试矩阵、同步实际缺陷的最小修复和本批次验收文档。

**Architecture:** 保留 Flutter Local First → Drift/SQLite → Sync Queue → REST push/pull → FastAPI → PostgreSQL。登录凭据只进入平台安全存储；业务数据仍保留在现有本地仓库，Token 不进入业务状态、备份或日志。

**Tech Stack:** Flutter/Dart, flutter_secure_storage, Drift/SQLite, FastAPI, SQLAlchemy, PostgreSQL/SQLite tests, Python unittest, Node test, Docker Compose.

**Spec:** User-provided “随想记 V1.3 · 第一实施批次” taskbook in the current conversation.

## Global Constraints

- 本批次只实施 Task 0、Task 3、Task 1、Task 2。
- REST 是唯一正式同步协议；不实现 WebSocket 实时同步。
- 不进入 Alembic、Agent/Prompt、rule_cache、Goal、CSV、UI 大改、Windows/Web 新功能。
- 先写会失败的测试，再写最小生产代码。
- 不能把自动化测试通过写成真实设备通过。
- JWT 不得进入 git、普通业务 JSON、备份或日志。

### Task 0: Lock the baseline

**Files:**
- Create: `docs/V1.3-BATCH1-BASELINE.md`
- Verify: repository status, backend, Flutter, Web commands

- [ ] Record branch, clean status, commit SHA, date and environment.
- [ ] Run backend unittest and compileall.
- [ ] Run Flutter analyze and test.
- [ ] Run Web npm test.
- [ ] Record only observed totals and status levels.

### Task 1: Add secure token lifecycle

**Files:**
- Modify: `outputs/wealthmate_flutter/pubspec.yaml`
- Modify: `outputs/wealthmate_flutter/lib/data/api_client.dart`
- Modify: `outputs/wealthmate_flutter/lib/main.dart`
- Modify: `outputs/wealthmate_flutter/lib/ui/login_page.dart`
- Test: `outputs/wealthmate_flutter/test/login_page_test.dart`
- Test: `outputs/wealthmate_flutter/test/finance_store_test.dart`
- Test: `outputs/wealthmate_backend/tests/test_api.py`

**Interfaces:**
- `ApiClient` receives an optional `TokenStore` and exposes async token load/save/clear behavior.
- `main()` restores a token before choosing `LoginPage` or `AppShell`.
- `ApiClient` clears the stored token on HTTP 401 and notifies an injected auth-expired callback.
- `LoginPage` persists a successful login token through `ApiClient`.

- [ ] Write Flutter tests for token save/load/clear and a 401 clearing the token.
- [ ] Run focused tests and confirm they fail because the secure token lifecycle is absent.
- [ ] Add `flutter_secure_storage` and implement a small injectable token-store boundary.
- [ ] Keep build-time token only as a compatibility fallback; never write it to business JSON.
- [ ] Wire startup restoration and 401-to-login state transition without deleting local finance state.
- [ ] Add backend/export assertions that no access token is present and retain the existing auth-version test.
- [ ] Run focused tests, then the full backend/Flutter/Web suite.

### Task 2: Build the SYNC-01~07 acceptance matrix and integration harness

**Files:**
- Create: `docs/SYNC-ACCEPTANCE-MATRIX.md`
- Create or modify: `outputs/wealthmate_backend/tests/test_sync_acceptance.py`
- Modify: `outputs/wealthmate_flutter/test/data_repository_test.dart`
- Modify: `outputs/wealthmate_backend/tests/test_api.py`

- [ ] Add matrix rows with separate `PASS`, `FAIL`, `BLOCKED`, `NOT_RUN` status columns for automation, integration, Android and Windows.
- [ ] Add automated tests for online create, ten offline records, offline update, offline soft delete, repeated client operation, queue reload, and empty-client full pull.
- [ ] Add cross-user tests covering pull, update and delete isolation.
- [ ] Run focused sync tests and verify any failure is an actual missing behavior rather than a test setup error.
- [ ] Run the full regression suite before making any production change.

### Task 3: Fix only test-proven sync defects

**Files:**
- Modify only the files implicated by a failing test, most likely `outputs/wealthmate_backend/app/api.py`, `outputs/wealthmate_flutter/lib/data/finance_repository.dart`, `outputs/wealthmate_flutter/lib/data/sync_queue.dart`, or `outputs/wealthmate_flutter/lib/domain/models.dart`.
- Update: `docs/DEVICE-SYNC-ACCEPTANCE.md`
- Update: `ACCEPTANCE-STATUS.md`

- [ ] For each failing test, document the symptom and expected behavior before editing production code.
- [ ] Apply the smallest fix for server-version propagation, queue retention, merge behavior, or ownership validation only when the test proves it is needed.
- [ ] Add retry metadata only if a test demonstrates that failed operations lose state; preserve queued operations and avoid hot-loop retries.
- [ ] Run focused regression tests after each fix and retain unchanged behavior where tests already pass.
- [ ] Write a non-technical Android/Windows manual script and mark device rows `NOT_RUN` unless physically exercised.
- [ ] Run all final verification commands, inspect `git diff --stat`, and report exact added/modified/deleted files.
