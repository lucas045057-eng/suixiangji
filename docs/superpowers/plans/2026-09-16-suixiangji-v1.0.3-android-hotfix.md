# [Suixiangji V1.0.3 Android Hotfix] Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在不改写 V1.0.2 Tag/Release、不修改数据库且不绕过签名证据的前提下，修复随想记 Android 发布事故，产出可覆盖安装、使用生产 API 的 V1.0.3 build 6，并完成自动化、真实设备和生产验收。

**Architecture:** 以 `main @ c283a001bf57ac8b1b5cd33e5476e4577edf8e7d` 为代码基线创建 `hotfix/v1.0.3-android-release`。把生产发布参数收敛到一个可验证的 PowerShell 构建入口；Android release variant 从受控外部签名配置读取正式证书；Flutter 与 Backend 共享明确的 `1.0.3 / 6` 版本目标；生产更新元数据采用“先降曝光、后上传 APK、最后切换 latest”的顺序。

**Tech Stack:** Flutter/Dart, Android Gradle Kotlin DSL, PowerShell, Python/FastAPI tests, npm tests, Docker Compose, PostgreSQL health checks, Android SDK `apkanalyzer`/`apksigner`, GitHub Git over HTTPS or SSH.

**Spec:** `docs/superpowers/specs/2026-09-16-suixiangji-v1.0.3-android-hotfix-design.md`

## Global Constraints

- 当前生产服务器为 `root@47.98.183.77`，项目目录为 `/opt/suixiangji/app`。
- 不删除、移动、重写或重新指向 `v1.0.2` Tag/Release；不 force push。
- 不修改数据库 schema、数据、迁移文件或 PostgreSQL 容器；只在 API 发布需要时重启 API 服务。
- 真实签名私钥不可验证时，立即输出 `RELEASE BLOCKED: ORIGINAL SIGNING PRIVATE KEY NOT AVAILABLE` 并停止所有发布动作。
- 两台真实 Android 设备无法完成覆盖安装和双设备同步时，记录 `REAL TWO-DEVICE TEST: NOT RUN` 并将发布结论标为 BLOCKED。
- 不使用卸载旧 App、清除数据、修改 applicationId 或 debug 签名来绕过覆盖安装问题。
- 正式 Flutter 构建必须包含：`WEALTHMATE_ENVIRONMENT=production`、`WEALTHMATE_API_BASE_URL=https://api.suixiangji.icu`、`cronetHttpNoPlay=true`。
- 目标版本固定为 Flutter `1.0.3+6`、运行时 `1.0.3 / 6`；minimum supported 固定为 `1.0.0 / 3`，`force_update=false`。
- 任何 Flutter 测试因 Windows Developer Mode / symlink 无法执行时，原样记录 `BLOCKED: Windows Developer Mode / symlink requirement`，不得标记 PASS。
- secret、keystore 私钥和密码只从受控本机/CI 读取，不能进入仓库、补丁、命令输出或最终报告。

---

## Task 1: 暂停线上 V1.0.2 错误 APK 更新曝光

**Files:** 生产文件 `/opt/suixiangji/app/outputs/wealthmate_backend/.env`；备份目录 `/opt/suixiangji/release-backups/v1.0.3-20260916/`。不改仓库代码。

- [ ] 读取并记录生产当前代码 SHA、API compose 文件、当前 `/app/version`，确认当前 latest 是 `1.0.2 / 5`，确认 V1.0.2 文件仍保留。
- [ ] 在服务器创建权限为 `600`、root 所有的 `wealthmate_backend.env.before-v1.0.3`，目标已存在时停止，不覆盖历史备份。
- [ ] 仅将更新字段改为 `1.0.1 / 4`、minimum `1.0.0 / 3`、`force_update=false`，下载地址指向现存的 `suixiangji-v1.0.1-build4.apk`；保留当前 API 代码 SHA 和其余环境变量。
- [ ] 使用现有 API compose 配置重启 API 服务，不执行 PostgreSQL 重建、迁移或重启。
- [ ] 从公网验证 `/app/version` 返回 `1.0.1 / 4`、`force_update=false`、可下载的 V1.0.1 地址；验证 `/health` HTTP 200、PostgreSQL healthy，并记录 V1.0.2 服务器文件未被删除。
- [ ] 只读检查 V1.0.2 Tag 对象和 GitHub Release 页面仍指向原版本；不执行任何修改命令。
- [ ] 将暂停动作作为后续 hotfix 分支的首个运维证据记录，不在此步骤创建 V1.0.3 Tag/Release。

