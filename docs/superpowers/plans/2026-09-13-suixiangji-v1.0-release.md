# 随想记 V1.0.0 Release Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在不改变 Beta 数据和 Sync 协议的前提下，完成集中 API 域名配置、App 内版本更新提醒、`1.0.0+3` 版本冻结和可审计的 Git 收口。

**Architecture:** Flutter 通过集中 `AppConfig` 读取环境注入的 API 基址；独立 App Update 模块通过匿名版本接口获取静态发布信息。版本升级只按 build number 判定，更新检查与本地财务状态、认证和 Sync 解耦。

**Tech Stack:** Flutter/Dart, `package_info_plus`, `url_launcher`, FastAPI, Pydantic Settings, pytest, unittest, Flutter test, Node test, Git。

**Spec:** `docs/superpowers/specs/2026-09-13-suixiangji-v1.0-release-design.md`

## Global Constraints

- 产品版本：`1.0.0`。
- Flutter 版本：`1.0.0+3`；Android versionName `1.0.0`；Android versionCode `3`。
- 版本升级判断：仅当 `remote_build > local_build` 时可更新。
- 正式 API 域名未提供时保持 `PRODUCTION DOMAIN: NOT CONFIGURED`，禁止猜测域名、localhost、IP 或 example.com 作为正式地址。
- APK 直接覆盖安装必须有相同 applicationId、相同签名 SHA-256 和更高 versionCode 的证据；没有证据时为 `APK UPDATE SIGNING: NOT VERIFIED`。
- 不修改 `0001_legacy_baseline`、`0002_beta_users`、Beta 数据或 Sync 核心协议。
- 历史 Tag `modular-monolith-v1`、`sync-v1.0-rc1` 不删除。
- 旧分支和旧 worktree 只能在 main、tag、bundle、报告和安全审计全部完成后清理。

---

### Task 1: 集中 Flutter 运行配置与发布版本

**Files:**
- Create: `outputs/wealthmate_flutter/lib/core/config/app_config.dart`
- Modify: `outputs/wealthmate_flutter/pubspec.yaml`
- Test: `outputs/wealthmate_flutter/test/core/app_config_test.dart`

**Interfaces:**
- Produces `AppConfig.fromEnvironment()`, `AppConfig.forTesting(...)`, `AppEnvironment`, `apiBaseUrl`, `isProduction` and `configurationError`.

- [ ] **Step 1: Write the failing tests**

```dart
test('production rejects a non-HTTPS API base URL', () {
  final config = AppConfig.forTesting(
    environment: AppEnvironment.production,
    apiBaseUrl: 'http://127.0.0.1:18000',
  );
  expect(config.configurationError, contains('HTTPS'));
});

test('development accepts a local HTTP API base URL', () {
  final config = AppConfig.forTesting(
    environment: AppEnvironment.development,
    apiBaseUrl: 'http://127.0.0.1:18000',
  );
  expect(config.configurationError, isNull);
});
```

- [ ] **Step 2: Run the focused test and verify RED**

Run from `outputs/wealthmate_flutter`:

```text
flutter test test/core/app_config_test.dart
```

Expected: FAIL because `AppConfig` does not exist.

- [ ] **Step 3: Implement the minimal centralized configuration**

Read `WEALTHMATE_ENVIRONMENT` and `WEALTHMATE_API_BASE_URL` only in `app_config.dart`. Parse only `development`, `test` and `production`; return a configuration error for an invalid environment or a production URL that is not HTTPS. Keep an empty base URL usable as offline mode so missing production domain does not crash the App.

- [ ] **Step 4: Set the release version and add runtime package metadata**

Change `pubspec.yaml` to `version: 1.0.0+3` and add `package_info_plus` and `url_launcher`. Do not change `applicationId` in `android/app/build.gradle.kts`; its existing Flutter-derived `versionCode` and `versionName` must resolve to 3 and 1.0.0.

- [ ] **Step 5: Run focused tests and verify GREEN**

```text
flutter test test/core/app_config_test.dart
flutter analyze
```

Expected: focused tests pass and analyze reports no issues.

- [ ] **Step 6: Commit**

```text
git add outputs/wealthmate_flutter/lib/core/config/app_config.dart outputs/wealthmate_flutter/pubspec.yaml outputs/wealthmate_flutter/pubspec.lock outputs/wealthmate_flutter/test/core/app_config_test.dart
git commit -m "feat: centralize release API configuration"
```

### Task 2: Static Backend App Version Endpoint

