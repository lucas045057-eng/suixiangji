# 随想记 V1.0.4 同步与 App 内更新设计规格

**状态：** 已获用户批准，待规格复审

**目标分支：** `fix/v1.0.4-sync-and-inapp-update`

**基线：** `main` / `origin/main` `52efc6ee4649b278080de7b6458bb6b9571b616e`，Flutter `1.0.3+6`

## 1. 目标与非目标

V1.0.4 解决两个生产可见问题：

1. 同账号多设备的双向最终一致性，覆盖本地 mutation 自动上传、前台自动拉取、同步期间新增 mutation，以及 PostgreSQL 多 worker 下的版本分配并发安全。
2. Android 更新改为 App 内 HTTPS 下载 APK，再交给 Android 系统 Package Installer 安装；外部浏览器只保留为原生安装能力不可用时的最终 fallback。

本版本不重建同步架构、不修改历史 migration、不清空或全量覆盖本地数据库、不改变用户 ID、JWT 或数据隔离语义，不引入 WebSocket 或高频轮询，不部署生产或切换生产 `/app/version`。

## 2. 已确认的基线问题

- `LedgerStore`、`AssetStore`、`BudgetStore` 本地提交成功后只写本地 state 和 `SyncQueue`；只有 QuickEntry 通过 `postConfirm` 显式调用 `FinanceStore.sync()`。
- `FinanceStore.sync()` 在同一 session 已同步时直接返回，导致同步期间的第二次同步请求没有留下待处理标记。
- `AppShell` 当前只在初始化/登录后的启动路径同步，没有统一的 `resumed` 处理和前台 timer。
- `AppUpdateDialog` 使用 `url_launcher` 的 `LaunchMode.externalApplication` 打开 `download_url`。
- 后端 `sync.service.push()` 直接在 Python 对象上执行 `user.sync_version += 1`，没有对 User 行加数据库锁；两个独立 PostgreSQL session 可能读取相同旧值并写入相同版本。
- 现有 Flutter `MemorySyncServer` 在单线程内执行 `version++`，不能证明 PostgreSQL 并发安全。

## 3. 客户端同步设计

### 3.1 统一 mutation 通知

特性 store 不直接发 HTTP。每个本地 mutation 在 `LocalStateSession.write()` 成功完成、state 和 queue 已持久化后发出一次 `onLocalMutation(reason)`：

- Ledger：账目新增、修改、软删除、分类新增/修改/归档。
- Assets：账户新增/修改；仅改变本地默认账户选择的操作不伪造同步 mutation，因为它没有同步 operation。
- Budget：预算新增/修改。
- QuickEntry：确认后通过 Ledger mutation 回调进入同一机制。

`FinanceStore` 在构造时绑定这些回调，Widget 只调用既有 store API。

### 3.2 serialized sync drain loop

`FinanceStore` 增加统一 `requestSync(reason, {immediate})` 调度入口，并维护当前登录 session 作用域内的：

- `syncDirty`：收到同步请求即置为 `true`；不记录可丢失的单次 future。
- `_syncingSession`：表示当前唯一实际 sync pipeline，防止并发 push/pull。
- `_drainFuture`：当前 serialized drain 的共享 Future；active drain 收到的新请求必须复用它，不能返回一个表示“请求已登记”但实际同步仍未结束的假完成 Future。
- 可取消的 debounce timer：连续本地修改在安静窗口内合并为一次 pipeline。
- 当前和最近一次安全诊断 reason，仅用于 debug 日志，不进入业务数据。

实际 drain 语义：

```text
requestSync()
  -> dirty = true
  -> 若没有 pipeline，按 debounce/立即策略启动 drain

drain:
  while (dirty && session 仍然有效):
      dirty = false
      执行一轮完整 push + pull
      若本轮成功且期间又有 mutation，继续下一轮
      若本轮失败，立即结束本次 drain；保留 queue/cursor 语义，不在本 while 内 retry
  退出
```

