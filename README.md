# 随想记

随想记是一款个人记账与极简资产管理应用，支持 Android、Windows 和 Web/PWA。

## 当前版本

- 当前线上版本：**V1.1.0（build 14）**
- Flutter：`1.1.0+14`
- 后端：FastAPI + PostgreSQL，生产部署提交 `6bfbe0b`，迁移至 `0008_v110_backup_v3`
- 最低支持版本：`1.0.0+3`
- Android 网络层继续使用 V1.0.1 Embedded Cronet，并保留 `cronetHttpNoPlay=true` 构建参数。

下载与校验：

- 直链：https://download.suixiangji.icu/app/suixiangji-v1.1.0-build14.apk
- GitHub：[Release v1.1.0](https://github.com/lucas045057-eng/suixiangji/releases/tag/v1.1.0)
- sha256：`4A152166B8F425E30523EEAFA93E31283190A04C04B44AAD350B443CB710C333`
- 签名证书与历史版本一致，可直接覆盖升级。

## V1.1.0 增量

### 余额校准改为调整流水

- 校准不再改写账户初始余额，而是写入一条带符号人民币差额的「调整」流水：计入账面余额，但不计入收支、预算与储蓄率，可随时撤销（撤销走反向流水）。
- 历史月份余额与净值不再被追溯改写；跨币种账户按人民币口径校准，已落账的换算快照冻结，刷新汇率不再重算历史。
- 校准需联网获取余额基准；基准为有效期 10 分钟的签名凭证，离线时保留草稿、联网后原样重发，基准过期需用户重新确认目标金额。

### 同步协议 V2 与冲突隔离

- 一触即断的「毒队列」已消除：业务校验失败的操作进入 `rejected` 并以字段级原因回滚，合法操作照常提交，整批不再回滚。
- 账户配置支持字段级三方合并：两台设备改不同字段互不覆盖；改同一字段时服务端值胜出并返回 `field_conflicts` 明细。
- 默认账户升级为用户偏好实体同步，跨设备一致；服务端可设定最低协议版本（低于门槛返回 426）。
- 客户端按自身能力比对版本门禁，不会因服务端声明而被误锁。

### 备份 v3

- 备份包含调整记录、用户偏好与协议元信息，兼容导入 v1/v2 旧备份；重复恢复幂等。
- 注意：恢复包含调整记录的备份后，`1.0.x` 客户端需要升级到 1.1.0 才能继续同步；导出会推进同步版本并写审计收据。

### 净值与外币

- 净值支持按日期回放（截至某日），月末自动留快照。
- 存在待换算的外币账户时，相关金额显示「待换算」而不是 0，避免把未知当零。

验收基线：后端全量 568 passed / 20 skipped，Flutter 全量 561 passed，`flutter analyze` 仅 2 条既有 info；真实 PostgreSQL 并发与备份用例在服务器一次性容器内跑绿，并有两轮独立回归。

## 早期版本能力

- **V1.0.9**：随口记推算卡按昨日分类逐张出卡；快捷记参照报错与云端解析失败回退修复。
- **V1.0.8**：随口记流式生成（SSE 逐卡到达）与方向 A 灰白纸感视觉重设计。
- **V1.0.7**：随口记（一句话拆账）——一句话生成至多 8 张候选卡片，逐项核对后原子入账；云端 LLM 解析先行，可关闭云端解析回退纯本地规则；默认分类词表扩至 13 类。
- **V1.0.5 / V1.0.6**：账户用途、归档与可搜索的账户管理；汇率快照进入同步队列；月度总预算与分类分配；恢复码重置密码；Drift 写入同时持久化财务状态与同步队列。
- **V1.0.0 能力**：自然语言快捷记（分类/账户/默认设置/已确认记忆自动补齐，确认后才入账）、自定义分类与账户、手机与电脑同一个 FastAPI + PostgreSQL 服务同步（离线队列、去重）、预算提醒、周期统计、资产/负债、汇率快照与月度分析。

历史版本的部署、验收与遗留项见 `docs/` 与 `docs_review/`；V1.1.0 的发布计划与已知项见 `docs_review/release-1.1.0-plan.md`。

## 目录

- `outputs/wealthmate_flutter/`：Android + Windows Flutter 客户端源码。
- `outputs/wealthmate_backend/`：FastAPI、PostgreSQL 和 Docker Compose 服务端。
- `outputs/wealthmate/`：无需后端即可预览的 Web/PWA 版本；此目录为无后端本地演示版（demo），非维护路径，正式功能在 Flutter 客户端。
- `outputs/website/`：官网静态站点源码。
- `docs/`：产品规格和实施计划；`docs_review/`：三方审查、架构设计与验收报告。
- `tests/`：Web/PWA 测试。

模块化边界：Flutter 的 Auth、Ledger、Assets、Budget、QuickEntry、Insights、Backup 和 Sync 分别位于 `lib/features/` 与 `lib/core/`；Backend 对应模块位于 `app/{auth,ledger,assets,budget,quick_entry,insights,sync,backup}/`。同步与账务的关键实现集中在 `app/sync/`（V1 主流程、V2 协议、偏好、V1 限定修复）、`app/assets/{calibration,replay}.py` 与 `app/core/financial_lock.py`，客户端对应 `lib/core/sync/` 与 `lib/features/assets/domain/asset_rules.dart`。

旧的 `FinanceStore`、`FinanceRepository`、`ApiClient` 和 `app/api.py` 仅作为兼容 façade/聚合入口。本地 FinanceState 与 SyncQueue 的写入统一经过 `LocalStateSession`，`app/models.py` 仍是唯一 SQLAlchemy 模型定义文件。

## 本地启动服务端

```powershell
cd outputs/wealthmate_backend
Copy-Item .env.example .env
# 编辑 .env，修改数据库密码、JWT 密钥和登录密码
docker compose up -d --build
# 首次启动或升级后执行迁移
docker compose exec api alembic upgrade head
```

健康检查：`http://127.0.0.1:18000/health`

客户端构建时通过集中配置注入服务端地址。下面的地址仅用于开发/测试：

```powershell
cd outputs/wealthmate_flutter
flutter pub get
flutter build windows --release --dart-define=WEALTHMATE_ENVIRONMENT=development --dart-define=WEALTHMATE_API_BASE_URL=http://127.0.0.1:18000
```

正式环境必须通过构建守卫注入固定的 HTTPS API 地址 `https://api.suixiangji.icu`：

```powershell
pwsh -NoProfile -File tools/build-android-release.ps1 -FlutterProjectPath outputs/wealthmate_flutter -OutputPath outputs/wealthmate_flutter/build/app/outputs/flutter-apk/app-release.apk -SigningPropertiesPath <controlled-signing-properties-path> -Environment production -ApiBaseUrl https://api.suixiangji.icu -VersionName 1.1.0 -VersionCode 14 -CronetHttpNoPlay
```

> 构建前需为当前进程预热 HTTPS 代理（`$env:HTTPS_PROXY`），sqlite3 原生资产由 Flutter hook 从 GitHub 下载，直连会超时导致 `compileFlutterBuildRelease` 失败。

PRODUCTION DOMAIN：api.suixiangji.icu

## Sync Status

本地优先的多端同步已完成双向 CRUD、离线队列、幂等、冲突恢复、tombstone 传播、重启持久化与双设备回归；V1.1.0 起升级为 V2 协议（字段级合并、`rejected`/`conflicts` 分离、协议下限门禁）。

Verified checkpoint: `sync-v1.0-rc1`

详细架构、恢复报告、测试矩阵和构建指纹见 [`docs/`](docs/)、[同步架构](docs/sync-architecture.md)、[恢复报告](docs/sync-recovery-report.md)、[发布检查点](docs/release-checkpoint.md) 与 `docs_review/account-sync-calibration-design.md`（V1.1.0 同步/校准架构定稿）。

内部 Flutter 包名、数据库名和环境变量仍保留 `wealthmate` 标识，仅用于兼容现有构建和数据，不影响产品显示名称“随想记”。
