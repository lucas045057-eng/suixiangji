# 随想记 V1.0.4 同步与 App 内更新 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox syntax for tracking.

**Goal:** 在不破坏现有本地优先同步协议、数据库和正式签名身份的前提下，交付 V1.0.4 的双向自动同步、PostgreSQL 并发安全和 Android App 内 APK 更新流程。

**Architecture:** 本地 mutation 只通过 feature store 回调通知 FinanceStore，由共享 SyncScheduler 管理 debounce、共享 Future 和 serialized drain loop；现有 SyncCoordinator 继续负责 push/pull、merge 和 cursor 持久化。服务端在单次 push transaction 开始时锁定并刷新当前 User 行，再按依赖顺序分配严格递增版本。更新器拆成可注入的 HTTPS downloader、Android MethodChannel installer 和状态驱动 UI。

**Tech Stack:** Flutter/Dart 3.13、Flutter test、Dart HttpClient、path_provider、Android Kotlin/MethodChannel/FileProvider/Package Installer、FastAPI、SQLAlchemy 2、PostgreSQL 16、pytest、Docker Compose。

**Spec:** docs/superpowers/specs/2026-09-16-suixiangji-v1.0.4-sync-and-inapp-update-design.md

## Global Constraints

- 不修改历史 migration，不清空或全量覆盖本地数据库，不改变用户 ID、JWT 或数据隔离语义。
- 本地 cursor 只有在 pull 成功并完成 merge 后推进；push receipt 不能单独推进 cursor。
- active drain 只允许一个实际 push + pull pipeline；active 请求返回同一个 drain Future。
- drain 失败后立即结束，不在内部 while loop retry 或 busy loop；下一次 retry 由 timer、resume、mutation、登录/启动或手动同步唤醒。
- onLocalMutation() 只由已持久化到 SyncQueue 的本地 mutation 触发；remote merge、cursor、receipt、owner 初始化和恢复不得触发它。
- PostgreSQL 版本分配使用一次 push transaction 的 User 行锁，并显式使用锁完成后的数据库最新 sync_version。
- 不申请 Android 全盘存储权限；安装始终交给系统 Package Installer，不静默安装。
- 保留 com.example.wealthmate_flutter applicationId 和 V1.0.3 正式 release signing identity，不提交 keystore、密码、key.properties 或 secrets。
- 不部署生产、不修改正式 PostgreSQL、不切换生产 /app/version、不创建正式 GitHub Release、不 force push、不卸载或清除真实用户 App。
- 无真实 PostgreSQL、签名、APK 下载 URL 或 Android 设备条件时报告 NOT VERIFIED，不写 PASS。

## File Map

### Sync client

- Create: outputs/wealthmate_flutter/lib/core/sync/sync_scheduler.dart — 共享 request Future、debounce 和 serialized drain loop。
- Modify: outputs/wealthmate_flutter/lib/state/finance_store.dart — 绑定 mutation callback、执行单轮 pipeline、暴露 requestSync()/sync()。
- Modify: outputs/wealthmate_flutter/lib/features/ledger/state/ledger_store.dart — 本地 mutation 成功后的通知。
- Modify: outputs/wealthmate_flutter/lib/features/assets/state/asset_store.dart — 账户 mutation 通知，排除非队列汇率/default account 写入。
- Modify: outputs/wealthmate_flutter/lib/features/budget/state/budget_store.dart — 预算 mutation 通知。
- Modify: outputs/wealthmate_flutter/lib/features/quick_entry/state/quick_entry_store.dart — 移除直接 post-confirm sync，沿用 Ledger mutation 通知。
- Modify: outputs/wealthmate_flutter/lib/ui/app_shell.dart — lifecycle observer、foreground timer、启动/resume 调度和 dispose。
- Modify: outputs/wealthmate_flutter/lib/main.dart — 登录完成后统一请求同步、更新恢复安装入口、释放 store。
- Modify: outputs/wealthmate_flutter/lib/core/sync/sync_coordinator.dart — 增加安全客户端诊断日志，保持 cursor/merge 逻辑。