新的 mutation 可以发生在 push、pull 或 state merge 的任意 await 边界；回调只设置 dirty，不启动第二个 pipeline。循环不使用“最多补一次”的上限，直到当前 session 没有新的同步请求。成功 drain 会排空这段时间内登记的 dirty rounds；一次完整 push/pull 因网络、HTTP、数据库或其他可恢复错误失败时，当前 drain 立即停止，不在 while loop 内反复 retry，也不产生 busy loop。可以保留 dirty/pending 状态，但下一次 retry 只能由 foreground timer、App resume、新 local mutation、登录/启动或用户手动同步重新唤醒。

`requestSync(reason, {immediate})` 和手动 `sync()` 都返回当前请求对应的 serialized drain Future。没有 active drain 时，调用会创建新的 drain Future（必要时先等待 debounce）；已有 active drain 时，调用只设置 dirty 并返回同一个 `_drainFuture`，该 Future 只有在当前 pipeline 及其期间登记的所有成功后续 rounds 真正结束时才完成。若本轮失败，Future 在本次 drain 停止、错误已持久化后完成；保留的 dirty/queue 由下一次外部唤醒重新创建/执行 drain。这样 `await store.sync()` 不会在 active pipeline 尚未结束时假完成，也不会因失败在内部无限重试。session 切换、退出登录和 dispose 会取消 debounce/retry，旧 session 的结果不得发布到新用户。

### 3.3 生命周期与前台同步

`AppShell` 实现 `WidgetsBindingObserver`：

- 登录成功、冷启动完成并确认本地 owner 后请求一次立即同步。
- `AppLifecycleState.resumed` 请求一次立即同步，并启动约 30 秒 foreground timer。
- `paused`、`inactive`、`detached` 停止 timer；后台不发起 timer 同步。
- timer 只有在 API 已配置、本地 owner 已绑定、App 仍在 foreground 且当前没有 active pipeline 时请求同步；实际并发保护仍由 FinanceStore 负责。
- 保留首页/设置页手动同步按钮。

### 3.4 cursor 与持久化不变式

继续由 `SyncCoordinator` 维护现有 push/pull 顺序和 merge 规则：

- push receipt 只完成对应本地 operation，不推进 download cursor。
- 只有 pull 成功并完成本地 merge 后才保存新的 `syncState.serverVersion`。
- push 成功但 pull 失败时，cursor 保持 pull 前值；下一轮从旧 cursor 拉取遗漏记录。
- queue 与 state 在同一个 `LocalStateSession` 串行写入；离线、响应丢失和重试保持幂等。

## 4. 后端 sync_version 并发设计

### 4.1 一次 push transaction 锁一次 User

`sync.service.push()` 保留单次 batch 的一个事务边界，并在处理 batch 前对当前用户执行一次：

```sql
SELECT ... FROM users WHERE id = :user_id FOR UPDATE
```

锁定后的 User 对象作为本次 push 的版本 allocator。随后按既有依赖排序处理 batch：

1. 基于当前数据库状态重新检查每个 `client_op_id` 的 `SyncOperation` receipt。
2. 对非幂等 operation 重新读取 entity 最新行并检查 `server_version` 冲突。
3. accepted operation 执行 `user.sync_version += 1` 并 flush，得到该 operation 独占的版本号。
4. 写 entity 和 `SyncOperation` receipt，继续处理 batch 中下一笔。
5. 所有 operation 成功处理后一次 commit。

这样同一个 user 的并发 push 会在 User 行锁上串行，不同 user 锁定不同的行而不互相阻塞；同一 batch 的 accepted versions 严格递增且唯一。已存在 receipt 的重试直接返回原版本，不递增。任何异常走 rollback，不能留下 entity、receipt 或 watermark 的部分提交。

