# 随想记 V1 API

这是手机 App 和 Windows App 共用的正式账本服务。客户端不互相直连，两个客户端都连接同一个 API；服务器 PostgreSQL 是最终账本，客户端本地数据只作离线缓存和待同步队列。

## 启动

1. 复制 `.env.example` 为 `.env`，至少修改数据库密码、登录密码和 JWT 密钥。
2. 在本目录执行 `docker compose up -d --build`。
3. 检查 `http://服务器地址:18000/health`。
4. 默认登录用户名和密码以 `.env` 为准；首次登录会创建个人用户和基础分类。

不使用 Docker 时，可安装 `requirements.txt` 后执行：

```text
uvicorn app.main:app --host 0.0.0.0 --port 8000
```

## 客户端配置

开发/测试时，Windows 客户端可以连接本机 `http://127.0.0.1:18000`；手机不能使用 `127.0.0.1`，局域网联调可以使用局域网地址。正式环境必须由发布环境注入 HTTPS API 域名。本项目当前没有提供最终正式域名，不得把局域网地址、IP 或占位域名用于正式 V1.0.4。

Flutter 参数示例：

```text
flutter run -d windows --dart-define=WEALTHMATE_ENVIRONMENT=development --dart-define=WEALTHMATE_API_BASE_URL=http://127.0.0.1:18000
flutter run -d <android-device> --dart-define=WEALTHMATE_ENVIRONMENT=development --dart-define=WEALTHMATE_API_BASE_URL=http://192.168.1.20:18000
```

版本接口为匿名 `GET /app/version`，由 `WEALTHMATE_APP_LATEST_VERSION`、`WEALTHMATE_APP_LATEST_BUILD`、`WEALTHMATE_APP_MINIMUM_SUPPORTED_BUILD`、`WEALTHMATE_APP_FORCE_UPDATE`、`WEALTHMATE_APP_DOWNLOAD_URL` 和 `WEALTHMATE_APP_RELEASE_NOTES` 提供静态发布元数据。正式下载地址必须是 HTTPS；空地址表示尚未配置发布下载页。

当前发布状态：

```text
产品版本：1.0.4
Flutter Version：1.0.4+7
Android versionCode：7
PRODUCTION DOMAIN：NOT CONFIGURED
APK UPDATE SIGNING：NOT VERIFIED
```

## 已实现的 V1 边界

- JWT 登录；账户、分类、账目增删改查。
- `client_op_id` 幂等推送，同一操作重试不会重复入账。
- `server_version` 增量拉取；删除为软删除。
- CNY 和带来源/日期/汇率的外币折算；没有汇率就返回待补充。
- 收支、分类、储蓄率、资产/负债/净资产和月度报告接口。
- 备份导出与恢复；AI 日志记录任务、模型、状态、Token 元数据和结果摘要。
- 规则优先生成草稿；AI 未配置时基础记账继续可用。

## 模块边界

Auth、Ledger、Assets、Budget、QuickEntry、Insights、Sync 和 Backup 的 Router/Service 分别位于对应 `app/` 子目录。`app/api.py`、`app/domain.py`、`app/security.py` 和 `app/schemas.py` 仅保留兼容导出或路由聚合；`app/models.py` 是唯一 SQLAlchemy ORM 模型定义文件。Sync 的 `/sync/push`、`/sync/pull` 字段、依赖排序、提交回滚、幂等、冲突和租户隔离语义保持不变。

## 重要说明

Frankfurter 只用于低频查询汇率，不在每次记账时猜测或实时刷新。账目保存的是入账当时的折算快照，历史报告不会被新汇率改写。报告没有可用模型时会明确显示 AI 未配置/数据不足，不伪造分析。