**Files:**
- Create: `outputs/wealthmate_backend/app/release/__init__.py`
- Create: `outputs/wealthmate_backend/app/release/router.py`
- Create: `outputs/wealthmate_backend/app/release/schemas.py`
- Create: `outputs/wealthmate_backend/app/release/service.py`
- Modify: `outputs/wealthmate_backend/app/config.py`
- Modify: `outputs/wealthmate_backend/app/main.py`
- Modify: `outputs/wealthmate_backend/.env.example`
- Modify: `outputs/wealthmate_backend/docker-compose.yml`
- Test: `outputs/wealthmate_backend/tests/test_app_version.py`

**Interfaces:**
- Produces anonymous `GET /app/version` with `latest_version`, `latest_build`, `minimum_supported_version`, `minimum_supported_build`, `force_update`, `download_url` and `release_notes`.

- [ ] **Step 1: Write the failing endpoint tests**

```python
def test_app_version_returns_static_release_metadata(client, monkeypatch):
    settings = get_settings()
    monkeypatch.setattr(settings, "app_latest_version", "1.0.0")
    monkeypatch.setattr(settings, "app_latest_build", 3)
    monkeypatch.setattr(settings, "app_minimum_supported_version", "1.0.0")
    monkeypatch.setattr(settings, "app_minimum_supported_build", 3)
    monkeypatch.setattr(settings, "app_download_url", "")
    response = client.get("/app/version")
    assert response.status_code == 200
    assert response.json()["latest_build"] == 3
    assert response.json()["download_url"] is None

def test_production_rejects_non_https_download_url():
    settings = Settings(_env_file=None, environment="production",
                        jwt_secret="x" * 40,
                        cors_origins="https://app.invalid",
                        app_download_url="http://download.invalid/app.apk")
    with pytest.raises(ValueError, match="HTTPS"):
        settings.validate_runtime()
```

- [ ] **Step 2: Run the backend focused tests and verify RED**

```text
python -m pytest tests/test_app_version.py -q
```

Expected: collection or assertion failure because the release settings and route do not exist.

- [ ] **Step 3: Implement static settings and response schema**

Add typed settings with defaults `1.0.0`, build `3`, minimum build `3`, force `false`, empty download URL and empty release notes. Validate numeric semver shape and require HTTPS for non-empty Beta/production download URLs. Return `null` for an empty download URL. Do not import ORM models or call `ensure_schema` from this feature.

- [ ] **Step 4: Register the public route**

Create a release router and include it in `app.main`. Keep `/health`, auth routes, database initialization and all Sync routers unchanged.

- [ ] **Step 5: Run focused backend tests and verify GREEN**

```text
python -m pytest tests/test_app_version.py -q
python -m pytest tests/test_migrations.py tests/test_sync_acceptance.py -q
```

Expected: endpoint tests pass and migration/Sync tests remain green.

- [ ] **Step 6: Commit**

```text
git add outputs/wealthmate_backend/app/release outputs/wealthmate_backend/app/config.py outputs/wealthmate_backend/app/main.py outputs/wealthmate_backend/.env.example outputs/wealthmate_backend/docker-compose.yml outputs/wealthmate_backend/tests/test_app_version.py
git commit -m "feat: add static app version endpoint"
```

### Task 3: Build-First Flutter Update Domain and Remote Data Source

**Files:**
- Create: `outputs/wealthmate_flutter/lib/features/app_update/domain/app_version.dart`
- Create: `outputs/wealthmate_flutter/lib/features/app_update/data/app_update_remote_data_source.dart`
- Create: `outputs/wealthmate_flutter/lib/features/app_update/state/app_update_store.dart`
- Test: `outputs/wealthmate_flutter/test/features/app_update/app_version_test.dart`
- Test: `outputs/wealthmate_flutter/test/features/app_update/app_update_remote_data_source_test.dart`

**Interfaces:**
- `AppVersion` parses the endpoint and exposes `isUpdateAvailable(localBuild)` and `requiresForceUpdate(localBuild)`.
- `AppUpdateRemoteDataSource.fetch()` performs unauthenticated `GET /app/version` through `ApiSession`.
- `AppUpdateStore.check()` records `checking`, `available`, `upToDate` or `failed` without writing local finance state.

- [ ] **Step 1: Write the historical build-order tests**