实现不依赖 Python process lock。认证依赖注入得到的 `current_user` 可能已经存在于 SQLAlchemy Session identity map；加锁后必须显式通过 `populate_existing`、`Session.refresh()` 或等价且有测试证明的方式，确保 locked User 的 `sync_version` 来自加锁完成后的数据库最新值。禁止在锁等待前读取的缓存对象上直接递增。所有依赖本次 allocator 的 entity/receipt 查询也必须使用锁后最新状态，避免并发 entity edit 在锁等待期间使用过期对象。现有表结构和 migration 不变。

### 4.2 PostgreSQL 并发回归

新增真实 PostgreSQL integration test，使用隔离测试数据库/Compose 环境和合成 user，不连接生产：

- 两个独立 SQLAlchemy session（必要时通过两个真实 `/sync/push` 请求）同时提交不同 `client_op_id` 的 operation。
- 先用失败复现测试证明旧的 `user.sync_version += 1` 在并发 barrier 下可能产生重复版本或 cursor 遗漏；若数据库调度未稳定复现，测试仍检查旧实现的并发不变量并记录未复现原因，不能把串行 SQLite 结果当作通过。
- 修复后验证两笔 operation 都保存、版本唯一且严格递增、`User.sync_version` 等于最大版本、旧 cursor pull 同时得到两笔变化。
- 额外验证重复 `client_op_id` 不增加版本，以及异常 rollback 不返回虚假 watermark。
- 并发测试先把同一 User 预加载到各 SQLAlchemy session 的 identity map，再执行 locked select，验证分配使用锁后数据库最新 `sync_version`，而不是锁等待前的缓存值。

## 5. local mutation 与 remote merge 的边界

`onLocalMutation()` 只能由用户发起、并已通过 `LocalStateSession.write()` 同时持久化 state 和 `SyncQueue` 的本地 mutation 调用。它不能挂在泛化的 `onStateChanged` 或 `adoptState` 上，因为这些入口也会被同步 merge、server version 更新、cursor 保存、queue completion、owner/session 初始化和数据库恢复调用。

pull 后的 remote entity merge、server version 更新、cursor 持久化、`SyncOperation` completion、本地 owner/session 初始化、从数据库恢复 state 都只能更新现有 store state，不得发出 local mutation notification，也不得因 merge 自动再次 `requestSync()`。测试必须覆盖：

```text
B push
  -> A pull
  -> A merge remote changes
  -> A 不产生新的 local SyncOperation
  -> A 不因 merge 自己 requestSync
```

本地 store 的 mutation callback 与 FinanceStore 的 remote state adoption 使用不同代码路径；远端 merge 只调用 `adoptState`/notify，不调用 mutation callback。

## 6. 同步诊断日志

后端使用模块 logger 输出结构化/可检索字段：

- 安全化 user 标识（固定长度 hash，不输出原始 JWT、密码或 token）。
- `push`/`pull`、`since_version`、push 前后 sync version。
- `client_op_id`、entity、entity_id、accepted/conflict、返回 server version。

客户端 debug 日志输出本地 cursor、pending queue 数量、push watermark、pull since、pull 返回版本和最终保存 cursor。日志只记录诊断元数据，不记录 secrets 或完整认证头。

## 7. Android App 内更新设计

### 6.1 下载层

新增可注入 `AppUpdateDownloader`：

- 使用 Dart `HttpClient` 对 `AppVersion.downloadUrl` 发起 HTTPS 请求。
- 目标文件写入 app-specific cache/files 目录，先写 `.part` 文件；响应成功且文件完整后再 rename 为 APK。
- 通过 `Content-Length` 和已写入字节回调进度；未知长度显示已下载字节或不确定进度。
- HTTP 非 2xx、空文件、网络异常、取消和磁盘异常统一进入可重试的 `failed` 状态，并清理临时文件。
- 不申请 `READ_EXTERNAL_STORAGE` 或 `WRITE_EXTERNAL_STORAGE`。

### 6.2 原生安装层

新增可注入 `AppUpdateInstaller`，Android 默认实现使用 MethodChannel：

