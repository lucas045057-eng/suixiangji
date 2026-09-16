# 随想记 V1.0.2 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox syntax for tracking.

**Goal:** 在保持现有同步协议、数据隔离和 Embedded Cronet 方案不变的前提下，完成随想记 V1.0.2 的 P0 修复、自动化测试、版本更新和本地可审计交付。

**Architecture:** 先在后端和 Flutter domain/store 层建立可复现红灯，再分别修复纯规则、持久化和 UI 边界。同步沿用 LocalStateSession -> SyncQueue -> SyncCoordinator -> ApiClient/ApiTransport，只修复 A/B 场景证明的根因。余额校准作为 Account/Assets 领域写入账户 opening 字段，不生成 FinanceTransaction。

**Tech Stack:** Python 3、FastAPI、SQLAlchemy、pytest；Dart/Flutter、ChangeNotifier、flutter_test；Node.js 现有测试脚本；Git 本地临时仓库。

**Spec:** docs/superpowers/specs/2026-09-15-suixiangji-v1.0.2-design.md

## Global Constraints

- Remote baseline：69c42c99c9d2d26844a58db3c2cb68f198f96478。
- Local snapshot baseline 是本地初始化 Git 后生成的 commit，不得声称与远端 SHA 相同。
- 本轮只允许 P0 修复、自动化测试、V1.0.2 版本更新、本地验证、本地 commit 和实施报告。
- 不 push、不 force push、不创建 tag、不创建 GitHub Release、不部署、不修改生产数据库、不上传 APK。
- Flutter 版本必须是 1.0.2+5；运行时 kProductVersion = '1.0.2'、kProductBuild = 5。
- minimum supported version/build 维持现有 1.0.0 / 3。
- 保留 V1.0.1 Embedded Cronet 方案及 cronetHttpNoPlay=true。
- 本机缺少项目已声明依赖时，只安装该声明版本，不修改项目依赖版本。
- Flutter 被 Windows Developer Mode / symlink 限制阻塞时，统一记录 BLOCKED: Windows Developer Mode / symlink requirement，不得标记 PASS。
- 每个行为变更先写测试并运行确认红灯，再写最小实现并运行绿灯回归。

---

### Task 1: 统一中文金额解析并保持确认安全

Files:
- Modify: outputs/wealthmate_backend/app/quick_entry/domain.py and service.py
- Test: outputs/wealthmate_backend/tests/test_quick_entry_module.py
- Modify: outputs/wealthmate_flutter/lib/domain/finance_rules.dart
- Test: outputs/wealthmate_flutter/test/finance_rules_test.dart and test/features/quick_entry/quick_entry_store_test.dart

Interfaces: 后端 _amount_from_text(text: str) -> Decimal | None 与 Flutter FinanceRules.parseNaturalLanguage 使用同一语义；缺失金额仍必须确认，在线响应同时兼容 missing_fields 和 missing_facts。

- [ ] Step 1: 在后端写参数化红灯测试，覆盖 16块86、16元8角6分、16元8毛6、两元、两块、两块五、2块5、16.86元、32元；再测试 买了一些东西 返回空金额、缺失金额提示和 requires_confirmation 为 true。
- [ ] Step 2: 运行红灯：

    cd E:\suixiangji\outputs\wealthmate_backend
    python -m pytest tests/test_quick_entry_module.py -q

    预期中文用例因现有数字正则失败；依赖问题先检查 pyproject.toml，只安装已有声明依赖。
- [ ] Step 3: 实现后端解析器。使用中文数字表支持常用数字及 两，按 元/块/块钱、角/毛、分 解析；单尾数 2块5 解释为五角，双尾数 16块86 解释为分。无歧义金额返回 Decimal，否则返回 None；解析一次并复用结果；service 在保留 missing_fields 的同时提供 missing_facts。
- [ ] Step 4: 运行 python -m pytest tests/test_quick_entry_module.py tests/test_domain.py -q，确认聚焦和域回归通过。
- [ ] Step 5: 先在 finance_rules_test.dart 写相同输入表和不可解析 missingFacts 红灯，运行 flutter test test/finance_rules_test.dart，再实现 Flutter 同语义解析；保持 confirmationThreshold 和 canPost 门槛。symlink 阻塞时记为 BLOCKED，不改业务代码绕过。
- [ ] Step 6: 运行 Flutter Quick Entry 回归并提交：

    cd E:\suixiangji\outputs\wealthmate_flutter
    flutter test test/finance_rules_test.dart test/features/quick_entry/quick_entry_store_test.dart
    cd E:\suixiangji
    git add outputs/wealthmate_backend/app/quick_entry outputs/wealthmate_backend/tests/test_quick_entry_module.py outputs/wealthmate_flutter/lib/domain/finance_rules.dart outputs/wealthmate_flutter/test/finance_rules_test.dart outputs/wealthmate_flutter/test/features/quick_entry/quick_entry_store_test.dart
    git commit -m "fix: parse Chinese quick-entry amounts safely"

