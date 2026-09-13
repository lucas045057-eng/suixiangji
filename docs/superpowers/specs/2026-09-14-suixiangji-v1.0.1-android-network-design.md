# 随想记 V1.0.1 Android 网络兼容修复设计

## 文档状态

- 设计版本：`v1.0.1-android-network-design`
- 状态：已根据用户设计批准形成，等待二次确认后才可实施
- 本文档不是实现计划，不授权创建实现分支、修改源码、修改版本号或修改 V1.0.0
- V1.0.0 冻结基线：`v1.0.0` / `72f05120a3f8ab0b3f68fbd8ee2c0b856d9af406`

## 1. 目标与问题边界

V1.0.1 只修复 Android 真机上的 HTTPS 网络兼容问题。已知诊断矩阵显示：同一 vivo V2426A Android 16 设备上，Dart IO/系统 HttpsURLConnection 访问正式 API 失败，而 Cronet 访问正式 API 成功。准确表述为：

> Android 网络兼容问题由 Cronet transport 缓解；不能将问题表述为已经证明是 Dart 本身的缺陷。

本次目标版本：

```text
产品版本：1.0.1
Flutter Version：1.0.1+4
Android versionName：1.0.1
Android versionCode：4
Git Tag：v1.0.1（所有验收通过后才能创建）
```

版本顺序继续只按 build number / Android versionCode 判断：

```text
1.0.0+3 → 1.0.1+4
```

## 2. 非目标与禁止事项

本次不修改：

- V1.0.0 的源码、Tag、发布 APK 或签名证书
- Backend、API schema、PostgreSQL、volume、历史 migration
- Auth、JWT rotation、用户注销、用户隔离和 local partition
- Sync push/pull、cursor、serverVersion、client_op_id、tombstone、conflict 处理
- `ApiTransport` 的业务语义、状态码映射和鉴权重试规则
- 正式 API 域名：仍使用 `https://api.suixiangji.icu`

禁止：

- 为绕过兼容问题让用户卸载 V1.0.0
- `docker compose down -v`、删除数据库 volume 或重建数据库
- 修改 `0001` / `0002_beta_users` migration
- force push
- 使用不同签名证书构建 V1.0.1
- 在某些 Android 路径使用 Google Play Services Cronet、在另一些路径使用 Embedded Cronet

## 3. 当前架构审计结论

当前生产请求链路已经集中在一个 HTTP 入口：

```text
main.dart
  ↓
ApiClient
  ↓
ApiTransport
  ↓
一个 package:http Client
  ↓
全部 RemoteDataSource
```

`ApiClient` 是兼容 façade，当前生产入口只有一处创建；`ApiTransport` 统一负责 URL、headers、Authorization、JSON、非 2xx 映射和认证过期处理。Auth、业务数据、Backup、Sync 及 `/app/version` 均经由该链路。

审计还确认：

- Feature 层没有直接创建 HTTP client。
- 生产代码没有独立 Dio 请求链路。
- 生产代码没有直接使用 `dart:io HttpClient`。
- 现有测试依赖 `ApiClient(client: fakeClient)` 注入，因此该注入能力必须保留。
- 当前 `ApiClient` 没有明确的 close 入口，需要在本次最小改动中补上生命周期收口。

## 4. 方案选择

### 4.1 采用方案 A：集中 HTTP client factory

只在 `ApiClient` 的默认 client 创建处接入平台 factory：

```text
Android      → Embedded CronetClient
非 Android   → 现有 package:http Client
```

RemoteDataSource、ApiTransport、认证和同步代码不需要逐个改写，因此不会形成“只修登录、漏修同步或版本检查”的半修复。

不采用在 `main.dart` 分别创建 Cronet client 的方案，也不采用重写 ApiTransport 抽象的方案；前者扩大组合层职责，后者会扩大测试和架构变更面。

## 5. 平台隔离与 Web 兼容设计

### 5.1 条件导入边界

新增一个公共 factory façade，并通过条件导入隔离平台实现：

```text
http_client_factory.dart
  ├─ dart.library.io       → native factory
  ├─ dart.library.js_interop → Web factory
  └─ fallback              → package:http factory
```

Android-only 的 `package:cronet_http/cronet_http.dart` 只能出现在 native Android-capable 实现文件中，Web 实现文件不得导入该包。Web 构建和 Web 测试继续使用现有 `package:http` transport，不执行 Cronet 分支。