### Sync server

- Modify: outputs/wealthmate_backend/app/sync/service.py — locked User allocator、锁后刷新、一次 transaction batch、诊断日志。
- Create: outputs/wealthmate_backend/tests/test_sync_postgres_concurrency.py — 隔离 PostgreSQL 并发失败/回归测试。
- Modify: outputs/wealthmate_backend/integration/postgres_acceptance.py — 真实 HTTP 并发 push 验收路径和幂等/cursor 断言。

### App update

- Create: outputs/wealthmate_flutter/lib/features/app_update/data/app_update_downloader.dart — HTTPS APK 下载、进度、临时文件和取消。
- Create: outputs/wealthmate_flutter/lib/features/app_update/data/app_update_installer.dart — 安装结果抽象与 MethodChannel 实现。
- Modify: outputs/wealthmate_flutter/lib/features/app_update/state/app_update_store.dart — 下载/安装状态机和共享任务 Future。
- Modify: outputs/wealthmate_flutter/lib/ui/app_update_dialog.dart — 状态、进度、重试、取消和安装权限文案。
- Modify: outputs/wealthmate_flutter/lib/ui/settings_page.dart — 新状态枚举分支和手动检查入口。
- Modify: outputs/wealthmate_flutter/android/app/src/main/kotlin/com/example/wealthmate_flutter/MainActivity.kt — MethodChannel、FileProvider URI、系统安装 Intent、未知来源权限。
- Modify: outputs/wealthmate_flutter/android/app/src/main/AndroidManifest.xml — REQUEST_INSTALL_PACKAGES 与 provider。
- Create: outputs/wealthmate_flutter/android/app/src/main/res/xml/file_paths.xml — 仅允许 app-specific cache/files 的 provider 路径。

### Version, tests and delivery

- Modify: outputs/wealthmate_flutter/pubspec.yaml、lib/core/config/app_config.dart、windows/runner/Runner.rc — V1.0.4 build metadata。
- Modify: outputs/wealthmate_backend/app/config.py、docker-compose.yml — V1.0.4 default metadata。
- Modify/Create: version tests and docs/release/v1.0.4-*.md — 版本回归和实际交付证据。
- Keep outside Git: release APK、签名 properties、keystore、生产环境变量和任何 token。

---

## RED 阶段：先写并提交全部失败回归测试

### Task 1: Add a real PostgreSQL concurrency RED test

**Files:**

- Create: outputs/wealthmate_backend/tests/test_sync_postgres_concurrency.py
- Modify: outputs/wealthmate_backend/integration/postgres_acceptance.py

**Interfaces:**

- Consumes: app.sync.service.push, SyncPushIn, SessionLocal, Base, User, Transaction and SyncOperation。
- Produces: 隔离 PostgreSQL test helpers and a deterministic race harness that fails against the unlocked allocator。

- [ ] **Step 1: Create an isolated PostgreSQL fixture**

Use WEALTHMATE_POSTGRES_TEST_DATABASE_URL as the only database target. Skip with the exact reason "real PostgreSQL test requires WEALTHMATE_POSTGRES_TEST_DATABASE_URL" when unset or when the URL backend is not PostgreSQL. Create tables only when WEALTHMATE_TEST_SCHEMA_INIT=true; generate a random synthetic user ID and reject production-looking database URLs.

~~~python
database_url = os.environ.get("WEALTHMATE_POSTGRES_TEST_DATABASE_URL")
if not database_url:
    pytest.skip("real PostgreSQL test requires WEALTHMATE_POSTGRES_TEST_DATABASE_URL")
assert make_url(database_url).get_backend_name() == "postgresql"
~~~

- [ ] **Step 2: Write the old-allocator race test**

Load the same User into two independent sessions before starting the pushes. Use a temporary SQLAlchemy before_update listener and a two-party barrier so both old Python increments are prepared from the same cached sync_version. Submit different transaction operations, then assert duplicate server_version values or an incomplete old-cursor pull. Keep the test marked RED until the old implementation demonstrably fails.

