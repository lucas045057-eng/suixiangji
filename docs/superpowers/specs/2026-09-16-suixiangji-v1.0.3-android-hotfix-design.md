# 随想记 V1.0.3 Android 发布事故热修复设计

状态：已批准，实施前设计基线

日期：2026-09-16

## 1. 目标

发布 V1.0.3 build 6，解决 V1.0.2 的两个 Android 发布事故：

1. V1.0.2 build 5 在 V1.0.1 设备上无法覆盖安装，必须证明 V1.0.3 使用与 V1.0.1 相同的正式签名身份。
2. V1.0.2 APK 构建时缺少生产环境 Dart defines，启动后进入 Demo Mode；V1.0.3 必须在构建流程中强制校验生产 API 配置。

最终发布条件是：正式签名证据、生产配置证据、真实设备覆盖安装证据、登录及数据保留证据全部齐全。任一条件缺失，均不得继续上传 APK、切换生产更新元数据、创建 V1.0.3 Tag 或 GitHub Release。

## 2. 已知基线与不可变对象

- 代码基线：`main @ c283a001bf57ac8b1b5cd33e5476e4577edf8e7d`。
- V1.0.2 Tag/Release：已经正式发布，保留原状，不移动、不重写、不删除。
- 生产目录：`/opt/suixiangji/app`。
- 生产服务器：`root@47.98.183.77`。
- 生产当前代码继续保持 V1.0.2 版本对应提交；数据库 schema、数据和数据库容器不在本次热修复范围内。
- 当前生产更新接口的真实路由是 `/app/version`；不得把不存在的 `/app-version` 当作发布接口。
- V1.0.1 的最低支持版本保持 `1.0.0 / 3`。
- 保留 V1.0.1 引入的 Embedded Cronet 方案，并在正式构建中继续使用 `cronetHttpNoPlay=true`。

## 3. 发布前立即动作：暂停错误 APK 更新曝光

在任何 V1.0.3 代码、构建或上传动作之前，只调整生产更新元数据，将公开更新目标临时恢复为 V1.0.1 build 4：

```text
latest_version: 1.0.1
latest_build: 4
minimum_supported_version: 1.0.0
minimum_supported_build: 3
force_update: false
download_url: https://download.suixiangji.icu/app/suixiangji-v1.0.1-build4.apk
```

此动作只重启承载更新元数据的 API 服务，不重建、不重启 PostgreSQL，不修改任何数据库对象；已上传的 V1.0.2 APK 文件保留为历史发布资产，不删除、不覆盖。暂停完成后必须从公网验证 `/app/version`，并验证 `/health` 和 PostgreSQL 健康状态。

## 4. 分支与提交策略

从当前 `main @ c283a001...` 创建独立分支：

```text
hotfix/v1.0.3-android-release
```

本地提交按可迁移的逻辑拆分：设计与计划、可失败的构建守卫测试、构建守卫实现、版本元数据、正式签名配置、测试与文档。GitHub 连接恢复后先推送 hotfix 分支；在真实设备与生产验收全部通过前，不合并 `main`，不创建 Tag/Release，不 force push。

## 5. 签名设计与硬门槛

### 5.1 证据来源

优先从下列来源取得 V1.0.1 的真实 APK 或设备上已安装包，并使用 Android SDK 的 `apksigner` 读取证书摘要：

- V1.0.1 原始发布 APK；
- 一台已经安装 V1.0.1 且保留用户数据的真实 Android 设备；
- 项目外部受控的正式签名 keystore 及其访问凭据。

只接受能复核的证据：APK 的 SHA-256、包名、versionName/versionCode、签名证书 SHA-256、keystore alias 及签名配置来源。私钥、密码、token 不进入 Git、日志或最终报告。

### 5.2 失败规则

若无法取得原始签名私钥或无法证明新 APK 与 V1.0.1 的证书身份相同，立即停止发布并报告：

```text
RELEASE BLOCKED: ORIGINAL SIGNING PRIVATE KEY NOT AVAILABLE
```

不得用 debug 签名、临时生成 keystore、改 applicationId、卸载旧 App 或清除数据来绕过覆盖安装验证。

### 5.3 Gradle 接入

正式签名配置只从本机或 CI 的受控 `key.properties`/环境变量读取，配置文件加入忽略规则；仓库只保留无秘密的示例和操作说明。`release` variant 必须使用正式签名配置，缺少配置时构建直接失败；不允许回退到 `signingConfigs.debug`。

## 6. 构建守卫设计

新增 Windows 开发机和 CI 共用的构建入口：

```text
tools/build-android-release.ps1
```

入口必须在调用 Flutter 前校验并明确打印以下固定值：

