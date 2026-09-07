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
FinanceStore
    ↓
FinanceRepository
    ↓
Local SQLite / LocalMetadata
    ↓
SyncQueue
    ↓
FastAPI Sync API
    ↓
PostgreSQL
```

UI 只通过状态层执行业务操作。FinanceRepository 同时维护本地 FinanceState 和待提交的 SyncQueue；联网后由 FastAPI 校验身份、实体归属、依赖和版本，再写入 PostgreSQL。

## 3. 主要实体

```text
User：登录身份、用户级同步游标
Account：资产或负债账户
Category：收入/支出分类
Transaction：收入、支出或转账账目
Budget：按月份和分类设置的预算
SyncOperation：服务器已接受的客户端变更操作记录
```

## 4. 数据所有权

```text
Server = authoritative source
Local client = offline-first working copy
SyncQueue = uncommitted local mutations
```

服务器是跨设备共同账本。客户端本地数据是缓存和离线工作区；本地新建、编辑、删除在服务器确认前只属于待提交状态。每个实体和关联实体都必须属于当前用户，客户端不得通过 ID 访问或修改其他用户的数据。

## 5. 部署边界

服务端由 Docker Compose 启动 FastAPI 与 PostgreSQL。客户端构建时通过 `WEALTHMATE_API_BASE_URL` 注入 API 地址；部署后可通过 `/health` 的 `git_sha` 判断正在运行的 Backend 构建版本。