- [ ] **Step 3: Add locked-User identity-map freshness assertions**

Arrange committed sync_version=40, preload each session, advance the committed value to 41 before the locked section, and assert allocation starts from the post-lock value. In one batch assert accepted operation versions are unique and strictly increasing. Replay a committed client_op_id and assert it does not increment the User version. Inject a failure after allocation and assert rollback leaves no row, receipt or watermark advance.

- [ ] **Step 4: Run the RED test before changing service.py**

Run: pytest -q tests/test_sync_postgres_concurrency.py -vv

Expected: FAIL against the current unlocked implementation on duplicate versions, stale User state, idempotency race or rollback/watermark behavior. If PostgreSQL is unavailable, the test is SKIPPED with the exact environment reason and remains NOT VERIFIED.

- [ ] **Step 5: Commit only the backend RED test**

~~~powershell
git add outputs/wealthmate_backend/tests/test_sync_postgres_concurrency.py outputs/wealthmate_backend/integration/postgres_acceptance.py
git commit -m "test: reproduce postgres sync version race"
~~~

### Task 2: Add client sync, lifecycle and remote-boundary RED tests

**Files:**

- Create: outputs/wealthmate_flutter/test/sync_scheduler_test.dart
- Create: outputs/wealthmate_flutter/test/auto_sync_regression_test.dart
- Create: outputs/wealthmate_flutter/test/app_lifecycle_sync_test.dart
- Modify: outputs/wealthmate_flutter/test/core/two_device_sync_test.dart
- Modify: outputs/wealthmate_flutter/test/dashboard_sync_status_test.dart

**Interfaces:**

- Consumes: existing FinanceStore, MemorySyncServer, SyncBarrier, local repositories and SyncQueue。
- Produces: failures for shared Future, continuous drain, failure stop, mutation callbacks, lifecycle triggers and remote merge silence。

- [ ] **Step 1: Define the scheduler contract in the test seam**

Use these exact types in the test seam so the implementation can remain independent of Flutter widgets:

~~~dart
typedef SyncPipeline = Future<bool> Function();
typedef SyncEligibility = bool Function();

class SyncScheduler {
  SyncScheduler({
    required SyncPipeline runPipeline,
    required SyncEligibility canRun,
    Duration debounce = const Duration(milliseconds: 250),
  });

  Future<void> request({String reason = 'unknown', bool immediate = false});
  bool get isActive;
  void dispose();
}
~~~

- [ ] **Step 2: Write the shared-Future RED test**

Block the first push, call first = store.sync(), call second = store.sync() while active, assert identical(first, second), and assert both callers remain pending until the current pipeline and all successful dirty rounds finish.

- [ ] **Step 3: Write the continuous-drain RED test**

Use successive push barriers. During round one mutate twice, release it, assert round two sends the latest snapshot; during round two mutate again, release it, assert round three runs. Assert no overlapping push/pull pipeline and no hard one-round limit.

- [ ] **Step 4: Write the failure-stop RED test**

Fail push once. Assert the shared Future completes after one failed pipeline, queue/cursor/prior success time are retained, and a bounded delay does not trigger another push. Then issue an explicit request and assert the retry occurs.

- [ ] **Step 5: Write local mutation coverage**

With a real FinanceStore and MemorySyncServer, assert ordinary transaction add/update/delete, account add/update, category add/update/archive, budget upsert and QuickEntry confirmation all request automatic sync only after local state plus queue persistence succeeds. Assert repeated calls are debounced/coalesced.

- [ ] **Step 6: Write remote merge silence coverage**

Have B create and push a transaction; have A pull and merge it. Assert A has no new local SyncOperation, no extra push from the merge path, and the local mutation callback counter remains zero.

- [ ] **Step 7: Write lifecycle RED tests**

Mount an authenticated non-demo store and assert startup/login and AppLifecycleState.resumed request sync. Assert a 30-second timer fires only while foreground and is cancelled on paused/inactive/detached. Assert lifecycle requests while active reuse the same drain Future.