**Verification:** `/app/version` 公网响应为 `latest_version=1.0.1`、`latest_build=4`；API health 和数据库 health PASS；V1.0.2 历史 APK、Tag、Release 均存在。

**Commit:** 无仓库提交；这是实施前的生产保护动作。

## Task 2: 建立 V1.0.3 分支与签名证据检查

**Files:** `.gitignore`（仅在需要忽略签名文件且现有规则不足时修改）、`docs/release/v1.0.3-signing-evidence.md`、`tools/inspect-android-signing.ps1`。

- [ ] 确认工作树干净、`main` 和 `origin/main` 均为 `c283a001bf57ac8b1b5cd33e5476e4577edf8e7d`，确认 `v1.0.2` Tag 对象 SHA 不变。
- [ ] 从该 SHA 创建 `hotfix/v1.0.3-android-release`，不把无关历史合并进来。
- [ ] 编写签名检查脚本，输入 APK 路径和 Android SDK 工具路径，输出包名、versionName、versionCode、APK SHA-256、签名证书 SHA-256；脚本禁止输出 keystore 密码。
- [ ] 先用脚本检查可取得的 V1.0.1 和 V1.0.2 APK/设备包，记录证书摘要，判断事故是否为签名身份不一致；不先假定根因。
- [ ] 验证正式 keystore、alias 和访问方式确实存在且可用于签名；不生成临时 keystore。
- [ ] 若没有原始签名私钥或无法证明 V1.0.1 签名身份，停止后续任务并记录 `RELEASE BLOCKED: ORIGINAL SIGNING PRIVATE KEY NOT AVAILABLE`。
- [ ] 将非敏感签名证据模板和复核结果写入 `docs/release/v1.0.3-signing-evidence.md`，私钥、密码、完整 `key.properties` 不写入文件。

**Verification:** 同一正式证书 SHA-256 出现在 V1.0.1 基线和待构建 V1.0.3 的验证记录中；缺证据时脚本非零退出且发布状态 BLOCKED。

**Commit:** `docs: record v1.0.3 signing evidence gate`

## Task 3: 先写构建守卫失败测试

**Files:** `tools/build-android-release.ps1`、`tools/build-android-release.tests.ps1`。

- [ ] 定义构建入口参数：`-FlutterProjectPath`、`-OutputPath`、`-SigningPropertiesPath`、`-Environment`、`-ApiBaseUrl`、`-VersionName`、`-VersionCode`、`-CronetHttpNoPlay`、`-ValidateOnly`。
- [ ] 先实现测试运行器，使用临时测试目录和假的 Flutter 可执行文件，验证守卫在以下输入下非零退出：`Environment=development`、API URL 非生产地址、API URL 非 HTTPS、Cronet 开关为 false、版本不是 `1.0.3/6`、签名配置不存在。
- [ ] 增加一条完整 production 参数的成功用例，验证脚本打印固定参数并进入构建调用；测试不读取或打印真实 secret。
- [ ] 运行 `pwsh -NoProfile -File tools/build-android-release.tests.ps1`，在脚本尚未实现守卫时确认至少一个断言失败；保存失败输出作为 TDD 证据。

**Verification:** 失败测试确实能区分每一种错误参数，且在缺少构建脚本时不会被静默跳过。

**Commit:** `test: define v1.0.3 android build guard failures`

## Task 4: 实现生产 Android 构建守卫

