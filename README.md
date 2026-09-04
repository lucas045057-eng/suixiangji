# 随想记

随想记是一款个人记账与极简资产管理应用，支持 Android、Windows 和 Web/PWA。

## V1.2 能力

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

## 本地启动服务端

```powershell
cd outputs/wealthmate_backend
Copy-Item .env.example .env
# 编辑 .env，修改数据库密码、JWT 密钥和登录密码
docker compose up -d --build
```

健康检查：`http://127.0.0.1:18000/health`

客户端构建时注入服务端地址：

```powershell
cd outputs/wealthmate_flutter
flutter pub get
flutter build apk --release --dart-define=WEALTHMATE_API_BASE_URL=http://服务器地址:18000
flutter build windows --release --dart-define=WEALTHMATE_API_BASE_URL=http://服务器地址:18000
```

完整部署和验收记录见 [随想记 V1.2 部署说明](outputs/WEALTHMATE-V1-DEPLOYMENT.md) 和 [验收状态](outputs/ACCEPTANCE-STATUS.md)。

内部 Flutter 包名、数据库名和环境变量仍保留 `wealthmate` 标识，仅用于兼容现有构建和数据，不影响产品显示名称“随想记”。