---

### Task 2: Enforce income/expense category coupling

Files:
- Modify: outputs/wealthmate_flutter/lib/features/ledger/domain/ledger_rules.dart, state/ledger_store.dart, ui/widgets/transaction_form.dart, ui/widgets/draft_editor.dart
- Test: outputs/wealthmate_flutter/test/features/ledger/ledger_store_test.dart, test/transaction_flow_test.dart, new test/transaction_form_category_test.dart
- Modify: outputs/wealthmate_backend/app/ledger/service.py
- Test: new outputs/wealthmate_backend/tests/test_category_type_coupling.py

Interfaces: 新分类候选为 active 且 type 等于 transactionType；编辑时可保留当前交易中仍匹配类型的归档分类；Ledger Store 和后端拒绝跨类型非转账分类。

- [ ] Step 1: 写 Flutter 红灯：准备 active income、active expense、archived income 分类，测试类型过滤、非法分类写入抛 ArgumentError，以及表单 expense 切到 income 后选第一个 income 分类、无候选时清空。

    expect(LedgerRules.categoriesForType(state, TransactionType.income), [state.categories['salary']]);
    expect(() => ledger.addTransaction(incomeWithExpenseCategory), throwsA(isA<ArgumentError>()));
- [ ] Step 2: 运行 flutter test test/features/ledger/ledger_store_test.dart test/transaction_flow_test.dart test/transaction_form_category_test.dart，确认新断言在旧实现上红灯；若环境阻塞，明确记录 BLOCKED。
- [ ] Step 3: 写后端红灯：通过直接 CRUD/service 和 sync acceptance 路径提交 expense + income category，断言 422；匹配类型仍成功。运行 python -m pytest tests/test_category_type_coupling.py -q。
- [ ] Step 4: 实现 LedgerRules 类型过滤；TransactionForm/DraftEditor 复用并在类型切换时重置 ID；LedgerStore 写入前验证。后端 save_transaction 在用户归属检查后比较 Category.kind 与 transaction kind，覆盖 HTTP CRUD 和 _save_tx，保持 transfer 语义。
- [ ] Step 5: 运行 python -m pytest tests/test_category_type_coupling.py tests/test_sync_acceptance.py -q 和 Flutter 聚焦回归，确认归档的合法历史分类不被清空，然后提交：

    git add outputs/wealthmate_flutter/lib/features/ledger outputs/wealthmate_flutter/lib/ui/widgets/transaction_form.dart outputs/wealthmate_flutter/lib/ui/widgets/draft_editor.dart outputs/wealthmate_flutter/test/features/ledger/ledger_store_test.dart outputs/wealthmate_flutter/test/transaction_flow_test.dart outputs/wealthmate_flutter/test/transaction_form_category_test.dart outputs/wealthmate_backend/app/ledger/service.py outputs/wealthmate_backend/tests/test_category_type_coupling.py
    git commit -m "fix: couple transaction categories to type"

---

### Task 3: 先复现再修复双设备同步，并补充同步状态

Files:
- Modify: outputs/wealthmate_flutter/lib/core/sync/sync_coordinator.dart, lib/data/sync_queue.dart, lib/state/finance_store.dart, lib/ui/dashboard_page.dart
- Modify only when red evidence requires: outputs/wealthmate_flutter/lib/core/database/local_state_session.dart
- Test: new test/core/two_device_sync_test.dart and test/dashboard_sync_status_test.dart, plus existing sync lifecycle tests

Interfaces: 两个同 owner、独立 LocalStateSession 的客户端通过内存 fake API；不改变 API payload、JWT、同步公共协议或数据库 schema。

- [ ] Step 1: 写 A/B 红灯 harness。fake server 维护四类实体、单调 server_version、client_op_id 幂等和可注入网络失败；分别测试 A push/B 旧游标 pull、B 修改/A pull、不同设备新增、离线 pending、失败重试幂等、冲突恢复、重启/重登录游标以及四类实体不回退。

    await deviceA.addTransaction(testTransactionA);
    await deviceA.sync();
    await deviceB.sync();
    expect(deviceB.state.transactions, containsA(testTransactionA.id));
    await deviceB.updateTransaction(testTransactionA.copyWith(note: 'B edit'));
    await deviceB.sync();
    await deviceA.sync();
    expect(deviceA.state.transactions[id]!.note, 'B edit');