native factory 内部再按运行平台选择：

```text
TargetPlatform.android → CronetClient
其他 native 平台       → http.Client
```

实现阶段必须验证至少：

- Web analyze/test/build 不因 Cronet import 失败。
- Windows 或当前仓库支持的非 Android 构建继续通过。
- Android 才能实际创建 CronetEngine。

### 5.2 测试注入

factory 必须具备可测试的选择边界。主机单元测试不启动真实 Cronet，而是通过 fake builder 或 transport kind 断言：

```text
Android 选择 Cronet
非 Android 选择现有 http
```

现有 `ApiClient(client: fakeClient)` 构造方式继续有效。

## 6. Embedded Cronet 设计

依赖锁定为：

```yaml
cronet_http: 1.9.0
```

Android 使用：

```text
CronetEngine.build(
  cache disabled,
  HTTP/2 enabled,
  QUIC disabled,
)
CronetClient.fromCronetEngine(engine, closeEngine: true)
```

目标发行方式：

```text
Cronet distribution：Embedded
Google Play Services required：NO
```

不使用 `defaultCronetEngine()` 之类可能选择 Google Play Services 的默认路径。`cronetHttpNoPlay=true` 是 Embedded 选择的构建契约，不是可选调试参数。

## 7. Flutter Binding 初始化顺序

任何可能创建 CronetEngine 的路径，都必须先完成 Flutter Binding 初始化。应用入口固定遵循：

```dart
WidgetsFlutterBinding.ensureInitialized();
// 然后才允许构造 ApiClient / CronetEngine
```

该调用必须早于数据库初始化之后的 `ApiClient` 创建，也早于任何 Flutter plugin 或 JNI/Cronet 初始化。factory 可在 Android 创建 Engine 前再次调用幂等的 `WidgetsFlutterBinding.ensureInitialized()` 作为防御性保障，但不能依赖“调用顺序碰巧正确”。

## 8. 生命周期与所有权

遵循“谁创建谁关闭”：

```text
ApiClient 内部创建的生产 Client → ApiClient.close() 关闭
CronetClient.fromCronetEngine(..., closeEngine: true)
  → Client close 时一并关闭所属 Engine
外部注入 fake/test Client     → ApiClient 不关闭
```

具体约束：

- `ApiClient` 只创建一个生产 Client。
- `ApiClient.close()` 必须幂等。
- 由 factory 创建的 client 标记为 owned。
- 通过 `client:` 注入的 client 标记为 external，不由 `ApiClient` 擅自 close。
- 所有 RemoteDataSource 共享同一个 ApiClient/ApiTransport/client，不创建第二个 Engine 或 client。
- App 生命周期结束时由应用组合根调用 `ApiClient.close()`。

## 9. ApiClient 与请求语义

`ApiClient` 的最小修改仅包括：

1. 默认 client 从 platform factory 获取。
2. 保留现有 `client:` 注入参数。
3. 记录 client ownership。
4. 增加幂等 `close()`。

以下行为必须原样保留：

- `content-type: application/json`
- Authorization header
- access token / refresh token 流程
- 401 后 refresh、session generation 检查和 retry
- 400、401、403、404、409、422、429、500 等错误映射
- 网络错误、超时和 JSON 解码错误映射
- `/auth/login`、`/auth/register`、`/auth/me`、注销、密码接口
- `/sync/push`、`/sync/pull`
- `/app/version`

## 10. Android 路径统一构建契约

所有相关 Android 执行路径必须显式使用同一个 dart-define：

```text
--dart-define=cronetHttpNoPlay=true
```

适用范围：

```text
flutter run                         必须使用
Android integration/test 路径       必须使用
CI 中的 Android Flutter 命令         必须使用
flutter build apk --release          必须使用
```

实现阶段应将这些命令集中到统一的 Android 运行/构建约定或 CI 命令模板，并增加检查，防止出现测试使用 Play Services、正式包使用 Embedded 的配置漂移。任何未带该 define 的 Android Release 构建都不具备 V1.0.1 发布资格。

主机上的纯 Dart/Flutter 单元测试可以使用 fake client，不需要启动真实 Cronet；但只要测试或集成测试执行 Android plugin/runtime，就必须带上述 define。

## 11. 测试优先验收设计

实施前先添加失败测试，再写实现。最低测试集合：