```dart
test('Beta 1.2.0+2 sees formal 1.0.0+3 as an update', () {
  final remote = AppVersion.fromJson({
    'latest_version': '1.0.0',
    'latest_build': 3,
    'minimum_supported_version': '1.0.0',
    'minimum_supported_build': 3,
    'force_update': false,
    'download_url': 'https://download.invalid/app.apk',
    'release_notes': '正式版本',
  });
  expect(remote.isUpdateAvailable(2), isTrue);
});

test('a lower version name with an equal build is not an update', () {
  final remote = AppVersion.fromJson({
    'latest_version': '1.0.0',
    'latest_build': 3,
    'minimum_supported_version': '1.0.0',
    'minimum_supported_build': 3,
    'force_update': false,
    'download_url': 'https://download.invalid/app.apk',
    'release_notes': '正式版本',
  });
  expect(remote.isUpdateAvailable(3), isFalse);
});
```

- [ ] **Step 2: Run the focused tests and verify RED**

```text
flutter test test/features/app_update/app_version_test.dart
```

Expected: FAIL because the model and build-first comparison do not exist.

- [ ] **Step 3: Implement strict response parsing and build comparison**

Parse positive integer build values and numeric `major.minor.patch` display versions. Compare only `latest_build` with `localBuild`; use `minimum_supported_build` for force logic. Reject malformed or non-HTTPS download URLs as a server/configuration failure.

- [ ] **Step 4: Add remote source and store tests**

Assert the request path is `/app/version`, no Authorization header is sent, a network/format failure produces `failed`, and a valid response produces `available` or `upToDate`.

- [ ] **Step 5: Implement remote source and store**

Use `requestMapWithSession(..., includeAuth: false)`. Catch `ApiFailure` in the store, expose a user-safe message, and never throw from startup check into `runApp`.

- [ ] **Step 6: Run focused tests and verify GREEN**

```text
flutter test test/features/app_update
```

Expected: all App Update tests pass.

- [ ] **Step 7: Commit**

```text
git add outputs/wealthmate_flutter/lib/features/app_update outputs/wealthmate_flutter/test/features/app_update
git commit -m "feat: compare app updates by build number"
```

### Task 4: Startup Prompt, Settings UI and Safe APK Launch

**Files:**
- Create: `outputs/wealthmate_flutter/lib/ui/app_update_dialog.dart`
- Modify: `outputs/wealthmate_flutter/lib/main.dart`
- Modify: `outputs/wealthmate_flutter/lib/ui/app_shell.dart`
- Modify: `outputs/wealthmate_flutter/lib/ui/settings_page.dart`
- Test: `outputs/wealthmate_flutter/test/app_update_flow_test.dart`

**Interfaces:**
- `WealthMateApp` accepts an optional `AppUpdateStore` and checks it asynchronously after the first frame.
- `SettingsPage` displays current version/build and provides manual checking.
- `AppUpdateDialog` uses “稍后/立即更新” for normal updates and only “立即更新” for valid forced updates.

- [ ] **Step 1: Write widget tests**

Cover current version `1.0.0 (3)`, manual “检查更新”, normal update actions, forced update without “稍后”, and failed checks that leave the home screen usable.

- [ ] **Step 2: Run widget tests and verify RED**

```text
flutter test test/app_update_flow_test.dart
```

Expected: FAIL because the settings row, dialog and startup wiring do not exist.

- [ ] **Step 3: Wire package metadata and centralized config**

Read `PackageInfo.fromPlatform()` in `main.dart`, create the update store only when a configured API client exists, and pass the store/current metadata through `WealthMateApp` and `AppShell`. Preserve existing offline demo and authentication branches.

- [ ] **Step 4: Implement the non-blocking dialog and external HTTPS launch**

Show the dialog after a successful check on the first frame. Use `launchUrl(uri, mode: LaunchMode.externalApplication)` only for the validated HTTPS URL. If launch fails, show an error without changing local data. Do not add install permissions or silent installation logic.

- [ ] **Step 5: Run widget tests and verify GREEN**

```text
flutter test test/app_update_flow_test.dart
flutter test
flutter analyze
```

Expected: update flow tests and the complete Flutter suite pass with no analyzer issues.

- [ ] **Step 6: Commit**

```text
git add outputs/wealthmate_flutter/lib/main.dart outputs/wealthmate_flutter/lib/ui/app_shell.dart outputs/wealthmate_flutter/lib/ui/settings_page.dart outputs/wealthmate_flutter/lib/ui/app_update_dialog.dart outputs/wealthmate_flutter/pubspec.yaml outputs/wealthmate_flutter/pubspec.lock outputs/wealthmate_flutter/test/app_update_flow_test.dart
git commit -m "feat: add in-app update prompt and settings check"
```

