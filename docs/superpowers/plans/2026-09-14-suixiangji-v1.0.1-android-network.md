# 随想记 V1.0.1 Android Network Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在不改变 Auth、Sync、Backend、数据库和 V1.0.0 的前提下，将 Android 生产 HTTP transport 切换为 Embedded Cronet，并发布可覆盖 V1.0.0 的 `1.0.1+4` 候选 APK。

**Architecture:** 保持 `ApiClient → ApiTransport → http.Client → RemoteDataSource` 单一链路。新增一个带条件导入的平台 HTTP factory：Android native 选择 `CronetClient`，Web 与其他平台选择现有 `package:http` client；`ApiClient` 保持 fake client 注入能力并只关闭自己创建的 client。

**Tech Stack:** Flutter/Dart、`package:http`、`cronet_http 1.9.0`、Embedded Cronet、Flutter test、Android device/ADB、FastAPI/pytest、Node test。

**Spec:** `docs/superpowers/specs/2026-09-14-suixiangji-v1.0.1-android-network-design.md`

## Global Constraints

- 分支必须为 `fix/v1.0.1-android-network`，基线为 `89fbe1ad0902772cb171a76a7fcb3a9444d5b4fd`。
- `v1.0.0` 必须继续指向 `72f05120a3f8ab0b3f68fbd8ee2c0b856d9af406`，不得移动或修改。
- 目标 Flutter 版本为 `1.0.1+4`，Android `versionName=1.0.1`、`versionCode=4`。
- `cronet_http` 必须锁定 `1.9.0`。
- 所有 Android `flutter run`、Android integration/test、CI Android Flutter 命令和 release build 必须带 `--dart-define=cronetHttpNoPlay=true`。
- Android 目标为 Embedded Cronet，Google Play Services required 为 `NO`。
- Cronet Engine 和 Client 每个 App 生命周期只创建一个；不得按请求或 RemoteDataSource 重复创建。
- `WidgetsFlutterBinding.ensureInitialized()` 必须早于 CronetEngine 创建。
- ApiClient 内部创建的 Client 由 `ApiClient.close()` 关闭；外部注入 fake/test Client 不关闭；Cronet 使用 `closeEngine: true`。
- 所有生产请求必须经过 `ApiTransport`；Feature/RemoteDataSource 不得创建第二套 HTTP 入口。
- 不修改 Auth/JWT、Sync 协议、`LocalStateSession`、`SyncCoordinator`、Backend、数据库、migration 或 API schema。
- 正式 API 必须使用 `https://api.suixiangji.icu`。
- APK 必须保持 applicationId `com.example.wealthmate_flutter` 和签名 SHA-256 `cadeb8ca7786b755305e07a086b407d8da7d6751d54566d9a0787d457df32458`。
- 真机测试使用 `adb install -r`，不得卸载当前 V1.0.0。
- 全部测试和真机验收通过前，不 merge 到 main、不创建 `v1.0.1` Tag、不更新服务器 `/app/version`、不替换下载 APK。

## Current Code Map

- `outputs/wealthmate_flutter/pubspec.yaml`: Flutter version and direct dependencies。
- `outputs/wealthmate_flutter/lib/main.dart`: Binding 初始化、唯一生产 `ApiClient` 组合入口、App 生命周期。
- `outputs/wealthmate_flutter/lib/data/api_client.dart`: 兼容 façade、默认 `http.Client` 创建、Auth/session/client ownership 边界。
- `outputs/wealthmate_flutter/lib/core/network/api_transport.dart`: URL、headers、JSON、错误映射、认证过期回调。
- `outputs/wealthmate_flutter/lib/core/network/api_session.dart`: session generation/token protection。
- `outputs/wealthmate_flutter/lib/features/*/data/*_remote_data_source.dart`: Auth、业务、Backup、Sync、版本请求，必须继续只调用 ApiClient/ApiTransport。
- `outputs/wealthmate_flutter/test/`: 现有 `ApiClient(client: fakeClient)`、Auth、Sync、版本和架构回归测试。
- `outputs/wealthmate_flutter/android/app/build.gradle.kts`: applicationId、versionName/versionCode、签名配置。
- `outputs/wealthmate_backend/`: Backend pytest，不应有业务代码改动。
- `tests/wealthmate.test.mjs`: Root/Web/PWA Node 测试，不应因 Flutter Cronet 依赖受影响。

## Task 1: Lock the implementation baseline