- [ ] **Step 8: Run and commit all client RED tests**

Run: flutter test test/sync_scheduler_test.dart test/auto_sync_regression_test.dart test/app_lifecycle_sync_test.dart

Expected: failures identify absent scheduler, early-return Future, absent continuous drain, missing automatic mutation callback, merge feedback, or lifecycle behavior.

~~~powershell
git add outputs/wealthmate_flutter/test/sync_scheduler_test.dart outputs/wealthmate_flutter/test/auto_sync_regression_test.dart outputs/wealthmate_flutter/test/app_lifecycle_sync_test.dart outputs/wealthmate_flutter/test/core/two_device_sync_test.dart outputs/wealthmate_flutter/test/dashboard_sync_status_test.dart
git commit -m "test: define v1.0.4 sync drain and lifecycle invariants"
~~~

### Task 3: Add App Update downloader, installer and UI RED tests

**Files:**

- Create: outputs/wealthmate_flutter/test/features/app_update/app_update_download_test.dart
- Modify: outputs/wealthmate_flutter/test/features/app_update/app_update_store_test.dart
- Modify: outputs/wealthmate_flutter/test/app_update_flow_test.dart
- Create: outputs/wealthmate_flutter/test/features/app_update/android_installer_contract_test.dart

**Interfaces:**

- Consumes: AppVersion, existing AppUpdateStore test doubles and injected downloader/installer seams。
- Produces: failures for in-app HTTPS download, progress, retry, cancellation, installer permission flow and browser independence。

- [ ] **Step 1: Write downloader progress/failure RED tests**

Use an injected fake HTTP client or local test server to assert progress callbacks, non-2xx failure, short-response failure, .part cleanup, cancellation and app-specific destination. Count external launcher calls and assert the primary path does not invoke it.

- [ ] **Step 2: Write AppUpdateStore state RED tests**

Assert checking -> available -> downloading -> downloaded -> installing, waitingForPermission on installer result, failed on network error, retry creates a new task, and a second download call while active returns the same Future and starts one download.

~~~dart
expect(store.status, AppUpdateStatus.downloading);
expect(store.progress, closeTo(0.5, 0.01));
expect(identical(first, second), isTrue);
~~~

- [ ] **Step 3: Write UI RED tests**

Assert update dialog renders downloading percentage, downloaded-ready, installing, waiting-for-permission, failure/retry and user-readable error messages. Assert ordinary updates offer 稍后 and forced updates do not.

- [ ] **Step 4: Write Android installer contract RED tests**

Mock MethodChannel calls and assert installApk is the primary action, the MIME is application/vnd.android.package-archive, a waitingForPermission result preserves the cached path, resume retries without redownload, and external URL fallback is called only for unsupported native installation.

- [ ] **Step 5: Run and commit all update RED tests**

Run: flutter test test/features/app_update/app_update_download_test.dart test/features/app_update/app_update_store_test.dart test/features/app_update/android_installer_contract_test.dart test/app_update_flow_test.dart

Expected: failures identify the absent downloader/state-machine/MethodChannel UI behavior. These are test-only commits; no business implementation starts before Tasks 1–3 are complete.

~~~powershell
git add outputs/wealthmate_flutter/test/features/app_update outputs/wealthmate_flutter/test/app_update_flow_test.dart
git commit -m "test: define in-app Android update invariants"
~~~

---

## Implementation 阶段：只在 RED 测试提交后开始

### Task 4: Implement locked PostgreSQL version allocation

**Files:**

- Modify: outputs/wealthmate_backend/app/sync/service.py
- Modify: outputs/wealthmate_backend/tests/test_sync_postgres_concurrency.py

**Interfaces:**

- Consumes: Task 1 isolated database fixture and SyncPushIn operations。
- Produces: push(payload, db, user) that locks one refreshed User row per batch and returns a truthful watermark。

- [ ] **Step 1: Add the lock-and-refresh helper**

