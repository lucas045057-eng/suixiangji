# Task 5 — Budget module收尾报告

## 结果

Budget 职责已抽取并接入 Flutter 与 Backend：

- Flutter 新增 `features/budget` 的 domain rules、repository、remote data source、store 与 focused tests。
- Backend 新增 `app/budget` 的 router、service、schema、domain，并由 `main.py` 注册路由。
- `app/api.py` 与 `app/schemas.py` 保留兼容聚合入口；同步仍复用 Budget 序列化和保存委托。
- Budget 页面改为依赖 `BudgetStore`；Dashboard 读取 BudgetStore 的只读预算进度/提醒视图。
- `FinanceRepository.applyLocalBudget` 保留兼容入口并委托 BudgetRepository；Budget 状态与 queue 写入均通过共享 `LocalStateSession`。提醒 key 仍使用既有本地 metadata 机制。

## 保持的契约

- `/budgets` 的 create/update/list/delete 响应字段与状态语义保持不变。
- `month=YYYY-MM` 筛选、正数阈值校验、分类归属校验、用户租户隔离和软删除保持不变。
- 阈值规则保持：低于 80% 无提醒，80% 为 warning，100% 为 exhausted，高于 100% 为 over。
- 提醒 key 按预算/月/阈值去重；预算 queue operation 仍保留稳定的 `entity`、`entityId`、payload 与 `clientOpId` 结构。
- `app/models.py`、schema/migration、sync 协议和 Auth 边界未被拆改。

## 验证

已运行：

- `flutter test test/features/budget/budget_store_test.dart test/overview_pages_test.dart`：11 项通过。
- 后端 `PYTHONPATH=tests;.` 下的 `python -m unittest tests.test_api -v`：33 项通过。
- Flutter 目标文件 `flutter analyze`：无问题。
- Backend Budget/API 目标文件 `compileall`：通过。
- `git diff --check`：通过。

首次直接运行后端 unittest 时因测试内部的顶层导入找不到 `test_sync_acceptance` 而加载失败，补充 `tests` 到模块路径后重跑通过；这不是断言失败。

按要求未运行：Flutter full test、pytest 全量、unittest 全量、`npm test`。未执行 push、PR、部署或生产数据库操作。

## 明显缺口 / concerns

- 本次仅做 Task 5 范围的聚焦验证，未覆盖全量回归；跨模块已有调用方的潜在回归仍需后续阶段统一验证。
- BudgetRepository 当前主要负责本地优先写入与远端数据源封装，远端 CRUD 方法由现有 ApiClient 保持兼容；本阶段未改变在线同步生命周期。
- 当前工作区已有其他阶段的未提交变更，本 commit 按用户要求包含本次 Budget 收尾相关工作区内容；未执行 reset、checkout、merge 或 cherry-pick。

## Fix round 1 — scoped review findings

基于 HEAD `437a69f` 完成以下最小修正，未进入下一 Phase：

- `FinanceStore` 现在拒绝 `BudgetStore.repository.session` 与主 `FinanceRepository.session` 不同的注入，确保 Budget 的 FinanceState/queue 写入不会旁路主 session。
- Budget focused tests 改为用重建的 `LocalStateSession`/`LocalRepository` 验证持久化，并断言 `clientOpId`、`entity`、`type`、`entityId` 和完整 payload；新增 warning、exhausted、over 的真实提醒路径与重复调用去重覆盖。
- AppShell 桌面详情面板改从 `BudgetStore.progress` 读取预算存在性；Dashboard 的兼容参数仍保留，但正式 AppShell 路径不再从 `FinanceStore.metrics.budgetProgress` 取预算视图。
- 删除 `app/api.py` 中未使用的 Budget route/schema imports；API、schema、migration、sync、Auth、Assets、Ledger 未改行为。

TDD 记录：新增 foreign-session 边界测试先在 `437a69f` 上失败（未抛出 `ArgumentError`），加入 session 身份校验后通过。

Fix round 1 验证：

- `flutter test test/features/budget/budget_store_test.dart`：8 项通过。
- 目标 Flutter 文件 `flutter analyze`：无问题。
- Backend Budget/API 目标文件 `compileall`：通过。
- `git diff --check`：通过。

本轮仍未运行 Flutter full test、pytest 全量、unittest 全量、`npm test`；未执行 push、PR、部署或生产数据库操作。