- [ ] Confirm the isolated branch and frozen tag before editing.

  Run from `E:/codex/suixiangji-v1.0.1-android-network`:

  ```powershell
  git branch --show-current
  git rev-parse HEAD
  git rev-parse 'v1.0.0^{}'
  git status --short --branch
  ```

  Expected:

  ```text
  fix/v1.0.1-android-network
  89fbe1ad0902772cb171a76a7fcb3a9444d5b4fd
  72f05120a3f8ab0b3f68fbd8ee2c0b856d9af406
  ```

- [ ] Keep the initial plan commit separate from implementation commits.

  ```powershell
  git add docs/superpowers/plans/2026-09-14-suixiangji-v1.0.1-android-network.md
  git commit -m "docs: add v1.0.1 Android network implementation plan"
  ```

## Task 2: RED — specify platform selection and Web isolation

- [ ] Add `test/core/network/http_client_factory_test.dart` before adding the factory implementation.

  The tests must exercise a testable platform-selection seam and assert:

  ```text
  Android selects Cronet transport.
  Non-Android selects package:http transport.
  Web selects package:http transport.
  Android selection does not construct a second client for repeated requests.
  ```

  Use fake client builders in host tests so the tests do not require Android JNI or a real Cronet engine.

- [ ] Run only the new test and verify a meaningful RED failure caused by the missing factory API, not a syntax or test setup error.

  ```powershell
  flutter test test/core/network/http_client_factory_test.dart
  ```

  Record the failing test names and failure reason in the implementation notes/commit message.

## Task 3: GREEN — implement platform-isolated factory

- [ ] Add a common factory façade and conditional implementations under `outputs/wealthmate_flutter/lib/core/network/`.

  The common API must expose a testable platform decision and a `http.Client`-compatible creation result. The conditional import must select native implementation for `dart.library.io`, Web implementation for `dart.library.js_interop`, and a fallback implementation for unsupported targets.

- [ ] Keep `package:cronet_http/cronet_http.dart` out of the Web and fallback implementation files.

- [ ] In the native implementation, select Cronet only when `defaultTargetPlatform == TargetPlatform.android`; select `http.Client()` for Windows, macOS and Linux.

- [ ] In the Android branch, defensively call `WidgetsFlutterBinding.ensureInitialized()` immediately before the first `CronetEngine.build()` call, then construct exactly one Engine and one `CronetClient` with:

  ```text
  cache disabled
  HTTP/2 enabled
  QUIC disabled
  closeEngine: true
  ```

- [ ] Run the factory test and verify GREEN.

  ```powershell
  flutter test test/core/network/http_client_factory_test.dart
  ```

- [ ] Run Web static analysis/build after the factory exists.

  ```powershell
  flutter analyze
  flutter build web --release
  ```

  The Web build must not import or execute `cronet_http`.

## Task 4: RED — specify ApiClient ownership and close behavior

- [ ] Extend `test/api_client_test.dart` with tests for:

  ```text
  an internally created client is closed exactly once by ApiClient.close()
  an externally injected fake client is not closed by ApiClient.close()
  repeated ApiClient.close() calls are safe
  ```

- [ ] Run the focused tests before production changes and verify the new tests fail for the missing lifecycle behavior.

  ```powershell
  flutter test test/api_client_test.dart
  ```

## Task 5: GREEN — connect factory and lifecycle without changing request semantics

- [ ] Add `cronet_http: 1.9.0` to `outputs/wealthmate_flutter/pubspec.yaml` without upgrading unrelated direct dependencies.

- [ ] Run dependency resolution and confirm the lockfile contains `cronet_http 1.9.0`.

  ```powershell
  flutter pub get
  flutter pub deps --style=compact | Select-String "cronet_http"
  ```

- [ ] Modify `ApiClient` only to:

  ```text
  use the platform factory when client is omitted
  preserve client: fakeClient injection
  record whether the client is owned
  add an idempotent close() for owned clients only
  ```

- [ ] Keep `ApiTransport`, `ApiSession`, all RemoteDataSource code, headers, auth retry, status mapping and JSON handling unchanged.

- [ ] Ensure `main.dart` keeps `WidgetsFlutterBinding.ensureInitialized()` before database and ApiClient construction, and arrange App shutdown to close the owned ApiClient.

- [ ] Run the focused ApiClient tests and verify GREEN.

  ```powershell
  flutter test test/api_client_test.dart
  ```

- [ ] Commit the completed transport/lifecycle slice.

  ```powershell
  git add outputs/wealthmate_flutter/pubspec.yaml outputs/wealthmate_flutter/pubspec.lock outputs/wealthmate_flutter/lib/core/network outputs/wealthmate_flutter/lib/data/api_client.dart outputs/wealthmate_flutter/lib/main.dart outputs/wealthmate_flutter/test/core/network/http_client_factory_test.dart outputs/wealthmate_flutter/test/api_client_test.dart
  git commit -m "fix: use embedded Cronet for Android HTTP"
  ```

