# 随想记 瘦身执行报告（2026-10-23）

审批方式：Ponytail skill 全库审查（pi 架构分析 + codex 功能审计 + codebuddy 冗余扫描）后，经用户逐项确认执行。
约束：只在本地 main 提交，未 push、未触碰生产服务器 api.suixiangji.icu。

## 审查结论引用

- 全库共识别可削减代码 ≈ -4,833 行、-2 依赖；可归档/删除文档 5,674 行。
- 防误删关键项：ApiClient.push/pullChanges 位于同步主路径必须保留；sqlite3_flutter_libs 必须保留；FinanceStore 为组合根不可删。

## 用户决策

1. 批次 1-4 全部执行。
2. 批次 4 历史计划文档直接删除（不落归档目录）。
3. Web/PWA 降级为 demo（保留、不加功能、标注非维护路径）。
4. Goal（应急金目标）功能下线删除。
5. 功能缺口 ①快捷记草稿字段丢失 ③备份不完整 列入 V1.0.6 待办；②预算提醒形态 ④汇率快照同步口径 待用户拍板。

## 各批次执行记录

| 提交 | 批次 | 内容 | 变更 |
|---|---|---|---|
| `757bff9` | 批次 4 | 删 docs/superpowers/（21 文件 4,915 行）与 .superpowers/sdd/（6 文件 759 行）；ACCEPTANCE-STATUS 补历史存档标注 | 29 文件 +2/-5,676 |
| `3c4ee97` | 批次 1 | 零引用死代码：ApiClient legacy 段 25 个死转发（保留同步主路径 push/pullChanges）、Goal 全链、SharedPreferencesKeyValueStore、FirstOrNullExtension、HttpTransportKind、http_client_factory_web.dart、4 个死成员、QuickEntry/Repository 纯转发、backup 死链、后端 insights/schemas.py、idempotency.py、api.py 零调用段、langgraph 简化、Web/PWA demo 标注 | 50 文件 +93/-667，-2 依赖 |
| `c63d0c6` | 批次 2 | 删后端三个 Compatibility exports 模块（app/domain.py、app/schemas.py、app/security.py），使用方改走真实模块路径；test_architecture_boundaries 改为守门测试防回退 | 11 文件 +75/-92 |
| `30a9019` | 批次 3 | drift 裁掉 LocalAccounts/LocalTransactions/LocalSyncOperations/LocalBudgets 四张零引用表，schemaVersion 2→3，onUpgrade DROP TABLE IF EXISTS 旧表（local_metadata 无损），新增迁移测试，重新生成 g.dart | 3 文件 +239/-3,815，g.dart 3,918→346 行 |

## 净效果

- 全程 90 文件变更：+409 / -10,250，**净 -9,841 行**（其中文档 -5,674，代码净 ≈ -4,167）。
- Flutter lib：15,749 → 11,982 行（手写 11,831 → 11,636）。
- 后端 app：3,823 → 3,122 行。
- 依赖：-shared_preferences、-langgraph。
- 版本号维持 1.0.5+9 不变，仅内部瘦身，不构成发布。

## 验证证据

- Flutter：`flutter test` 400 全部通过（基线 399 + 新增 drift 迁移测试 1 条）；`flutter analyze` 无告警；删除符号全仓 grep 零残留。
- 后端：`pytest` 153 passed, 6 skipped（基线 155 → 153：删除 idempotency 自测 1 条、合并 architecture 守门断言 1 条；去 langgraph 后 6 skipped 保持）。
- 兼容模块回退守门：`test_legacy_compatibility_modules_are_removed` 常驻。

## 遗留与后续

1. V1.0.6 待办（缺口修复优先）：
   - ① 快捷记远端草稿合并丢弃 category_id/account_id/confidence/missing_facts；
   - ③ 备份只含账户+交易，恢复不触发同步感知（apps 恢复后跨端一致性）。
2. 待用户拍板：② 预算提醒是否升级为系统通知/跨设备；④ "汇率快照进入同步队列"的口径（文档改为现状 or 代码补齐实体）。
3. 质量债：7 个页面（991 行）与 `ledger_rules.dart`（多币种换算）零测试，建议列入下一轮加强项。

## 实测参考

- 瘦身后仓库体积与行数复测见提交记录；审查方法论与详细 findings 见工作区 `docs_review/` 三份报告（未入库）。