### Task 5: Release Documentation and Beta Branch Semantic Audit

**Files:**
- Modify: `README.md`
- Modify: `outputs/wealthmate_flutter/README.md`
- Modify: `outputs/wealthmate_backend/.env.example`
- Create: `docs/PROJECT_STATE.md`
- Create: `docs/V1.0.0-GIT-CLEANUP-REPORT.md`

- [ ] **Step 1: Document environment examples without inventing a domain**

Document development/test commands with localhost only as non-production examples, the production `WEALTHMATE_API_BASE_URL` injection point, explicit production CORS, static version settings, APK HTTPS requirement, and `PRODUCTION DOMAIN: NOT CONFIGURED`.

- [ ] **Step 2: Record final project state fields**

Write `PROJECT_STATE.md` with product version `V1.0.0`, expected tag/branch, migration `0002_beta_users`, modular-monolith modules, no database rebuild, and the actual final commit only after merge/tag verification.

- [ ] **Step 3: Audit old branch content before any deletion**

Compare `feat/v1-user-system` commits `67e67db`, `2b3ec26` and `374a2c2` against current auth, registration, migration, tenant isolation, offline/relogin and Sync-session tests. Record commit SHA, main containment, semantic coverage, and deletion decision. Keep `feat/v1-admin` as `NOT VERIFIED` if absent.

- [ ] **Step 4: Commit documentation**

```text
git add README.md outputs/wealthmate_flutter/README.md outputs/wealthmate_backend/.env.example docs/PROJECT_STATE.md docs/V1.0.0-GIT-CLEANUP-REPORT.md
git commit -m "docs: record v1.0.0 release state and cleanup audit"
```

### Task 6: Full Verification, Signing Gate and Release Freeze

**Files:**
- Verify: `outputs/wealthmate_flutter/android/app/build.gradle.kts`
- Verify: `outputs/wealthmate_flutter/pubspec.yaml`
- Verify: `docs/PROJECT_STATE.md`
- Verify: `docs/V1.0.0-GIT-CLEANUP-REPORT.md`

- [ ] **Step 1: Run the complete regression suite**

```text
cd outputs/wealthmate_backend
python -m pytest -q --basetemp=E:\codex\suixiangji\work\pytest-basetemp
python -m unittest discover -s tests -q
cd ..\..\
npm test
cd outputs/wealthmate_flutter
flutter analyze
flutter test
cd ..\..\
git diff --check
```

Record actual counts and failures; do not replace numbers with “全部通过”.

- [ ] **Step 2: Verify Android metadata and certificate evidence without printing secrets**

Build the release candidate with version `1.0.0+3` only after tests pass. Use `apkanalyzer`/ `apksigner verify --print-certs` to record applicationId, versionCode and SHA-256 certificate fingerprints. Never print passwords, private keys or keystore contents. Compare with a discovered Beta APK; if no Beta APK/certificate evidence exists, record `APK UPDATE SIGNING: NOT VERIFIED` and stop before claiming direct-update support.

- [ ] **Step 3: Verify production-domain status**

Confirm no final domain was supplied. Keep release source/config tests complete, but record `PRODUCTION DOMAIN: NOT CONFIGURED`; never build a production artifact pointing at localhost, an IP or example.com.

- [ ] **Step 4: Merge and tag only after release gates**

Fast-forward local `main` to `origin/main`, merge `feat/v1-release`, run the final verification again, push `origin/main`, create annotated `v1.0.0`, push the tag, and confirm `main` and `v1.0.0` resolve to the same final SHA.

- [ ] **Step 5: Create and verify the full Git bundle**

Create `E:\codex\suixiangji-pre-v1.0.0-cleanup-2026-09-13.bundle` with all refs and run `git bundle verify` successfully. Keep the bundle outside the repository and out of Git.

- [ ] **Step 6: Delete only confirmed-safe development branches**

After the bundle, cleanup report, clean worktree, pushed main/tag and semantic audit, delete only confirmed-safe remote/local development branches. Do not delete main or either historical Tag; do not delete an admin branch/worktree containing unverified unique code.

- [ ] **Step 7: Final local-state verification**

```text
git fetch --prune
git branch -a
git worktree list
git status
git log --decorate --oneline -10
```

Expected final local state is branch `main`, one worktree, clean status, and HEAD equal to tag `v1.0.0`, subject to the signing/domain gates recorded above.