**Files:** `tools/build-android-release.ps1`、`tools/build-android-release.tests.ps1`、`README.md` 或现有 Android 发布文档。

- [ ] 实现参数校验：环境必须为 `production`，API 必须精确为 `https://api.suixiangji.icu`，Cronet 开关必须开启，版本必须精确为 `1.0.3` 和 `6`，签名配置必须存在且不为空。
- [ ] 由脚本统一调用 `flutter build apk --release`，显式传入三个 Dart defines，并把输出固定复制为 `outputs/wealthmate_flutter/build/app/outputs/flutter-apk/app-release.apk`。
- [ ] 构建前检查 `android/app/build.gradle.kts` 的 release signing 不是 debug signing；构建后使用 `apkanalyzer`/`apksigner` 检查 applicationId、版本和证书摘要。
- [ ] 对错误输入返回非零退出码；成功时输出 APK SHA-256、文件大小和验证结果；所有密码参数只作为进程环境输入，不打印值。
- [ ] 运行 Task 3 的失败/成功测试，确认失败用例全部拒绝、production 用例通过。
- [ ] 更新文档中的唯一推荐发布构建命令，禁止再出现省略 production defines 的可复制命令。

**Verification:** `pwsh -NoProfile -File tools/build-android-release.tests.ps1` 全部通过；错误参数均无法产生可发布 APK。

**Commit:** `fix: guard android release builds against demo configuration`

## Task 5: 更新 Flutter 与 Backend 版本元数据并补测试

**Files:** `outputs/wealthmate_flutter/pubspec.yaml`、`outputs/wealthmate_flutter/lib/core/config/app_config.dart`、相关 Flutter 配置测试、`outputs/wealthmate_backend/app/core/config.py`、相关 Backend 测试。

- [ ] 先添加版本断言测试，断言 Flutter 运行时为 `1.0.3 / 6`、minimum 为 `1.0.0 / 3`，Backend 默认 latest 为 `1.0.3 / 6`、minimum 为 `1.0.0 / 3`、force 为 false；先运行并确认旧版本导致失败。
- [ ] 将 Flutter `pubspec.yaml` 改为 `version: 1.0.3+6`，运行时常量改为 `kProductVersion='1.0.3'`、`kProductBuild=6`。
- [ ] 将 Backend 默认值更新为 `1.0.3 / 6`，不增加数据库迁移、不修改 API 路由、不改变 minimum supported 或强制更新策略。
- [ ] 运行新增测试和既有更新检查测试，确认客户端版本比较、下载 URL 和 `/app/version` schema 不回归。

**Verification:** Flutter/Backend 版本断言全部通过；代码搜索确认没有把 `/app-version` 写成 API 路由，也没有把 minimum 提升到 `1.0.2` 或更高。

**Commit:** `chore: bump app version to v1.0.3 build 6`

## Task 6: 接入正式 Android 签名并验证覆盖安装前置条件

**Files:** `outputs/wealthmate_flutter/android/app/build.gradle.kts`、`outputs/wealthmate_flutter/android/gradle.properties`（如现有项目需要）、`.gitignore`、`docs/release/v1.0.3-signing-evidence.md`。

- [ ] 增加从外部 `key.properties` 或环境变量读取正式签名参数的配置，并让 release variant 显式使用该 signing config；缺失任一必需字段时 Gradle 失败。
- [ ] 保持 `applicationId = "com.example.wealthmate_flutter"` 不变；不添加 debug fallback，不改包名绕开覆盖安装。
- [ ] 将 `key.properties`、keystore、签名导出文件加入忽略规则，复核 Git 不跟踪任何秘密文件。
- [ ] 在本地用正式签名配置执行一次最小 release signing 校验，记录 V1.0.1 证书摘要与新构建应匹配的证书摘要。
- [ ] 运行 Gradle 配置检查和签名检查脚本；正式私钥不可用时保持 BLOCKED，不执行后续构建/发布。

**Verification:** release variant 的实际证书 SHA-256 与 V1.0.1 基线一致；`git status --ignored` 显示秘密文件被忽略且 `git ls-files` 不包含它们。

