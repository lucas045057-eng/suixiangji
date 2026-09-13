# WealthMate / 随想记 Architecture

## 1. 技术栈

```text
Client：Flutter
Local persistence：Drift / SQLite；LocalMetadata JSON
State：FinanceStore / FinanceState
Backend：FastAPI
Database：PostgreSQL
Sync：REST Push/Pull
Realtime：WebSocket currently auxiliary/echo
```

Flutter 同一套主要客户端代码覆盖 Android 与 Windows。SQLite/Drift 负责离线可用和本地队列持久化；服务器端 PostgreSQL 保存正式账本。

## 2. 整体架构

```text
Flutter UI
    ↓
FinanceStore（兼容组合 façade）
    ↓
Feature Stores / Repositories
    ↓
LocalStateSession（唯一串行本地聚合写入口）
    ├── LocalRepository / Drift
    └── SyncQueue
    ↓
SyncCoordinator
    ↓
FastAPI Sync API
    ↓
PostgreSQL
```

UI 只通过对应 Feature Store 执行业务操作。FinanceStore、FinanceRepository、ApiClient 保留旧入口作为兼容 façade；真实职责分别归属 Auth、Ledger、Assets、Budget、QuickEntry、Insights 和 Sync 模块。所有 FinanceState、Queue、cursor、冲突恢复和 tombstone 写入都必须经过同一个 LocalStateSession。联网后由 FastAPI 校验身份、实体归属、依赖和版本，再写入 PostgreSQL。

## 3. 最终模块树

```text
outputs/wealthmate_flutter/lib/
├── core/
│   ├── database/local_state_session.dart
│   ├── network/{api_session,api_response,api_transport}.dart
│   └── sync/{sync_coordinator,sync_remote_data_source}.dart
├── features/
│   ├── auth/{data,state,domain}/
│   ├── ledger/{data,state,domain}/
│   ├── assets/{data,state,domain}/
│   ├── budget/{data,state,domain}/
│   ├── quick_entry/{data,state,domain}/
│   ├── insights/{data,state,domain}/
│   └── backup/data/
└── data/{finance_repository,api_client,local_repository,sync_queue}.dart

outputs/wealthmate_backend/app/
├── models.py                 # 唯一 SQLAlchemy ORM 定义文件
├── auth/{router,service,schemas}.py
├── ledger/{router,service,domain,schemas}.py
├── assets/{router,service,domain,schemas}.py
├── budget/{router,service,domain,schemas}.py
├── quick_entry/{router,service,domain,schemas}.py
├── insights/{router,service,domain,schemas}.py
├── sync/{router,service,schemas,ordering,conflict,idempotency}.py
├── backup/{router,service,schemas}.py
├── api.py                   # 兼容导出与 Router aggregation
├── domain.py                # 兼容导出
├── schemas.py               # 兼容导出
└── security.py              # 兼容导出
```

## 4. 主要实体

```text
User：登录身份、用户级同步游标
Account：资产或负债账户
Category：收入/支出分类
Transaction：收入、支出或转账账目
Budget：按月份和分类设置的预算
SyncOperation：服务器已接受的客户端变更操作记录
```

## 5. 数据所有权

```text
Server = authoritative source
Local client = offline-first working copy
SyncQueue = uncommitted local mutations
```

服务器是跨设备共同账本。客户端本地数据是缓存和离线工作区；本地新建、编辑、删除在服务器确认前只属于待提交状态。每个实体和关联实体都必须属于当前用户，客户端不得通过 ID 访问或修改其他用户的数据。

## 6. 部署边界

服务端由 Docker Compose 启动 FastAPI 与 PostgreSQL。客户端构建时通过 `WEALTHMATE_API_BASE_URL` 注入 API 地址；部署后可通过 `/health` 的 `git_sha` 判断正在运行的 Backend 构建版本。

本轮只做职责边界抽取，不新增或重写数据库 Schema；`app/models.py` 与历史 migration 保持不变。Sync 只抽取 Coordinator、Router 和 Service 边界，协议字段、排序、事务、幂等、游标、冲突和软删除语义保持原样。