- Kotlin 侧接收 APK 文件路径，使用 `FileProvider` 转换为 `content://` URI。
- 配置 provider 与 `file_paths.xml`，授予系统安装器临时 read URI 权限。
- 使用 `ACTION_VIEW`、MIME `application/vnd.android.package-archive`，始终交给系统 Package Installer，禁止静默安装。
- Manifest 只增加必要的 `android.permission.REQUEST_INSTALL_PACKAGES`。
- Android 8+ 若 `canRequestPackageInstalls()` 为 false，跳转当前 App 的 `ACTION_MANAGE_UNKNOWN_APP_SOURCES`；返回 App 后复用缓存 APK 再尝试安装。
- MethodChannel 不可用或平台不支持时，才尝试现有外部 URL fallback；fallback 不是主路径，测试会证明主流程不依赖 Chrome。

### 6.3 更新状态与 UI

`AppUpdateStatus` 扩展为：`idle`、`checking`、`available`、`downloading`、`downloaded`、`installing`、`waitingForPermission`、`failed`、`upToDate`。

`AppUpdateStore` 负责检查、单任务下载、缓存路径、安装结果和 resume 后继续安装；下载中拒绝重复点击。对用户显示可理解的消息：

- “下载中 xx%”
- “下载失败，请检查网络后重试”
- “安装文件已准备好”
- “请允许随想记安装应用更新”

普通更新允许“稍后”；强制更新继续禁止跳过。设置页仍保留“检查更新”。更新 URL 继续来自 `/app/version`，测试和发布配置使用直接 APK HTTPS 地址，不使用 GitHub Release HTML 页面。

## 8. 版本、构建与安全边界

- 若仓库没有更高 build number，`pubspec.yaml`、产品常量和 Android metadata 升级为 `1.0.4+7`；若存在更高整数，使用其上的下一个整数，不倒退。
- 后端默认 `app_latest_version/app_latest_build`、Compose 默认值、版本测试和 release 文档对齐。
- 保留 applicationId、production release signing properties 和原签名 identity；不提交 keystore、密码、key.properties 或 secrets。
- release APK 输出到仓库外的受控目录，独立检查 package、version、versionCode、SHA-256 和 signing certificate SHA-256，并与 V1.0.3 artifact 对照。
- 不修改正式 PostgreSQL、不清库、不卸载或清除真实 App 数据、不删除历史 APK、不切换生产 `/app/version`、不创建正式 GitHub Release。

## 9. 测试与验收范围

先复现，再写失败测试，再修复，再回归：

1. 后端 PostgreSQL 并发失败复现测试，然后锁行修复和真实 PostgreSQL 回归。
2. Flutter 自动同步失败测试：普通账目、账户、分类、预算、快捷记均触发 request；同步期间连续 mutation 触发持续多轮 drain，且无并发 pipeline；active drain 的多个 caller 收到同一 drain Future，失败后 drain 停止且不在内部 retry。
3. 双设备双向新增、修改、删除、依赖实体、离线 queue、push 成功/pull 失败 cursor、重启保留 queue/cursor。
4. remote merge 边界：B push 后 A pull/merge 不产生新的 local SyncOperation、不触发 requestSync。
5. PostgreSQL locked User identity-map freshness：预加载旧 User 后并发锁行，版本仍从锁后的最新数据库状态分配。
6. 生命周期：登录/冷启动/resume/timer/后台停止。
7. 更新检查、下载进度、失败重试、取消、无 Chrome 主流程、未知来源权限返回、普通/强制更新。
8. 全量 backend pytest、Flutter `flutter analyze`、Flutter `flutter test`、Android release build；可用时执行真实 V1.0.3 → V1.0.4 覆盖升级。无真实条件必须标记 `NOT VERIFIED`，不伪造 PASS。

交付报告必须包含根因、修改文件、sync drain 语义、A/B 结果、PostgreSQL 并发结果、更新架构、版本号、测试结果、APK 路径/大小/SHA-256、签名一致性、真机覆盖升级状态、分支、最终 commit 和 git status。
