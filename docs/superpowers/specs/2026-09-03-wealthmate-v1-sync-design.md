# WealthMate V1 可同步账本设计

## 目标

交付一个个人使用的财务管家 V1：手动或自然语言记账、账户与净资产管理、人民币及已由汇率源验证的币种折算、手机与 Windows 客户端同步、程序计算后由 AI 解释的月度报告。

## 边界

- 服务端是最终共同账本；客户端是本地缓存和离线工作区。
- 账目正式写入必须经过用户确认；AI 只生成草稿和报告文字。
- 所有核心金额由程序计算；没有可靠汇率时保留原币金额并标记待补充，不猜测。
- 删除采用软删除，保留同步可见的变更记录。
- 以 `client_op_id` 做幂等键；同一设备重试不会产生重复账目。
- 历史净资产保存当时的 CNY 折算结果，不被后续汇率重写。
- V1 不接支付、银行、财经行情、投资组合或交易能力。

## 组件

```text
Flutter Android / Windows
        │ REST + 可选 WebSocket
        ▼
FastAPI ─ SQLAlchemy ─ PostgreSQL
        ├─ 账目、账户、分类、预算
        ├─ 汇率快照与净资产快照
        ├─ 幂等同步日志
        ├─ 月度报告任务（APScheduler）
        └─ Agent 草稿 / 报告日志（LangGraph-compatible adapter）
```

客户端离线时先写入本地 SQLite/Drift 数据库和同步队列；联网后按 `client_op_id` 推送，再按 `server_version` 拉取。当前仓库已保留 SharedPreferences demo fallback，并提供 Drift schema 作为正式本地存储迁移基线。

## 核心数据约束

账目和账户都保留 `currency`。每一笔非 CNY 金额可同时有：`original_amount`、`original_currency`、`cny_amount`、`exchange_rate`、`exchange_rate_date`、`exchange_rate_source`。CNY 账目汇率为 1；缺汇率时 `cny_amount` 为空，统计明确显示待补充数量。

收入/支出参与月度收支；转账只改变账户余额，不进入收入、支出或储蓄率。资产账户余额为正向资产，负债账户余额按负债计算。账户余额以正式账目和初始余额推导，服务端不接受客户端直接覆盖余额。

## API 最小集合

- `GET /health`
- `POST /auth/login`
- `GET/POST/PATCH/DELETE /accounts`
- `GET/POST/PATCH/DELETE /transactions`
- `POST /agent/draft`
- `GET /stats?month=YYYY-MM`
- `GET /wealth`
- `GET/POST /exchange/rates`
- `GET /reports/monthly/{month}`
- `POST /sync/push`、`GET /sync/pull?since_version=N`
- `GET /backup/export`、`POST /backup/restore`

## AI 与可靠性

规则关键词和用户历史偏好优先，模型只在必要时参与分类。模型适配器支持在线模型和 Ollama；未配置模型时，基础记账、资产和同步不受影响，报告接口返回准确的结构化统计并明确 AI 不可用。所有 AI 调用记录任务、模型、状态、Token/成本元数据和结果摘要，不把原始私密备注写入日志。

## 验收映射

后端测试覆盖金额/转账/汇率/统计/幂等同步/备份恢复；客户端保留手动记账、草稿确认、本地队列、报告和 API 接入。由于本机当前没有 Flutter/Dart、Docker 或后端依赖运行环境，APK、Windows 二进制和真实 PostgreSQL 联机验收必须在安装对应工具链后执行，交付文档会明确列出命令与状态。
