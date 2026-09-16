# 随想记

随想记是一款个人记账与极简资产管理应用，支持 Android、Windows 和 Web/PWA。

## 当前版本

- 产品版本：V1.0.2
- Flutter：`1.0.2+5`
- 最低支持版本：`1.0.0+3`
- Android 网络层继续使用 V1.0.1 Embedded Cronet，并保留 `cronetHttpNoPlay=true` 构建参数。

## V1.0.0 能力

- 自然语言快捷记：输入“今天吃饭吃了 30 元”，系统按分类、账户、默认设置和已确认记忆自动补齐。
- 自动补齐后始终可以“修改”，确认后才正式入账。
- 自定义分类和账户名称，账户配置可编辑且保留历史账目。
- 昵称、用户名和密码可在“我的 → 账户与登录”中修改。
- 手机与电脑通过同一个 FastAPI + PostgreSQL 服务同步，支持离线队列和去重。
- 预算提醒、周期统计、资产/负债、汇率快照和月度分析。

## 目录

- `outputs/wealthmate_flutter/`：Android + Windows Flutter 客户端源码。
- `outputs/wealthmate_backend/`：FastAPI、PostgreSQL 和 Docker Compose 服务端。
- `outputs/wealthmate/`：无需后端即可预览的 Web/PWA 版本。
- `docs/`：产品规格和实施计划。
- `tests/`：Web/PWA 测试。

模块化边界已完成：Flutter 的 Auth、Ledger、Assets、Budget、QuickEntry、Insights、Backup 和 Sync 分别位于 `lib/features/` 与 `lib/core/`；Backend 对应模块位于 `app/{auth,ledger,assets,budget,quick_entry,insights,sync,backup}/`。旧的 `FinanceStore`、`FinanceRepository`、`ApiClient` 和 `app/api.py` 仅作为兼容 façade/聚合入口。本地 FinanceState 与 SyncQueue 的写入统一经过 `LocalStateSession`，`app/models.py` 仍是唯一 SQLAlchemy 模型定义文件。

## 本地启动服务端

```powershell
cd outputs/wealthmate_backend
Copy-Item .env.example .env
# 编辑 .env，修改数据库密码、JWT 密钥和登录密码
docker compose up -d --build
```

健康检查：`http://127.0.0.1:18000/health`

客户端构建时通过集中配置注入服务端地址。下面的地址仅用于开发/测试：

```powershell
cd outputs/wealthmate_flutter
flutter pub get
flutter build windows --release --dart-define=WEALTHMATE_ENVIRONMENT=development --dart-define=WEALTHMATE_API_BASE_URL=http://127.0.0.1:18000
```

正式环境必须注入最终的 HTTPS API 地址；本仓库当前没有猜测或固化正式域名：

```powershell
pwsh -NoProfile -File tools/build-android-release.ps1 -FlutterProjectPath outputs/wealthmate_flutter -OutputPath outputs/wealthmate_flutter/build/app/outputs/flutter-apk/app-release.apk -SigningPropertiesPath <controlled-signing-properties-path> -Environment production -ApiBaseUrl https://api.suixiangji.icu -VersionName 1.0.3 -VersionCode 6 -CronetHttpNoPlay
```

PRODUCTION DOMAIN：NOT CONFIGURED

版本冻结与 Git 收口记录见 [V1.0.0 项目状态](docs/PROJECT_STATE.md) 和 [Git 清理报告](docs/V1.0.0-GIT-CLEANUP-REPORT.md)。

## Sync Status

Core local-first multi-device synchronization has completed bidirectional CRUD, offline queue, idempotency, conflict recovery, tombstone propagation, restart persistence and final dual-device regression.

Verified checkpoint: `sync-v1.0-rc1`

详细架构、恢复报告、测试矩阵和构建指纹见 [`docs/`](docs/)、[同步架构](docs/sync-architecture.md)、[恢复报告](docs/sync-recovery-report.md) 和 [发布检查点](docs/release-checkpoint.md)。

内部 Flutter 包名、数据库名和环境变量仍保留 `wealthmate` 标识，仅用于兼容现有构建和数据，不影响产品显示名称“随想记”。
