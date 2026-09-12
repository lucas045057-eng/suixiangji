# Task 4 / Phase 3 Assets 验证报告

## 状态

- Branch: `refactor/modular-monolith`
- Initial commit: `ffada08c29532031e9748a11d8a1eaeabb773e65`
- Final commit: 见本次提交后的 HEAD
- Commit message: `refactor(assets): extract assets module`
- 工作目录中的上一代理未提交改动已审计并保留，未执行 rollback/reset/checkout/清理。

## 本阶段改动

Flutter 新增 Assets data/domain/state 边界：

- `outputs/wealthmate_flutter/lib/features/assets/data/assets_repository.dart`
- `outputs/wealthmate_flutter/lib/features/assets/data/assets_remote_data_source.dart`
- `outputs/wealthmate_flutter/lib/features/assets/domain/asset_rules.dart`
- `outputs/wealthmate_flutter/lib/features/assets/state/asset_store.dart`
- `outputs/wealthmate_flutter/test/features/assets/asset_store_test.dart`

Flutter 页面与兼容层接入 `AssetStore`：

- Wealth、汇率、账户详情、设置页和 `AppShell`
- `FinanceStore` 的账户/汇率 façade 委托 Assets
- `FinanceRepository` 的账户兼容写入委托 `AssetsRepository`
- `FinanceRules` 的账户余额计算委托 `AssetRules`
- 账本变更会通知财富选择器刷新；删除/失效会话路径的队列清理通过 `LocalStateSession`

Backend 新增 Assets router/service/schema/domain，并在 `main.py` 注册：

- `outputs/wealthmate_backend/app/assets/router.py`
- `outputs/wealthmate_backend/app/assets/service.py`
- `outputs/wealthmate_backend/app/assets/schemas.py`
- `outputs/wealthmate_backend/app/assets/domain.py`

`api.py` 仅保留 Assets 兼容 re-export（`_account_json`、`_save_account`、`_wealth` 和旧汇率函数名），账户、财富、汇率路由已由 Assets router 承担；scheduler 改为直接导入 Assets service 的财富操作。旧测试的汇率异常 mock 目标同步到新 service 边界，断言未改变。

## TDD / 专项验证

- Flutter `flutter test test\\features\\assets\\asset_store_test.dart test\\finance_rules_test.dart`：通过，19 tests。
- Flutter 新增回归测试（账本写入通知财富选择器）先失败，修复通知边界后通过。
- Flutter 该回归单测：通过，1 test。
- Backend `PYTHONPATH=tests python -m unittest tests.test_api tests.test_domain -v`：通过，38 tests。
- Backend `python -m unittest discover -s tests -v`：通过，49 tests（在 Assets 路由切换后执行）。
- Backend `python -m pytest --basetemp=E:\\codex\\suixiangji\\.pytest-tmp tests/test_beta_hardening.py::test_rate_upstream_error_is_sanitized -q`：通过，1 test。
- Backend `python -m compileall -q app tests`：通过。
- Flutter `flutter analyze`：通过，No issues found。
- `git diff --check`：通过；仅有 Git 的 LF/CRLF 提示，无 whitespace error。

## 约束确认

- API URL、HTTP method、请求字段、响应字段和状态码：未改变；原账户 CRUD、财富、汇率端点保留。
- Schema / migrations：未修改；`app/models.py` 未修改，Account、ExchangeRate、NetWorthSnapshot 仍由原 ORM 定义拥有。
- Sync：未改算法、排序、协议字段、幂等、cursor、tombstone、冲突恢复或 tenant isolation；sync 兼容调用使用 Assets service façade。
- Flutter 聚合状态与 queue 写入：Assets、Ledger、FinanceStore 相关写入均经同一 `LocalStateSession`；没有新增 `LocalRepository.save`/`saveQueue` 旁路。`saveOwnerUserId` 仍是 owner metadata 技术写入，不是聚合状态写入。
- 未连接生产数据库，未执行 push、PR、部署或生产数据操作。

## Fix round 1（基于 `4800d222314d45f0dd1e84da6dbe79b714cc680b`）

- Initial commit: `4800d222314d45f0dd1e84da6dbe79b714cc680b`。
- 修复范围：共享 `LocalStateSession` 的 Assets/Ledger 初始写入不再以旧 `baseState` 覆盖另一侧；push/pull 网络返回阶段改为在当前 session 写入闭包中合并，冲突恢复保持同一边界；FinanceStore façade 同步 AssetStore validation message。
- 新增回归：交错新增账户与交易、push/pull 网络等待期间新增账户、FinanceStore 账户重复名错误消息。
- TDD 记录：新增回归和既有大部分 focused 用例先暴露失败；首轮修复验证中新增回归通过，但旧 push 兼容用例因用户分区空状态与调用方内存 state 的兼容差异仍失败。随后已补充“当前 session 优先、只回填缺失实体”的最小兼容修复；遵照用户要求立即停止，最后补丁未重新运行测试。
- 本轮未重新运行 Flutter analyze、Backend compile/pytest/unittest 或 full regression；上一节中的 Task 4 基线结果仍保留，不将其冒充为本轮结果。
- 本轮 `git diff --check`：通过；仅有 Git LF/CRLF 提示，无 whitespace error。
- API URL/method/request/response/status、schema/migrations、sync 协议/排序/cursor/冲突规则、tenant isolation、Auth/partition/session 语义未主动改变；未改 `app/models.py`，未 push/PR/部署/生产数据库。
- Final fix commit: `3c47dc9` (`fix(assets): preserve serialized state updates`).

## Post-fix verification

After fix round 1 and the scoped re-review approval, the following commands were rerun from the working tree at `3c47dc9`:

- Root `npm test`: 7 passed, 0 failed.
- Backend `python -m compileall -q app tests`: passed.
- Backend `python -m pytest tests -q --basetemp=C:\\Users\\Admin\\AppData\\Local\\Temp\\suixiangji-pytest-assets`: 119 passed, 0 failed, 1 pre-existing warning.
- Backend `python -m unittest discover -s tests -v`: 49 passed, 0 failed.
- Flutter focused `flutter test test/data_repository_test.dart test/finance_store_test.dart test/features/assets/asset_store_test.dart`: 36 passed, 0 failed.
- Flutter `flutter analyze`: no issues found.
- Flutter full `flutter test`: 214 passed, 0 failed.
- `git diff --check`: passed.

The old push compatibility assertion and the new interleaving/session regression tests both pass after the final fix. The temporary pytest directory was removed after verification and was not committed.

## 未运行与剩余风险

因用户要求停止长时间验证，本轮未运行：

- 根目录 `npm test`
- 完整 Flutter `flutter test`
- 完整共享 gate 的 `dart format --output=none --set-exit-if-changed .`

已运行的 focused、compile、unittest discover 和 analyze 均通过；未运行项仍需在后续集成窗口补跑。运行 pytest 时在仓库生成了本地临时目录 `.pytest-tmp`，未纳入本次 commit。