```text
WEALTHMATE_ENVIRONMENT=production
WEALTHMATE_API_BASE_URL=https://api.suixiangji.icu
cronetHttpNoPlay=true
versionName=1.0.3
versionCode=6
```

校验失败时返回非零退出码，不产生可发布 APK。构建成功后必须自动检查 APK 的包名、versionName、versionCode、生产 API 配置痕迹、Embedded Cronet 依赖和正式签名证书摘要；输出 APK 的 SHA-256 与大小。脚本不得打印签名密码或任何 secret。

构建守卫测试采用先失败后实现的顺序，至少覆盖：缺少 production environment、API host 不是 `https://api.suixiangji.icu`、缺少 Cronet define、版本不是 `1.0.3+6`、release 签名配置缺失，以及完整参数通过。

## 7. 版本与运行时设计

Flutter：

```text
outputs/wealthmate_flutter/pubspec.yaml                 version: 1.0.3+6
outputs/wealthmate_flutter/lib/core/config/app_config.dart
  kProductVersion = '1.0.3'
  kProductBuild = 6
```

Backend 默认值与 Flutter 客户端保持一致：

```text
latest_version = 1.0.3
latest_build = 6
minimum_supported_version = 1.0.0
minimum_supported_build = 3
force_update = false
```

生产服务器最终切换时，将 `APP_GIT_SHA` 写为包含全部 V1.0.3 修改的最终提交 SHA；数据库迁移命令不执行，数据库镜像不重建。

## 8. 测试与验收门槛

### 8.1 自动化测试

- 构建守卫单元/脚本测试先失败，后实现，再运行全部测试。
- Flutter：针对版本常量和更新解析运行相关测试，随后运行完整 `flutter test` 与 `flutter analyze`。
- Backend：运行完整 pytest；只接受现有依赖，不为本机缺少依赖擅自改版本。
- Web：运行既有 npm test。
- 若 Flutter 因 Windows Developer Mode / symlink 无法运行，记录原文：`BLOCKED: Windows Developer Mode / symlink requirement`，不得标记 PASS。

### 8.2 真实 Android 设备

必须使用两台 Android 设备或两套可复核的真实设备状态：

1. A 设备安装 V1.0.1 build 4，保留已有登录和一条可识别数据。
2. B 设备登录同一账号并创建/同步一条可识别数据，证明服务端已有数据。
3. 在 A 设备直接覆盖安装 V1.0.3 build 6，不卸载、不清除数据。
4. 覆盖安装后检查包名、版本、签名、登录态/本地数据保留、API 环境不是 Demo Mode。
5. 检查登录、记账/记录保存、编辑、删除、同步及关键按钮可用。
6. B 设备重新拉取并确认 A 设备改动可见，反向同步也可见。

若两设备无法同时取得，必须记录：

```text
REAL TWO-DEVICE TEST: NOT RUN
```

并将发布结论标记为 BLOCKED。

### 8.3 生产验收

发布后依次验证：`/health` HTTP 200、数据库健康、认证接口保护、同步接口保护、服务日志无新的 ERROR/Traceback/Exception/FATAL/database/JWT 异常、APK 下载 HTTP 200 且 SHA-256 与服务器文件一致、`/app/version` 返回 `1.0.3 / 6` 且下载地址可用。

## 9. 正式发布顺序

只有所有硬门槛 PASS 后才执行：

1. 推送 `hotfix/v1.0.3-android-release`。
2. 基于当前安全 `main` 合并并推送 V1.0.3。
3. 在服务器创建带时间戳的代码和配置回滚点。
4. 通过可复核的 bundle/SSH 方式部署代码，避免依赖当前服务器 GitHub fetch 异常。
5. 先上传 APK 到新的 V1.0.3 文件名并校验 hash。
6. 重启 API 服务并进行健康/认证/同步检查。
7. 最后将 `/app/version` 的 latest 切换为 `1.0.3 / 6`。
8. 验证客户端更新接口和完整下载。
9. 创建不可变的 `v1.0.3` Tag 与 GitHub Release，保留 `v1.0.2` 原状。
10. 执行发布后健康检查并保存证据。

任一阶段失败，停止后续发布动作，按回滚点恢复代码/配置和更新元数据；不得修改数据库 schema 或数据。

## 10. 回滚设计

回滚只使用发布前记录的代码提交、API 环境文件和 APK 更新元数据备份。优先将 `/app/version` 恢复到 V1.0.1 build 4；必要时恢复 API 代码到 V1.0.2 发布前的已验证提交。PostgreSQL 不回滚、不重建、不执行迁移。V1.0.2 Tag/Release 始终保持原始对象不变。