Implement def _lock_current_user(db: Session, user_id: str) -> User. Use a locked select with populate_existing and refresh the returned object explicitly.

~~~python
def _lock_current_user(db: Session, user_id: str) -> User:
    locked = db.execute(
        select(User)
        .where(User.id == user_id)
        .with_for_update()
        .execution_options(populate_existing=True)
    ).scalar_one()
    db.refresh(locked)
    return locked
~~~

- [ ] **Step 2: Recheck receipts and entities after the lock**

Call the helper once per push transaction before ordered operations. For every operation, re-run the SyncOperation lookup and read the entity from the locked session’s current database state before conflict checking. A receipt found after lock wait returns created=False with its original version.

- [ ] **Step 3: Allocate unique versions and commit once**

For each accepted operation increment and flush the locked User, pass that exact version to entity and receipt writes, and keep one final db.commit() for the batch. Any exception must roll back entity, receipt and User version together.

- [ ] **Step 4: Run the PostgreSQL regression**

Run: pytest -q tests/test_sync_postgres_concurrency.py -vv

Expected: PASS on isolated PostgreSQL for unique strict versions, final User watermark, both old-cursor rows, locked User freshness, idempotency and rollback. A missing database remains NOT VERIFIED.

- [ ] **Step 5: Commit backend implementation**

~~~powershell
git add outputs/wealthmate_backend/app/sync/service.py outputs/wealthmate_backend/tests/test_sync_postgres_concurrency.py
git commit -m "fix: serialize sync versions per user transaction"
~~~

### Task 5: Implement client SyncScheduler and mutation boundary

**Files:**

- Create: outputs/wealthmate_flutter/lib/core/sync/sync_scheduler.dart
- Modify: outputs/wealthmate_flutter/lib/state/finance_store.dart
- Modify: outputs/wealthmate_flutter/lib/features/ledger/state/ledger_store.dart
- Modify: outputs/wealthmate_flutter/lib/features/assets/state/asset_store.dart
- Modify: outputs/wealthmate_flutter/lib/features/budget/state/budget_store.dart
- Modify: outputs/wealthmate_flutter/lib/features/quick_entry/state/quick_entry_store.dart
- Modify: outputs/wealthmate_flutter/lib/core/sync/sync_coordinator.dart
- Modify: outputs/wealthmate_flutter/test/auto_sync_regression_test.dart

**Interfaces:**

- Consumes: Task 2 RED tests and existing repository/session write paths。
- Produces: FinanceStore.requestSync(String reason, {bool immediate = false}) -> Future<void>, FinanceStore.sync() -> Future<void>, and per-store void Function(String reason)? onLocalMutation。

- [ ] **Step 1: Implement shared Future and debounce**

Maintain _dirty, _drainFuture, _active and a cancellable debounce Timer. When active, request sets dirty and returns the exact existing drain Future. When idle, it creates one Future and schedules immediate or debounced execution.

- [ ] **Step 2: Implement the continuous successful drain**

Clear dirty at the start of each round; run exactly one repository push + pull; if the round succeeds and a mutation marked dirty during any await boundary, continue the loop. Exit only when the session is still valid and dirty is false.

- [ ] **Step 3: Stop after one failed round**

If the round returns a sync error, complete the shared Future after persisting the error and exit. Leave dirty/queue state for the next external request, but do not retry inside the loop or schedule an internal busy retry.

- [ ] **Step 4: Wire local mutation callbacks**

Call onLocalMutation only after LocalStateSession.write has persisted both state and queue. Wire Ledger, account Assets and Budget changes; exclude exchange-rate/default-account changes with no SyncOperation. Remove QuickEntry postConfirm direct sync so confirmation emits one Ledger mutation.

- [ ] **Step 5: Preserve remote merge silence and diagnostics**

Keep remote state adoption on the existing state callback only. Never call onLocalMutation from adoptState, pull merge, server version update, cursor persistence, receipt completion, owner binding or state restore. Add safe debug metadata for cursor, queue count, watermark and final cursor without JWT or passwords.