## Task 6: RED/GREEN — protect the single network boundary

- [ ] Add or extend an architecture test that scans production Flutter code and permits production `http.Client()` creation only in the platform factory implementation.

- [ ] Add an assertion that feature and RemoteDataSource files contain no direct `cronet_http` import, `http.Client(` construction, `dart:io` HTTP client construction, or second transport entry.

- [ ] Run the architecture test and fix only the minimum production boundary issue it reveals.

  ```powershell
  flutter test test/architecture/module_boundaries_test.dart
  ```

- [ ] Commit the guard separately.

  ```powershell
  git add outputs/wealthmate_flutter/test/architecture/module_boundaries_test.dart
  git commit -m "test: guard the unified HTTP transport boundary"
  ```

## Task 7: Regression verification of preserved behavior

- [ ] Run the full Flutter test suite and record the exact test count and failures.

  ```powershell
  flutter test
  ```

- [ ] Run Flutter analysis.

  ```powershell
  flutter analyze
  ```

- [ ] Run Backend tests using a worktree-local pytest base directory to avoid the known Windows temp permission issue.

  ```powershell
  $tempPath = 'E:\codex\suixiangji-v1.0.1-android-network\.pytest-tmp-v101'
  New-Item -ItemType Directory -Force -Path $tempPath | Out-Null
  python -m pytest -q --basetemp=$tempPath
  ```

- [ ] Run root tests.

  ```powershell
  npm test
  ```

- [ ] Confirm no Backend, migration, database, API schema, Auth, JWT or Sync files are in the diff.

## Task 8: Version and Android build configuration

- [ ] Update Flutter version to `1.0.1+4` only on this feature branch.

- [ ] Verify Android continues to derive `versionName=1.0.1` and `versionCode=4` from Flutter build values, with applicationId `com.example.wealthmate_flutter`.

- [ ] Do not create `v1.0.1` yet.

- [ ] Add/update the Android execution/build documentation or CI command template so every relevant Android command visibly contains:

  ```text
  --dart-define=cronetHttpNoPlay=true
  ```

- [ ] Reject any Android build command without the Embedded Cronet define.

## Task 9: Android Embedded Cronet candidate APK

- [ ] Build only from the feature branch using both required defines:

  ```powershell
  flutter build apk --release --dart-define=WEALTHMATE_ENVIRONMENT=production --dart-define=WEALTHMATE_API_BASE_URL=https://api.suixiangji.icu --dart-define=cronetHttpNoPlay=true
  ```

- [ ] Inspect the APK and report:

  ```text
  versionName: 1.0.1
  versionCode: 4
  applicationId: com.example.wealthmate_flutter
  Cronet distribution: Embedded
  Google Play Services required: NO
  APK SHA-256: actual value
  signing SHA-256: actual value
  ```

- [ ] Stop immediately if signing SHA-256 differs from:

  ```text
  cadeb8ca7786b755305e07a086b407d8da7d6751d54566d9a0787d457df32458
  ```

- [ ] Keep the V1.0.0 APK and do not uninstall the device app.

## Task 10: Device overwrite and regression acceptance

- [ ] Verify the device currently has V1.0.0+3 and install the candidate with overwrite only:

  ```powershell
  adb install -r E:\\codex\\suixiangji-v1.0.1-android-network\\outputs\\wealthmate_flutter\\build\\app\\outputs\\flutter-apk\\app-release.apk
  ```

- [ ] Verify local data survives the overwrite.

- [ ] Execute the required data flow in order:

  ```text
  original account login
  server data restoration
  create transaction: “V1.0.1 Cronet 真机验收”, amount 0.01
  sync
  close and restart app
  verify data remains
  logout
  relogin
  verify data resynchronizes
  /app/version
  Wi-Fi
  mobile data
  ```

- [ ] Capture the actual test evidence. Any unavailable item must be `NOT VERIFIED`.

## Task 11: Candidate release gate

- [ ] Review the entire diff against the design spec and verify the only functional production change is Android HTTP transport plus lifecycle/version/build plumbing.

- [ ] Run the final required automated commands again on the exact candidate source:

  ```text
  flutter analyze
  flutter test
  Web test/build
  Backend pytest
  Root npm test
  Architecture tests
  ```

- [ ] Confirm `v1.0.0` still points to `72f05120a3f8ab0b3f68fbd8ee2c0b856d9af406`.

- [ ] Produce the candidate release report with real numbers and explicit `NOT VERIFIED` values for anything not executed.

- [ ] Do not merge, push, create `v1.0.1`, update `/app/version`, upload or replace the official APK until the user authorizes release after reviewing the candidate report.