**Commit:** `fix: use original signing identity for android release`

## Task 7: 构建并检查 V1.0.3 APK

**Files:** `outputs/wealthmate_flutter/build/app/outputs/flutter-apk/app-release.apk`（构建产物不提交）、签名证据文档。

- [ ] 通过 `tools/build-android-release.ps1` 构建 V1.0.3，不手工执行缺少 production defines 的 Flutter 命令。
- [ ] 校验 APK SHA-256、文件大小、包名、versionName `1.0.3`、versionCode `6`、正式签名证书摘要和 Embedded Cronet native libraries。
- [ ] 通过 APK 解包/资源检查确认 API 配置为 `https://api.suixiangji.icu`，不能出现 Demo Mode 的默认构建配置。
- [ ] 保存本地产物路径、hash、大小、版本和证书证据；不把 APK 二进制加入 Git 提交。

**Verification:** 构建守卫、`apkanalyzer`、`apksigner` 和 hash 检查全部 PASS；任何签名或生产配置不匹配都停止发布。

**Commit:** `build: verify signed production v1.0.3 android artifact`

## Task 8: 真实设备覆盖安装、登录和双设备同步验收

**Files:** `docs/release/v1.0.3-device-acceptance.md`；设备不修改仓库文件。

- [ ] A 设备保持 V1.0.1 build 4、原包名、登录态和可识别本地数据；B 设备使用同一账号，先确认服务端存在可同步数据。
- [ ] 在 A 设备不卸载、不清除数据的情况下覆盖安装 V1.0.3 build 6，记录安装结果、包名、版本和系统签名冲突信息。
- [ ] 打开 App 检查不进入 Demo Mode，登录态/本地数据保留，新增/编辑/删除操作和关键按钮正常。
- [ ] 让 A/B 两设备分别产生同步变更并执行 pull/push，核对双方数据最终一致；记录账号、时间、数据标识，不记录密码和 token。
- [ ] 若两台真实设备无法同时取得或任一步无法执行，原样记录 `REAL TWO-DEVICE TEST: NOT RUN`，发布状态为 BLOCKED。

**Verification:** 覆盖安装 PASS、登录 PASS、数据保留 PASS、按钮 PASS、A/B 同步 PASS；全部证据归档后才允许 Task 9。

**Commit:** `test: record v1.0.3 real-device acceptance`

## Task 9: 执行完整自动化回归

**Files:** 测试结果记录 `docs/release/v1.0.3-test-evidence.md`；使用现有项目测试目录，不修改业务逻辑。

- [ ] 运行 Flutter `flutter analyze` 和完整 `flutter test`。
- [ ] 运行 Backend 完整 pytest，若环境缺少 `python-jose`，先确认项目已声明依赖；仅在已有声明且本机未安装时安装，不改依赖版本。
- [ ] 运行 Web 既有 npm test。
- [ ] 运行 Android 构建守卫测试和签名检查。
- [ ] 将每个命令的退出码、通过数量、阻塞原因和环境信息写入证据；symlink 限制使用指定 BLOCKED 原文。

**Verification:** 所有可运行测试 PASS；任何 BLOCKED 或失败都禁止进入生产发布。

**Commit:** `test: record v1.0.3 regression evidence`

## Task 10: 推送 hotfix、合并 main 前的远端安全复核

**Files:** Git refs；不修改生产文件。

- [ ] 检查 hotfix 工作树干净，确认最终提交包含设计、计划、守卫、版本、签名和测试证据，且没有 keystore/APK/secret。
- [ ] 先推送 `hotfix/v1.0.3-android-release`，不 force push。
- [ ] `git fetch origin` 后复核 `origin/main` 未出现未知变化；若变化，重新比较 `origin/main...hotfix/v1.0.3-android-release`，不直接合并。
- [ ] 在所有本地和真实设备验收通过后，将 hotfix 合并到 main 并推送 main；保留 `v1.0.2` Tag 对象 SHA 不变。

