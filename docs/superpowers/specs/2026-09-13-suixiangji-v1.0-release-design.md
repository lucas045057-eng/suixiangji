# 随想记 V1.0.0 发布收口设计

## 发布硬约束

- 产品版本为 `1.0.0`。
- Flutter 版本为 `1.0.0+3`，Android `versionName=1.0.0`、`versionCode=3`。
- Android build number 是唯一发布顺序依据，必须单调递增；不得复用或降低 versionCode。
- 更新判断只比较 `latest_build > local_build`。`versionName` 用于展示和发布标识，不参与升级顺序判断。
- 现有 Beta `1.2.0+2` 到正式 `1.0.0+3` 必须被判定为可更新。
- 不修改数据库、历史 migration、Beta 用户数据或 Sync 协议。
- 正式域名不猜测；当前状态为 `PRODUCTION DOMAIN: NOT CONFIGURED`。
- APK 直接覆盖安装必须以 applicationId、签名证书指纹和更高 versionCode 三项证据为准；无法证明时标记 `APK UPDATE SIGNING: NOT VERIFIED`，不得声称可直接更新。
- 历史 Tag `modular-monolith-v1`、`sync-v1.0-rc1` 本阶段不删除。

## 当前证据

- `origin/main` 与 `origin/refactor/modular-monolith` 均指向 `02f2bd0`。
- 当前源码此前使用 Flutter `1.2.0+2`，Android Gradle 通过 Flutter 继承 versionName/versionCode，applicationId 为 `com.example.wealthmate_flutter`。
- API 基址由 `WEALTHMATE_API_BASE_URL` 注入，但此前在 `main.dart` 直接读取，构建示例和交付文档中存在局域网地址。
- Backend 已有环境配置、CORS 和 `/health`，没有版本更新接口；迁移 head 为 `0002_beta_users`。
- 仓库及 `E:\codex` 下没有发现 Beta APK、AAB、keystore 或 `key.properties`；当前 Android release 配置使用 debug signing，Beta 证书指纹因此尚未得到可比对证据。

## 方案

### 1. 集中环境配置

新增 Flutter `AppConfig`，集中读取 `WEALTHMATE_API_BASE_URL` 与 `WEALTHMATE_ENVIRONMENT`。开发/测试可使用 localhost 或 HTTP；生产 API 基址必须是 HTTPS。正式域名只通过该入口注入，不在 Dart 文件中散落硬编码。

后端继续使用 `WEALTHMATE_CORS_ORIGINS`，Beta/生产保持显式 origin 校验。当前仓库没有 Nginx 配置，因此 DNS、HTTPS 证书、反向代理和生产 Host 配置仍属于外部部署验收项，不用示例域名冒充正式配置。

### 2. 静态版本接口

新增公开的 `GET /app/version`。接口只读取服务端环境配置，不访问数据库：

```json
{
  "latest_version": "1.0.0",
  "latest_build": 3,
  "minimum_supported_version": "1.0.0",
  "minimum_supported_build": 3,
  "force_update": false,
  "download_url": null,
  "release_notes": ""
}
```

`minimum_supported_build` 用于避免历史 versionName 倒退造成错误判断。生产强制更新只有在配置有效 HTTPS 下载地址时才允许生效；接口异常、字段异常或下载地址不可信时，客户端继续进入 App。

### 3. Flutter 更新流程

客户端通过 `package_info_plus` 读取当前 `version` 与 `buildNumber`。App 启动后异步调用版本接口，不阻塞本地数据加载、登录或离线使用。更新模型只按 build number 判断：

```text
updateAvailable = remote.latest_build > local.build
forceRequired = updateAvailable &&
                (remote.force_update || local.build < remote.minimum_supported_build)
```

普通更新提供“稍后”和“立即更新”；强制更新不提供稍后，但只有有效 HTTPS 下载地址才能阻止继续使用。点击更新使用 `url_launcher` 打开外部 HTTPS 地址，不做静默安装，不增加 Android 安装权限。

设置页增加当前版本和“检查更新”。失败、已是最新版和更新可用都用可理解的界面反馈；失败不改变本地状态和 Sync 队列。

### 4. Beta 用户系统语义审计

在 Git 清理前，对 `feat/v1-user-system` 的三个不在 main 的 commit 逐项对照当前模块化实现与测试，覆盖注册、邀请码、登录、JWT rotation、注销、用户隔离、0002 migration、离线/relogin 和 Sync session protection。若功能已被模块化版本语义覆盖，仅在 cleanup report 记录依据；若有缺失，只移植缺失行为，不合并整条旧分支。

### 5. 发布与清理顺序

在 `feat/v1-release` 上完成实现和全量验证后合并 `main`、推送 `origin/main`、创建 annotated `v1.0.0` 并确认两者指向同一 commit。随后创建仓库外完整 bundle 并通过 `git bundle verify`，生成 Git cleanup report，最后才删除确认安全的开发分支。历史 Tag 保留。

## 影响边界

- 数据库：无 schema 变化，继续使用 `0002_beta_users`，不执行 drop/rebuild。
- Beta 用户：不改用户、邀请、认证或本地分区数据。
- Sync：不改 `LocalStateSession`、`SyncCoordinator`、push/pull、cursor、tombstone、`client_op_id` 或 `serverVersion`。
- Web/PWA：当前是独立离线演示，不接入版本接口；域名改动不改变其现有行为。

## 验收重点

- `1.2.0+2` 本地与 `1.0.0+3` 远端判定为更新可用。
- 本地 build 等于或高于远端 build 时不得提示升级。
- 版本接口失败仍能进入 App。
- 普通/强制更新按钮和 HTTPS 下载地址行为正确。
- 设置页展示 `1.0.0 (3)` 并能手动检查。
- 现有 Backend、Flutter、Web、migration、架构边界和 Sync 回归保持通过。
- APK 签名连续性有证据才允许声称可覆盖安装；否则报告 `NOT VERIFIED`。