- [ ] **Step 6: Run client RED and existing sync tests**

Run: flutter test test/sync_scheduler_test.dart test/auto_sync_regression_test.dart test/core/two_device_sync_test.dart test/dashboard_sync_status_test.dart

- [ ] **Step 7: Commit the scheduler implementation**

~~~powershell
git add outputs/wealthmate_flutter/lib/core/sync/sync_scheduler.dart outputs/wealthmate_flutter/lib/state/finance_store.dart outputs/wealthmate_flutter/lib/features/ledger/state/ledger_store.dart outputs/wealthmate_flutter/lib/features/assets/state/asset_store.dart outputs/wealthmate_flutter/lib/features/budget/state/budget_store.dart outputs/wealthmate_flutter/lib/features/quick_entry/state/quick_entry_store.dart outputs/wealthmate_flutter/lib/core/sync/sync_coordinator.dart outputs/wealthmate_flutter/test
git commit -m "fix: drain local sync requests without dropping mutations"
~~~

### Task 6: Implement lifecycle foreground sync

**Files:**

- Modify: outputs/wealthmate_flutter/lib/ui/app_shell.dart
- Modify: outputs/wealthmate_flutter/lib/main.dart
- Create/Modify: outputs/wealthmate_flutter/test/app_lifecycle_sync_test.dart

**Interfaces:**

- Consumes: Task 5 FinanceStore.requestSync and AppLifecycleState。
- Produces: login/cold-start sync, resume sync, 30-second foreground timer and no background timer activity。

- [ ] **Step 1: Register and remove the lifecycle observer**

Register WidgetsBindingObserver in initState and remove it in dispose. Track a foreground flag and cancel the periodic timer for paused, inactive and detached.

- [ ] **Step 2: Trigger login/start/resume requests**

After authenticated profile loading, call requestSync with immediate=true. On resumed call the same API and start the timer. Any duplicate active request returns the existing drain Future.

- [ ] **Step 3: Gate the foreground timer**

Use Timer.periodic(const Duration(seconds: 30), ...) only while API is configured, owner is bound, App is foreground and no active sync is visible. The scheduler remains the final concurrency guard.

- [ ] **Step 4: Run lifecycle tests**

Run: flutter test test/app_lifecycle_sync_test.dart test/auth_sync_gate_test.dart test/startup_cursor_recovery_test.dart test/core/two_device_sync_test.dart

- [ ] **Step 5: Commit lifecycle implementation**

~~~powershell
git add outputs/wealthmate_flutter/lib/ui/app_shell.dart outputs/wealthmate_flutter/lib/main.dart outputs/wealthmate_flutter/test/app_lifecycle_sync_test.dart
git commit -m "feat: sync on login resume and foreground activity"
~~~

### Task 7: Implement App Update downloader and state machine

**Files:**

- Create: outputs/wealthmate_flutter/lib/features/app_update/data/app_update_downloader.dart
- Create: outputs/wealthmate_flutter/lib/features/app_update/data/app_update_installer.dart
- Modify: outputs/wealthmate_flutter/lib/features/app_update/state/app_update_store.dart
- Modify: outputs/wealthmate_flutter/test/features/app_update/app_update_download_test.dart
- Modify: outputs/wealthmate_flutter/test/features/app_update/app_update_store_test.dart

**Interfaces:**

- Consumes: Task 3 RED tests and AppVersion.downloadUrl。
- Produces: downloader.download(...)->Future<String>, installer.install(String apkPath)->Future<InstallOutcome>, progress and status transitions。

- [ ] **Step 1: Implement the app-specific HTTPS downloader**

Use Dart HttpClient, require an https URI, stream to a .part file under app cache/files, report received bytes and optional total, flush/close, then rename to a stable APK path. Delete partial files on every error and expose cancellation.

- [ ] **Step 2: Implement installer abstraction**

Define the following contract and a MethodChannel-backed default implementation:

~~~dart
enum InstallOutcome { started, waitingForPermission, unsupported, failed }