**Verification:** GitHub 上 hotfix 与本地最终 SHA 一致，main 合并提交的父历史来自当前安全 main，`v1.0.2` Tag/Release 未变化。

**Commit:** `merge: integrate v1.0.3 android hotfix`

## Task 11: 创建生产回滚点并部署后端代码

**Files:** 服务器 `/opt/suixiangji/app`、`/opt/suixiangji/release-backups/v1.0.3-20260916/`；不修改数据库。

- [ ] 在服务器记录发布前代码 SHA、Docker Compose 配置 hash、Nginx 配置 hash、API `.env` 备份和当前运行容器状态。
- [ ] 通过 bundle/SSH 或已验证的 Git transport 部署已合并 V1.0.3 代码，确认 checkout SHA 与 GitHub main 一致。
- [ ] 只重建/重启 API 服务；不运行数据库迁移，不重建或重启 PostgreSQL。
- [ ] 先执行 `/health`、数据库 health、认证 401 保护、同步接口 401 保护和错误日志检查。

**Verification:** 后端运行提交 SHA 正确，health、DB、认证、同步和日志检查 PASS；数据库状态与部署前一致。

**Commit:** 无额外仓库提交；服务器回滚点和部署证据保存到发布记录。

## Task 12: 上传 APK 并在最后切换更新元数据

**Files:** 服务器 `/var/www/suixiangji-download/app/suixiangji-v1.0.3-build6.apk`；生产 `.env` 的更新字段。

- [ ] 上传已验签的 APK 到新的 V1.0.3 文件名，禁止覆盖 V1.0.2 文件。
- [ ] 对本地文件、服务器文件和公网完整下载文件分别计算 SHA-256，三者必须一致；确认下载 HTTP 200。
- [ ] 在后端和 APK 均验证通过后，将生产 latest 切换为 `1.0.3 / 6`，minimum 仍为 `1.0.0 / 3`，force 仍为 false，下载 URL 指向新文件。
- [ ] 重启 API 服务并从公网验证 `/app/version`、下载、health、DB、认证、同步和日志。

**Verification:** 只有切换后的公网 `/app/version` 和 APK 完整下载都 PASS，才可创建 Tag/Release。

**Commit:** 无额外仓库提交；发布元数据通过受控生产配置更新。

## Task 13: 创建 V1.0.3 Tag/Release 并完成发布后检查

**Files:** Git ref `v1.0.3`、GitHub Release；不接触 `v1.0.2`。

- [ ] 在已推送且验收通过的 main 最终 SHA 上创建并推送不可变 `v1.0.3` Tag；不使用 force。
- [ ] 创建 GitHub Release，上传同一份已验签 APK 或引用已验证下载资产，Release 说明包含版本、build、生产配置、签名证书摘要和测试结论，不包含 secret。
- [ ] 重新 fetch 并核对 `origin/main`、`origin/hotfix/v1.0.3-android-release`、`v1.0.3` 和既有 `v1.0.2` Tag。
- [ ] 执行发布后健康检查，保存公网 version、下载、health、DB、认证、同步、日志和真实设备更新证据。

**Verification:** V1.0.3 的所有发布条件 PASS；V1.0.2 Tag/Release 仍是原始对象；最终报告明确列出所有证据和任何未执行项。

**Commit:** 无后续代码提交；最终发布由 Tag/Release 指向已验收 main SHA。

## 回滚步骤

若 Task 11–13 任一生产检查失败：

- [ ] 立即把 `/app/version` 恢复为 V1.0.1 build 4 并验证公网响应。
- [ ] 必要时恢复 Task 11 创建的 API 代码和环境备份，只恢复已验证文件。
- [ ] 保留 V1.0.3 APK 作为未曝光的诊断资产，除非需要按安全流程清理；不覆盖 V1.0.2 APK。
- [ ] 不修改数据库、不执行迁移、不回滚 PostgreSQL。
- [ ] 在报告中写明失败阶段、回滚点、恢复后的 health/version 证据。



