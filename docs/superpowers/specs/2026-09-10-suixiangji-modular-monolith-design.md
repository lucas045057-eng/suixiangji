# 随想记模块化单体重构设计

**日期**：2026-09-10  
**范围**：`outputs/wealthmate_flutter`、`outputs/wealthmate_backend`、必要的架构文档与测试  
**实施方式**：当前本地目录原地修改，分支为 `refactor/modular-monolith`；不 push、不创建 PR、不连接线上环境。

本轮执行的额外硬约束：

- 以职责边界和依赖方向为拆分依据，不为凑目录机械搬移文件。
- 第一轮不拆 SQLAlchemy `app/models.py`；它继续作为唯一的 ORM 模型定义与 metadata 注册入口。业务模块可以按职责引用其中的模型，但本轮不新增重复的 SQLAlchemy Model 定义。
- `LocalStateSession` 是 Flutter 本地聚合状态的唯一串行写入口；任何 Feature Store、Repository、同步恢复和 demo 恢复都必须通过它提交状态写入，禁止旁路直接持久化或并发覆盖。
- Sync 阶段只抽取边界、接口和唯一 Coordinator，不重新设计、优化或改变现有同步算法、排序规则、冲突策略和协议字段。
- 每个 Phase 完成后必须先执行完整回归、检查并报告 diff，得到阶段结果后才进入下一 Phase。

## 1. 目标与不变项

本次工作只整理代码边界，不增加产品功能，不改变用户可见行为、核心页面流程、现有 API Contract 或同步协议。重构完成后，Flutter 页面依赖所属业务模块的 Store/Repository，后端路由只处理 HTTP 边界，业务规则进入 Service/Domain；跨模块同步仍由唯一的公共 Sync Engine/Coordinator 负责。

以下内容明确保持不变：

- API URL、HTTP method、请求字段、响应字段和状态码。
- 数据库表名、列名、主键、外键和现有数据语义。
- `Transaction.id`、`client_op_id`、`serverVersion`、`User.sync_version` 的职责。
- 离线队列持久化、幂等重放、增量 pull、tombstone、冲突恢复、依赖排序和用户隔离。
- AI 只能生成结构化草稿；真实账目和统计仍由确定性代码确认与计算。

本次不做 migration，不修改历史 migration，不删除表、不清空数据、不重建 PostgreSQL volume，也不引入微服务、消息队列、Redis、CQRS、Event Sourcing 或 Kubernetes。

## 2. 当前架构与主要耦合点

当前 Flutter 主要链路是：

```text
UI → FinanceStore → FinanceRepository → LocalRepository / ApiClient / SyncQueue
                         ↓
                    FinanceState / FinanceRules
```

当前后端主要链路是：

```text
FastAPI main → api.py → models.py / schemas.py / domain.py / security.py
                         ↓
                    PostgreSQL / SQLite
```

主要问题不是功能缺失，而是职责集中：

- `FinanceStore` 同时管理认证、账本、资产、预算、快捷记、统计、报告、汇率和同步生命周期，约 565 行。
- `FinanceRepository` 同时承担所有业务的本地状态修改、队列入列、push/pull、冲突恢复和缓存，约 493 行。
- `ApiClient` 同时包含认证、所有资源 CRUD、AI、统计、财富、汇率、报告和同步 HTTP 细节，约 327 行。
- 后端 `api.py` 约 896 行，包含所有 Router、响应转换、数据库写入、依赖排序、统计聚合和备份恢复逻辑。
- UI 页面直接依赖 `FinanceStore`，测试也大量直接构造 `FinanceStore + FinanceRepository`，因此不能一次性删除旧类型。
- 后端服务文件已有部分 AI/汇率服务，但 `api.py` 与 `scheduler.py` 仍互相依赖，拆分时必须先建立公共依赖和模块注册顺序。

## 3. 目标架构

### 3.1 Flutter Feature First

目标目录如下，只创建有实际职责的文件：

```text
lib/
├── app/
│   ├── app.dart
│   ├── bootstrap.dart
│   └── navigation/
├── core/
│   ├── auth/
│   ├── common/
│   ├── database/
│   ├── errors/
│   ├── network/
│   └── sync/
├── features/
│   ├── auth/
│   │   ├── data/
│   │   ├── domain/
│   │   ├── state/
│   │   └── ui/
│   ├── ledger/
│   │   ├── data/
│   │   ├── domain/
│   │   ├── state/
│   │   └── ui/
│   ├── assets/
│   │   ├── data/
│   │   ├── domain/
│   │   ├── state/
│   │   └── ui/
│   ├── budget/
│   │   ├── data/
│   │   ├── domain/
│   │   └── state/
│   ├── quick_entry/
│   │   ├── data/
│   │   ├── domain/
│   │   └── state/
│   └── insights/
│       ├── data/
│       ├── domain/
│       └── state/
└── main.dart
```

公共设施只提供技术能力：HTTP transport、Token store、Drift 数据库、通用本地状态存取和唯一 SyncCoordinator。业务 Repository 通过这些设施访问本地与远端，UI 不直接访问 HTTP 或数据库。