abstract interface class AppUpdateInstaller {
  Future<InstallOutcome> install(String apkPath);
}
~~~

Keep the cached path for waitingForPermission and provide resumeInstall without another download.

- [ ] **Step 3: Implement AppUpdateStore task sharing**

Add downloading, downloaded, installing, waitingForPermission and failed. Reject duplicate download tasks by returning the current task Future. Use the external URL only after native installer reports unsupported.

- [ ] **Step 4: Run update unit tests**

Run: flutter test test/features/app_update/app_update_download_test.dart test/features/app_update/app_update_store_test.dart

- [ ] **Step 5: Commit downloader/state implementation**

~~~powershell
git add outputs/wealthmate_flutter/lib/features/app_update outputs/wealthmate_flutter/test/features/app_update
git commit -m "feat: download app updates inside the app"
~~~

### Task 8: Implement Android FileProvider installer and update UI

**Files:**

- Modify: outputs/wealthmate_flutter/android/app/src/main/kotlin/com/example/wealthmate_flutter/MainActivity.kt
- Modify: outputs/wealthmate_flutter/android/app/src/main/AndroidManifest.xml
- Create: outputs/wealthmate_flutter/android/app/src/main/res/xml/file_paths.xml
- Modify: outputs/wealthmate_flutter/lib/ui/app_update_dialog.dart
- Modify: outputs/wealthmate_flutter/lib/ui/settings_page.dart
- Modify: outputs/wealthmate_flutter/lib/main.dart
- Modify: outputs/wealthmate_flutter/test/app_update_flow_test.dart

**Interfaces:**

- Consumes: Task 7 AppUpdateInstaller, InstallOutcome, cached APK path and store status。
- Produces: Android MethodChannel com.example.wealthmate_flutter/app_update method installApk。

- [ ] **Step 1: Add provider and install permission configuration**

Declare REQUEST_INSTALL_PACKAGES and a non-exported FileProvider whose authority is the application package plus .fileprovider. Restrict file_paths.xml to app cache/files; add no storage permission.

- [ ] **Step 2: Implement Kotlin installApk**

Register the channel in MainActivity.configureFlutterEngine. Validate the path is a regular file in the app-owned directory. On Android O+ if canRequestPackageInstalls is false, launch ACTION_MANAGE_UNKNOWN_APP_SOURCES for this package and return waitingForPermission. Otherwise create a content URI and launch ACTION_VIEW with MIME application/vnd.android.package-archive and temporary read permission.

- [ ] **Step 3: Resume after permission return**

On app resume call updates.resumeInstall when status is waitingForPermission or downloaded. Keep the APK and map results to user-readable messages.

- [ ] **Step 4: Update dialog and Settings**

Replace the external launcher as the primary action with the store download/install action. Display progress, retry, cancel, downloaded-ready and permission messages. Disable duplicate actions, preserve ordinary “稍后” and forced-update blocking.

- [ ] **Step 5: Run Android/UI tests and analyze**

Run: flutter test test/app_update_flow_test.dart test/features/app_update/android_installer_contract_test.dart test/features/app_update/app_update_store_test.dart; then flutter analyze.

- [ ] **Step 6: Commit Android installer/UI**

~~~powershell
git add outputs/wealthmate_flutter/android/app/src/main outputs/wealthmate_flutter/lib/main.dart outputs/wealthmate_flutter/lib/ui/app_update_dialog.dart outputs/wealthmate_flutter/lib/ui/settings_page.dart outputs/wealthmate_flutter/test/app_update_flow_test.dart
git commit -m "feat: install APK updates with Android package installer"
~~~

### Task 9: Align V1.0.4 metadata and release documentation

**Files:**

- Modify: outputs/wealthmate_flutter/pubspec.yaml
- Modify: outputs/wealthmate_flutter/lib/core/config/app_config.dart
- Modify: outputs/wealthmate_flutter/windows/runner/Runner.rc
- Modify: outputs/wealthmate_backend/app/config.py
- Modify: outputs/wealthmate_backend/docker-compose.yml
- Modify/Create: version tests and docs/release/v1.0.4-*.md