- [ ] Step 2: 先运行 flutter test test/core/two_device_sync_test.dart test/core/sync_coordinator_test.dart test/pending_create_edit_queue_consistency_test.dart test/server_version_persistence_test.dart test/startup_cursor_recovery_test.dart，按失败位置区分队列完成竞态、pull 版本门控、游标、冲突或 harness；不得先猜根因改生产同步代码。symlink 限制记为 BLOCKED。
- [ ] Step 3: 写在途编辑红灯：fake push 使用 Completer；A push 在途时编辑同一实体，释放旧响应，断言新 client_op_id/快照仍 pending，旧 accepted 不能完成新操作。
- [ ] Step 4: 根据红灯做最小修复。确认竞态时只用被接受 client_op_id 和仍对应实体快照完成队列；确认回退时 category/budget 也使用 serverVersion 单调门控；游标只前进，失败保留 pending 和上次成功时间。保留 LocalStateSession 隔离、JWT gate、ApiClient->ApiTransport、幂等和冲突语义，不新增协议字段。
- [ ] Step 5: 写 dashboard_sync_status_test.dart 红灯并实现状态优先级：同步中显示 同步中…，失败显示 同步失败，冲突显示 有冲突待处理，pending 显示 有 N 条待同步数据，完整 push+pull 后显示 已同步。首页现有同步按钮作为 retry；只有完整成功才写 lastSyncedAt。
- [ ] Step 6: 运行 Flutter 同步聚焦回归和 python -m pytest tests/test_sync_module.py tests/test_sync_acceptance.py -q；可运行测试通过，symlink 阻塞项只记 BLOCKED；确认没有新增 API payload 或 migration/schema。提交：

    git add outputs/wealthmate_flutter/lib/core/sync outputs/wealthmate_flutter/lib/data/sync_queue.dart outputs/wealthmate_flutter/lib/state/finance_store.dart outputs/wealthmate_flutter/lib/ui/dashboard_page.dart outputs/wealthmate_flutter/test/core/two_device_sync_test.dart outputs/wealthmate_flutter/test/dashboard_sync_status_test.dart
    git commit -m "fix: make two-device sync stateful and observable"

---

### Task 4: 将余额调整改为账户余额校准

Files:
- Modify: outputs/wealthmate_flutter/lib/features/assets/domain/asset_rules.dart, state/asset_store.dart, data/assets_repository.dart
- Modify: outputs/wealthmate_flutter/lib/ui/account_detail_page.dart, ui/wealth_page.dart, ui/settings_page.dart
- Test: new outputs/wealthmate_flutter/test/account_balance_calibration_test.dart and existing asset_store_test.dart

- [ ] Step 1: 写红灯。用 CNY/外币账户和既有交易，断言校准后交易数、月收入/支出、储蓄、预算、图表不变，net worth 增加 delta；CNY 修改 openingBalance，外币只修改 openingCnyAmount，保留原币 opening、汇率、日期、来源；队列只有 account upsert 而无 transaction。
- [ ] Step 2: 运行 flutter test test/account_balance_calibration_test.dart test/features/assets/asset_store_test.dart，旧实现应因创建 transaction 或缺少校准 API 而红灯；symlink 阻塞记为 BLOCKED。
- [ ] Step 3: 实现 AssetRules.calibrateBalance(Account account, double delta) -> Account 和 AssetStore.calibrateBalance(Account account, double delta) -> Future<void>。拒绝非有限数/零，按两位小数；CNY 调整 openingBalance，外币调整 openingCnyAmount；保存复用账户 upsert/Accounts sync。AccountDetailPage 使用 余额校准/保存校准，移除 LedgerStore 依赖及调用点。
- [ ] Step 4: 运行 flutter test test/account_balance_calibration_test.dart test/features/assets/asset_store_test.dart test/v1_account_flow_test.dart，确认无 transaction operation，然后提交：

    git add outputs/wealthmate_flutter/lib/features/assets outputs/wealthmate_flutter/lib/ui/account_detail_page.dart outputs/wealthmate_flutter/lib/ui/wealth_page.dart outputs/wealthmate_flutter/lib/ui/settings_page.dart outputs/wealthmate_flutter/test/account_balance_calibration_test.dart outputs/wealthmate_flutter/test/features/assets/asset_store_test.dart
    git commit -m "fix: calibrate account balances without ledger entries"

---

### Task 5: Dashboard 查看全部跳转已有 Ledger 页

Files:
- Modify: outputs/wealthmate_flutter/lib/ui/dashboard_page.dart and lib/ui/app_shell.dart
- Test: new outputs/wealthmate_flutter/test/dashboard_navigation_test.dart and widget_test.dart