目标目录中可能出现的模块级 `models.py` 属于后续演进形态；本轮第一轮重构不创建或移动 SQLAlchemy 模型文件，先以职责边界、Router/Service、Flutter Store/Repository 和公共基础设施为拆分重点。

`FinanceState` 在第一阶段作为兼容的持久化聚合 DTO 保留，不把它继续当作所有业务规则的拥有者。各模块 Store 只拥有自己的状态切片和用例；如果必须写入现有聚合快照，通过一个无业务规则的本地状态会话完成。`FinanceStore` 最终固定为薄兼容门面/应用会话协调器并标记为 deprecated；它不再包含领域规则和资源 CRUD，业务页面不再依赖它承载具体业务。

`ApiClient` 拆为无业务含义的 `ApiTransport` 与各模块 RemoteDataSource。旧 `ApiClient` 暂时作为兼容门面委托给这些 DataSource，避免一次性破坏既有测试和外部构造代码。

### 3.2 Backend Module First

目标结构如下：

```text
app/
├── main.py
├── config.py
├── db.py
├── core/
│   ├── dependencies.py
│   ├── errors.py
│   ├── security.py
│   └── rate_limit.py
├── auth/
│   ├── router.py
│   ├── service.py
│   ├── schemas.py
│   └── models.py
├── ledger/
│   ├── router.py
│   ├── service.py
│   ├── schemas.py
│   ├── models.py
│   └── domain.py
├── assets/
│   ├── router.py
│   ├── service.py
│   ├── schemas.py
│   ├── models.py
│   └── domain.py
├── budget/
│   ├── router.py
│   ├── service.py
│   ├── schemas.py
│   └── models.py
├── quick_entry/
│   ├── router.py
│   ├── service.py
│   └── schemas.py
├── insights/
│   ├── router.py
│   ├── service.py
│   └── schemas.py
└── sync/
    ├── router.py
    ├── service.py
    ├── schemas.py
    ├── conflict.py
    └── ordering.py
```

数据所有权按业务划分：Auth 拥有 User；Ledger 拥有 Category/Transaction；Assets 拥有 Account/ExchangeRate/NetWorthSnapshot；Budget 拥有 Budget；Insights 拥有 MonthlyReport；Sync 拥有 SyncOperation 及版本/操作处理。AI 调用适配器和日志作为共享基础设施，由 QuickEntry/Insights 的 Service 调用，不把 AI 决策下沉到 Router。

`main.py` 只负责应用生命周期、公共中间件和各模块 Router 注册。`core/dependencies.py` 提供当前用户、数据库 Session 等依赖。每个 Router 负责验证参数、注入依赖、调用 Service 和返回既有响应；账户归属检查、分类/汇率/版本规则、事务写入和统计聚合进入对应 Service/Domain。

第一轮保留 `app/models.py` 作为唯一 SQLAlchemy 模型定义文件，不拆成模块级 `models.py`；模块只通过明确的 import 使用其所属模型。迁移期间保留 `app/api.py`、`app/schemas.py`、`app/domain.py` 作为薄兼容聚合层和 re-export 入口；真正的实现只保留在业务模块中。`db.py` 继续显式导入 `app.models`，确保 `Base.metadata.create_all` 和现有 SQLite 测试仍能注册完整元数据。模型文件的进一步拆分作为后续独立变更，不属于本轮。

## 4. 模块依赖与数据流

```text
Flutter UI
  ↓
Feature Store / Controller
  ↓
Feature Repository
  ↓
Feature RemoteDataSource + LocalStateSession
  ↓                         ↘
Core ApiTransport             Core SyncCoordinator
                              ↓
                         /sync/push + /sync/pull
```

业务模块不互相复制同步算法。模块只提供可同步实体的序列化/反序列化、mutation 构造和依赖元数据；SyncCoordinator 统一处理 queue、push、pull、cursor、幂等、冲突和 tombstone。本轮 Sync 只把现有实现放入清晰边界并接入唯一 Coordinator，不改变现有算法、时序、排序、冲突恢复或协议字段。统计和财富页面可以读取其他模块的只读快照，但不能修改其他模块的实体。

后端同步入口按稳定依赖顺序调用模块 Service：Account/Category 先于 Transaction/Budget；返回结果仍按原始 `client_op_id` 对应操作返回。冲突操作只恢复对应实体并移除对应队列项，不能全局清空队列。

## 5. 渐进式重构阶段

每个阶段都遵守“修改 → format → analyze/lint → 专项测试 → 完整回归 → diff review → 报告阶段结果 → 本地 commit”。阶段报告必须说明变更文件、行为/API/Schema 是否保持不变、专项测试与完整回归结果、剩余风险；报告完成前不得进入下一阶段。