### Factory 与平台隔离

- Android 选择 Cronet。
- 非 Android 选择现有 `package:http` client。
- Web 文件不导入 `cronet_http`，Web analyze/test/build 通过。
- Android factory 不在每个请求中重复创建 Engine。
- Binding 初始化发生在 CronetEngine 创建之前。

### 生命周期

- ApiClient 内部创建的 client 由 `ApiClient.close()` 关闭。
- `CronetClient` 使用 `closeEngine: true`。
- 外部 fake/test client 不被 ApiClient 关闭。
- `close()` 重复调用不会产生异常。

### Auth、错误和请求语义

- login、register、refresh、logout。
- 401、404、409、422、500。
- 网络错误和 timeout。
- Authorization、Content-Type、JSON body 和响应解码保持不变。

### Sync 与版本检查

- push / pull。
- offline / reconnect。
- session protection 和 stale response 防护。
- `/app/version` 继续按 build number 判断。
- `1.2.0+2` → `1.0.1+4` 以及 `1.0.0+3` → `1.0.1+4` 均按 build 顺序正确处理。

### 回归门槛

```text
flutter analyze
flutter test
Web analyze/test/build
非 Android 构建
Android build
Android integration/device tests
Backend tests
Root/architecture tests
```

## 12. 版本、签名和发布边界

实现完成后才允许把版本改为：

```text
1.0.1+4
versionName=1.0.1
versionCode=4
```

正式 APK 必须使用：

```text
WEALTHMATE_API_BASE_URL=https://api.suixiangji.icu
```

APK 必须保持：

```text
applicationId=com.example.wealthmate_flutter
签名 SHA-256=cadeb8ca7786b755305e07a086b407d8da7d6751d54566d9a0787d457df32458
```

如果签名指纹不同，停止发布并报告 `APK UPDATE SIGNING: NOT VERIFIED`，不得要求用户卸载 V1.0.0。

所有自动化测试、Android 构建、真机 Wi-Fi/移动网络验证和数据保留验证通过后，才允许创建 `v1.0.1` Tag。

## 13. 风险与待验证项

- `cronet_http: 1.9.0` 已在独立探针中验证 Embedded Cronet 可访问正式 API；正式 App 的 Gradle、Web 条件导入和真机回归仍需在实现阶段验证。
- 该插件在独立构建中出现过 Kotlin Gradle Plugin 兼容性 warning；只有实际构建失败时才处理，不能借机升级无关依赖或改动 V1.0.0。
- Embedded Cronet 的最终 APK packaging、无 GMS 设备行为和签名连续性必须以正式候选 APK 的实测证据为准。
- Android 相关构建命令缺少 `cronetHttpNoPlay=true` 时，标记为配置不合格，不得发布。

## 14. 规格自审

| 自审项 | 结果 | 说明 |
|---|---|---|
| Web 兼容 | PASS（设计约束） | Cronet import 限制在 native 条件实现；实现后需实际 Web build |
| Binding 初始化 | PASS（设计约束） | 入口先 ensureInitialized，factory 创建 Engine 前再防御性确认 |
| 所有权 | PASS（设计约束） | owned client 由 ApiClient.close；外部 fake 不关闭；Engine 使用 closeEngine=true |
| Embedded 一致性 | PASS（设计约束） | run/test/CI/release 统一 `cronetHttpNoPlay=true` |
| 单 Engine/Client | PASS（设计约束） | ApiClient 构造时创建一次，全部 RemoteDataSource 共享 |
| Auth/Sync 不变 | PASS（设计约束） | 只替换默认 HTTP client 创建层 |
| 版本单调递增 | PASS | `1.0.0+3 → 1.0.1+4` |
| V1.0.0 保护 | PASS | 本轮只新增设计文档，不创建实现分支、不改源码和版本 |
| 实际编译与真机验收 | NOT RUN | 必须在二次确认后进入实施阶段 |

## 15. 二次确认后的顺序

收到用户对本文档的二次确认后，才进入下一阶段：

1. 创建隔离实现分支 `fix/v1.0.1-android-network`。
2. 按本文档先编写失败测试。
3. 实现平台 factory、Cronet client 生命周期和 ApiClient 接入。
4. 运行完整自动化测试、构建和真机验收。
5. 只有全部通过后才处理 APK 上传、版本接口更新和 `v1.0.1` Tag。