- [ ] Step 1: 写移动/桌面红灯；在两种窗口尺寸点击 查看全部，断言已有 Ledger tab 可见、选中状态同步且 Navigator 没有新账目页面。先运行 flutter test test/dashboard_navigation_test.dart test/widget_test.dart。
- [ ] Step 2: 给 DashboardPage 增加 onViewAllTransactions，AppShell 注入 () => _selectPage(1)；移动和桌面共用 _selectPage，不 push route。运行 flutter test test/dashboard_navigation_test.dart test/widget_test.dart test/overview_pages_test.dart，然后提交：

    git add outputs/wealthmate_flutter/lib/ui/dashboard_page.dart outputs/wealthmate_flutter/lib/ui/app_shell.dart outputs/wealthmate_flutter/test/dashboard_navigation_test.dart outputs/wealthmate_flutter/test/widget_test.dart
    git commit -m "fix: open ledger from dashboard recent entries"

---

### Task 6: 更新 V1.0.2 版本元数据并保留历史事实

Files:
- Modify: Flutter pubspec.yaml, lib/core/config/app_config.dart, windows/runner/Runner.rc, README.md, FLUTTER-DELIVERY.md
- Modify: backend app/config.py, docker-compose.yml, .env.example, app/main.py, pyproject.toml, README.md and current version tests
- Test: new outputs/wealthmate_flutter/test/v1.0.2_version_test.dart and backend test assertions

- [ ] Step 1: 写红灯并运行。Flutter 断言 kProductVersion == 1.0.2、kProductBuild == 5；backend /app/version 断言 latest 1.0.2/5、minimum 1.0.0/3。现有值应使新断言失败。
- [ ] Step 2: 更新当前有效值：pubspec 1.0.2+5、runtime 1.0.2/5、latest 1.0.2/5、minimum 1.0.0/3。更新当前交付文档和 Windows fallback，不批量改写历史 V1.0.0/V1.0.1 报告；保留 cronet_http 和 cronetHttpNoPlay=true。
- [ ] Step 3: 运行 backend app/health version tests、Flutter version/update tests 和 rg -n "cronetHttpNoPlay=true|cronet_http" outputs/wealthmate_flutter FLUTTER-DELIVERY.md；提交：

    git add outputs/wealthmate_flutter outputs/wealthmate_backend/app/config.py outputs/wealthmate_backend/docker-compose.yml outputs/wealthmate_backend/.env.example outputs/wealthmate_backend/app/main.py outputs/wealthmate_backend/pyproject.toml outputs/wealthmate_backend/README.md FLUTTER-DELIVERY.md
    git commit -m "chore: update app metadata for v1.0.2"

---

### Task 7: 全量验证、实施报告和最终本地提交

Files:
- Create: docs/V1.0.2-IMPLEMENTATION-REPORT.md
- Modify: ACCEPTANCE-STATUS.md only to append current V1.0.2 status

- [ ] Step 1: 运行全部可运行验证并捕获新鲜输出：

    cd E:\suixiangji
    npm test
    cd outputs\wealthmate_backend
    python -m pytest tests -q
    cd ..\wealthmate_flutter
    flutter analyze
    flutter test

    另行运行每个任务的聚焦命令；Python 只安装 pyproject.toml 已声明依赖。Flutter symlink 阻塞统一记录 BLOCKED，不能标 PASS。
- [ ] Step 2: 做安全边界检查：

    cd E:\suixiangji
    git diff --check
    git status --short --branch
    git log --oneline --decorate -n 12
    git tag --list
    rg -n "1\\.0\\.2|1\\.0\\.2\\+5|latest_build|minimum_supported|cronetHttpNoPlay=true" outputs FLUTTER-DELIVERY.md docs README.md

    确认没有 push、tag、Release、部署、生产 DB 或 APK 操作，且没有 migration/schema 变化。
- [ ] Step 3: 报告必须包含：

    Remote baseline: 69c42c99c9d2d26844a58db3c2cb68f198f96478
    Local snapshot baseline: a8b385e2429b2aea3a21e8e2c6a6576c9f7fda47
    V1.0.2 final local HEAD: use the SHA printed by git rev-parse HEAD after the report commit
    Branch: local-v1.0.2

    逐项记录 root cause、文件、测试命令和 PASS/FAIL/BLOCKED/NOT VERIFIED；同步专章覆盖 A/B、pending 保留、幂等、冲突、重启游标和四类实体；同时记录 Android build、migration/schema、生产操作和最终 git status。
- [ ] Step 4: 审查完整 diff，写报告，提交后输出最终 SHA：

    git add docs/V1.0.2-IMPLEMENTATION-REPORT.md ACCEPTANCE-STATUS.md
    git commit -m "docs: record v1.0.2 implementation evidence"
    git status --short --branch
    git rev-parse HEAD

不得更新任何远端 ref。