1. **Phase 0：基线与脚手架**。记录现有测试、确认 branch 和 clean status；建立 `LocalStateSession` 的唯一串行写入契约、公共命名和兼容导出策略，不改变行为；SQLAlchemy `app/models.py` 保持不拆。
2. **Phase 1：Auth**。抽取 Flutter AuthRepository/AuthStore 和后端 auth Router/Service/Schema/Model，迁移登录、注册、Profile、Token、Session；保留旧构造入口。
3. **Phase 2：Ledger**。抽取 Transaction/Category 的 Flutter 与后端模块，迁移账本 CRUD、分类管理、金额规则；不改同步字段。
4. **Phase 3：Assets**。抽取 Account、ExchangeRate、NetWorth 和财富页面依赖，保持外币折算快照语义。
5. **Phase 4：Budget**。抽取 Budget、BudgetAlert、预算 CRUD 与阈值计算。
6. **Phase 5：QuickEntry**。抽取 AgentDraft、QuickMemory 和 AI 草稿流程，确认入账仍由 Ledger 用例完成。
7. **Phase 6：Insights**。抽取 Stats、Metrics、MonthlyReport 和 AI 报告生成，保证数字由确定性 Domain 计算。
8. **Phase 7：Sync**。最后集中整理队列、push/pull、冲突、tombstone、依赖排序和生命周期；只抽取边界并接入一个 Coordinator，不重写、优化或重新设计同步算法。
9. **收尾**。迁移 UI 和测试到 feature 入口，保留必要的兼容 façade，更新架构文档与目录说明，做全量回归。

## 6. 风险与控制

| 风险 | 控制措施 |
|---|---|
| Flutter 页面依赖旧 FinanceStore | 先加入薄适配层，再逐页迁移；每阶段保留旧测试入口 |
| 本地状态快照被多个 Store 同时写入 | 使用单一且串行的 LocalStateSession 写入入口，Store 只提交明确的领域 mutation；代码审查禁止旁路写入 |
| ApiClient 拆分导致错误映射或 401 行为变化 | 先抽 `ApiTransport`，集中保留状态码映射、Token 清理和 auth-expired 回调 |
| SQLAlchemy 模型循环导入或元数据遗漏 | 按模型所有权拆分，使用显式 model registry，在应用启动和测试入口统一导入 |
| Router 拆分改变响应包装或状态码 | 以现有 API 测试为合同，迁移一个路由组后立即执行专项测试 |
| 同步冲突、幂等和 cursor 回退 | Sync 最后处理；只做边界抽取，逐项对照现有测试和同步架构文档，不做算法优化 |
| accidentally touching user/production data | 仅使用本地测试数据库/独立 Compose；不执行 volume 删除、数据库清理或线上连接 |

## 7. 回滚方案

每个阶段一个本地 commit，出现回归时只回滚当前阶段 commit；不使用 `reset --hard`、不覆盖用户未提交修改。兼容门面保证阶段间可以暂时停留在新旧实现混合状态。数据库不做 schema 变更，因此代码回滚不需要 downgrade migration；测试数据库使用独立文件或独立 Compose 数据目录。

## 8. 测试策略

基线与最终回归至少包含：

- Web：`npm test`。
- Backend：从 `outputs/wealthmate_backend` 执行 `python -m unittest discover -s tests -v`，并执行 `python -m compileall -q app tests`。
- Flutter：`dart format --output=none --set-exit-if-changed .`、`flutter analyze`、`flutter test`。
- API 合同：登录/Profile、账户、分类、交易、预算、统计、财富、汇率、报告、备份和现有 `/sync/push`/`/sync/pull` 测试。
- 同步专项：相同 `client_op_id` 重放、严格增量 cursor、tombstone、冲突恢复、依赖排序、失败 batch 回滚和跨用户隔离；这些测试用于证明边界抽取未改变现有算法。
- 本地写入约束：测试所有 Feature Store、Repository、同步恢复和 demo 恢复路径都经过同一个串行 `LocalStateSession`，并覆盖连续写入不会丢失更新的场景。
- 架构约束：页面不得直接持有 `ApiTransport`/数据库；Router 不直接实现领域计算；同步算法只存在于 Core SyncCoordinator。

若本机 Docker Desktop 可用，额外执行独立本地 PostgreSQL Compose 健康检查和 API 冒烟测试；任何测试都不连接生产数据库。

## 9. 明确不改的内容

- 不增加家庭账本、股票/基金、实时行情、导入、社区、新预算、新 AI、新统计指标或新同步协议。
- 不改变产品名称、UI 视觉、核心导航和已有用户流程。
- 不修改数据库 Schema，不生成或修改 Alembic migration，不重建数据库或 volume。
- 不 push、不开远程分支、不创建 PR、不部署服务器、不访问线上数据库。

## 10. 完成定义

只有同时满足以下条件才算完成：

- Flutter 页面主要依赖各自 Feature Store，`FinanceStore` 不再承担全部业务。
- Backend `api.py` 不再承载绝大多数路由和业务逻辑，各模块拥有自己的 Router/Service。
- 全项目只有一套同步 Engine/Coordinator，协议字段和行为不变。
- 数据库 Schema、API Contract 和用户可见行为无变化。
- 所有基线测试不倒退，架构约束测试通过。
- 最终报告包含 branch、HEAD、dirty status、目录树、模块拆分、同步协议、数据库/migration 状态、测试结果、技术债和下一步建议，并明确：`Remote push: NO`、`PR created: NO`、`Server deployment: NO`、`Production DB touched: NO`。