**Interfaces:**

- Consumes: current highest committed build number and existing release scripts。
- Produces: consistent 1.0.4+7 metadata unless a higher build exists, without changing production runtime settings。

- [ ] **Step 1: Calculate the next build**

Read all existing version sources. If the highest current build is 6, use versionName 1.0.4 and versionCode/build 7; if a higher integer exists, use the next higher integer everywhere.

- [ ] **Step 2: Update version tests**

Replace stale V1.0.3 assertions with V1.0.4 expectations and add cross-file consistency checks. Keep historical release evidence unchanged and add V1.0.4 evidence files.

- [ ] **Step 3: Validate synthetic direct APK metadata**

Test /app/version with an HTTPS direct APK URL such as https://download.invalid/releases/suixiangji-v1.0.4.apk. Do not change the real production environment or endpoint.

- [ ] **Step 4: Run metadata tests**

Run: pytest -q tests/test_app_version.py tests/test_v1_0_3_release_metadata.py; flutter test test/v1.0.4_version_test.dart

- [ ] **Step 5: Commit metadata and docs**

~~~powershell
git add outputs/wealthmate_flutter/pubspec.yaml outputs/wealthmate_flutter/lib/core/config/app_config.dart outputs/wealthmate_flutter/windows/runner/Runner.rc outputs/wealthmate_backend/app/config.py outputs/wealthmate_backend/docker-compose.yml outputs/wealthmate_backend/tests outputs/wealthmate_flutter/test docs/release
git commit -m "chore: align v1.0.4 release metadata"
~~~

### Task 10: Complete regression, isolated integration, release APK and evidence

**Files:**

- Modify: docs/release/v1.0.4-test-evidence.md
- Modify: docs/release/v1.0.4-signing-evidence.md
- Modify: docs/release/v1.0.4-device-acceptance.md

**Interfaces:**

- Consumes: all previous tasks, existing build/signing inspectors, Docker Compose and SDK paths。
- Produces: actual test/build/device evidence and a clean branch status without production deployment。

- [ ] **Step 1: Run full backend pytest with a writable task temp root**

Run pytest -q with a task-scoped writable temp directory if the default Windows temp ACL remains inaccessible. Record actual assertion failures separately from fixture permission errors.

- [ ] **Step 2: Run isolated real PostgreSQL integration**

Start only an isolated Compose project with synthetic credentials and project name. Run the new PostgreSQL concurrency test and integration/postgres_acceptance.py; inspect only synthetic rows.

- [ ] **Step 3: Run Flutter complete verification**

From outputs/wealthmate_flutter run flutter analyze and flutter test. Confirm existing sync/cursor/conflict/auth tests and all V1.0.4 tests.

- [ ] **Step 4: Build the signed production-configured APK**

Use the existing release script with production API configuration and the external authorized WEALTHMATE_SIGNING_PROPERTIES_PATH. Do not print property values; keep APK output outside Git.

- [ ] **Step 5: Inspect metadata and signature**

Use the existing inspector on V1.0.4 and the external V1.0.3 artifact. Compare package, version, build, APK SHA-256 and signing certificate SHA-256; certificate and applicationId must match.

- [ ] **Step 6: Attempt overlay install only with an authorized device**

Use adb install -r only. Never uninstall, downgrade or clear data. Verify version, login, SQLite/Drift data, queue/cursor, sync and in-app update. Without a real device or valid direct APK URL, record NOT VERIFIED with the exact missing condition.

- [ ] **Step 7: Write and verify evidence**

Record root causes, changed files, Future/drain semantics, A/B results, PostgreSQL result, update architecture, Chrome independence, version, test counts, APK path/size/SHA-256, signature, device status, branch, final commit and git status. Run git diff --check and git status --short --branch after the evidence edit.

~~~powershell
git add docs/release
git commit -m "docs: record v1.0.4 verification evidence"
git status --short --branch
~~~

