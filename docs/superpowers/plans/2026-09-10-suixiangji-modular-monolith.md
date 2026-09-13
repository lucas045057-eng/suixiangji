# 随想记模块化单体重构 Implementation Plan

> For agentic workers: REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (- [ ]) syntax for tracking.

Goal: 在不改变产品行为、API Contract、数据库 Schema 和同步协议的前提下，将随想记整理为按业务职责组织的模块化单体。

Architecture: 采用渐进式职责抽取。Flutter 先建立唯一串行 LocalStateSession，再按 Auth、Ledger、Assets、Budget、QuickEntry、Insights 拆分 Store/Repository/Domain；Backend 按相同业务边界拆 Router/Service/Schema/Domain，但本轮保留 app/models.py 作为唯一 SQLAlchemy 模型定义文件。Sync 最后只抽取边界并接入唯一 Coordinator，保留现有算法实现与协议语义。

Tech Stack: Flutter 3.47.2 / Dart 3.13.2、ChangeNotifier、Drift/SQLite、FastAPI、SQLAlchemy、PostgreSQL/SQLite、Python unittest、Node test。

Spec: docs/superpowers/specs/2026-09-10-suixiangji-modular-monolith-design.md

## Global Constraints

- 以职责边界和依赖方向为拆分依据，不为凑目录机械搬移文件。
- 第一轮不拆 SQLAlchemy app/models.py；它继续作为唯一的 ORM 模型定义与 metadata 注册入口。
- LocalStateSession 是 Flutter 本地聚合状态的唯一串行写入口；禁止 Feature Store、Repository、同步恢复和 demo 恢复旁路写入。
- Sync 阶段只抽取边界、接口和唯一 Coordinator，不重新设计、优化或改变现有同步算法、排序规则、冲突策略和协议字段。
- 保持 API URL、HTTP method、请求字段、响应字段和状态码。
- 保持 Transaction.id、client_op_id、serverVersion、User.sync_version、tombstone、幂等、cursor、冲突恢复、依赖排序和用户隔离语义。
- 不修改数据库 Schema，不生成或修改 Alembic migration，不删除表、不清空数据、不重建 PostgreSQL volume。
- 不新增家庭账本、股票/基金、实时行情、导入、社区、新预算、新 AI、新统计指标或新同步协议。
- 只使用本地测试数据库或独立本地 Compose；不连接生产数据库，不执行 git push、远程分支、PR 或服务器部署。
- 每个 Phase 必须在进入下一 Phase 前完成完整回归、diff review、阶段报告和本地 commit。

## Baseline and shared phase gate

Phase 0 开始时记录以下基线命令及结果；之后每个 Phase 都执行同一组完整回归命令，另外执行该 Phase 的专项测试。任何失败都必须停在当前 Phase，记录失败与是否为基线已有问题。

~~~powershell
Set-Location E:\codex\suixiangji
npm test
Set-Location outputs\wealthmate_backend
python -m compileall -q app tests
python -m unittest discover -s tests -v
Set-Location ..\wealthmate_flutter
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test
Set-Location ..\..
git status --short --branch
git diff --check
git diff --stat
~~~

每个 Phase 的报告必须列出：变更文件、专项测试结果、上面完整回归结果、git diff --stat、是否修改 API/Schema/同步字段、剩余风险。报告完成并提交后，才允许开始下一个 Phase。

## File and responsibility map

第一轮实际创建的 Flutter 公共设施和业务文件：

- outputs/wealthmate_flutter/lib/core/database/local_state_session.dart：唯一串行聚合状态写入口。
- outputs/wealthmate_flutter/lib/core/network/api_transport.dart：HTTP 请求、认证头、错误映射和 JSON 基础传输，不包含业务 endpoint。
- outputs/wealthmate_flutter/lib/core/sync/sync_coordinator.dart：Phase 7 才创建，承接现有 push/pull 算法，不改算法。
- outputs/wealthmate_flutter/lib/features/<module>/data/：模块 Repository 与 RemoteDataSource。
- outputs/wealthmate_flutter/lib/features/<module>/domain/：模块纯业务规则和输入/输出类型；持久化兼容 DTO 在首轮不破坏旧导出。
- outputs/wealthmate_flutter/lib/features/<module>/state/：模块 ChangeNotifier Store。
- outputs/wealthmate_flutter/lib/app/bootstrap.dart：组合公共基础设施和各模块 Store。

第一轮实际创建的 Backend 业务文件：

- outputs/wealthmate_backend/app/core/dependencies.py、errors.py、security.py：公共依赖、错误和认证技术能力。
- outputs/wealthmate_backend/app/auth/、ledger/、assets/、budget/、quick_entry/、insights/：Router、Service、Schema、Domain；本轮不创建模块级 SQLAlchemy models.py。
- outputs/wealthmate_backend/app/sync/：Phase 7 的同步 Router、Service、ordering 边界；不改变同步算法。
- outputs/wealthmate_backend/app/api.py：迁移期薄聚合/兼容入口，不再承载大段业务实现。
- outputs/wealthmate_backend/app/models.py：首轮保持现状和唯一 ORM 定义职责。

---

### Task 1: Phase 0 — 建立本地状态与网络基础边界

Files:
- Create: outputs/wealthmate_flutter/lib/core/database/local_state_session.dart
- Create: outputs/wealthmate_flutter/lib/core/network/api_transport.dart
- Create: outputs/wealthmate_flutter/test/core/local_state_session_test.dart
- Modify: outputs/wealthmate_flutter/lib/data/finance_repository.dart
- Modify: outputs/wealthmate_flutter/lib/data/api_client.dart
- Modify: outputs/wealthmate_flutter/lib/main.dart
- Test: outputs/wealthmate_flutter/test/data_repository_test.dart、outputs/wealthmate_flutter/test/api_client_test.dart

Interfaces:
- LocalStateSession(LocalRepository local, SyncQueue queue) owns the cached FinanceState and queue.
- Future<FinanceState?> load() loads the owner-bound aggregate once and returns the current snapshot.
- Future<FinanceState> write(FinanceState Function(FinanceState current) mutation, {Iterable<SyncOperation> appendOperations = const []}) serializes state mutation, queue append, state persistence, and queue persistence in FIFO order.
- Future<FinanceState> replaceState(FinanceState next) serializes an authoritative/local replacement without changing queue contents.
- Future<void> mutateQueue(void Function(SyncQueue queue) mutation) serializes queue-only changes.
- Future<List<SyncOperation>> pendingOperations() returns a snapshot after prior writes have drained.
- ApiTransport.requestMap(String method, String path, {Map<String, Object?>? body, bool includeAuth = true}) owns HTTP and status-to-ApiFailure mapping; it never knows a business entity.

- [x] Step 1: Record the baseline before touching implementation.

Run the shared baseline commands from E:\codex\suixiangji. Save the command summary in the Phase 0 report; do not attribute pre-existing failures to this task.

- [x] Step 2: Write the failing serialization tests.

Add tests that issue two writes without awaiting the first and prove the second mutation observes the first; add a queue/state atomicity test:

~~~dart
test('serializes concurrent aggregate writes without losing updates', () async {
  final session = LocalStateSession(
    local: LocalRepository(MemoryKeyValueStore()),
    queue: SyncQueue(),
  );

  final first = session.write((state) => state.copyWith(currentMonth: '2026-09'));
  final second = session.write((state) => state.copyWith(defaultAccountId: 'a-2'));
  await Future.wait([first, second]);

  final saved = await session.load();
  expect(saved?.currentMonth, '2026-09');
  expect(saved?.defaultAccountId, 'a-2');
});

test('persists a state mutation and its queued operation in one serial turn', () async {
  final session = LocalStateSession(
    local: LocalRepository(MemoryKeyValueStore()),
    queue: SyncQueue(),
  );
  final operation = SyncOperation(
    clientOpId: 'op-1', entity: 'transactions', entityId: 'tx-1',
    type: SyncOperationType.upsert, payload: const {'id': 'tx-1'},
    createdAt: '2026-09-10T00:00:00Z',
  );

  await session.write(
    (state) => state.copyWith(currentMonth: '2026-09'),
    appendOperations: [operation],
  );

  expect((await session.load())?.currentMonth, '2026-09');
  expect((await session.pendingOperations()).single.clientOpId, 'op-1');
});
~~~

- [x] Step 3: Run the focused tests and verify they fail for the missing interface.

Run:

~~~powershell
Set-Location E:\codex\suixiangji\outputs\wealthmate_flutter
flutter test test\core\local_state_session_test.dart
~~~

Expected: compilation failure because LocalStateSession is not implemented.

- [x] Step 4: Implement the smallest FIFO session and adapt existing writes.

Use a private future tail; every state and queue write must await the previous tail and update the session-owned snapshot. The core shape is:

~~~dart
typedef StateMutation = FinanceState Function(FinanceState current);

class LocalStateSession {
  LocalStateSession({required this.local, required this.queue});

  final LocalRepository local;
  final SyncQueue queue;
  Future<void> _tail = Future<void>.value();
  FinanceState? _state;

  Future<T> _serial<T>(Future<T> Function() action) {
    final run = _tail.then((_) => action());
    _tail = run.then<void>((_) {}, onError: (_, __) {});
    return run;
  }

  Future<FinanceState?> load() => _serial(() async {
        _state ??= await local.load();
        queue.replace(await local.loadQueue());
        return _state;
      });

  Future<FinanceState> write(
    StateMutation mutation, {
    Iterable<SyncOperation> appendOperations = const [],
  }) => _serial(() async {
        _state ??= await local.load() ?? const FinanceState();
        final next = mutation(_state!);
        for (final operation in appendOperations) queue.enqueue(operation);
        await local.save(next);
        await local.saveQueue(queue);
        _state = next;
        return next;
      });
}
~~~

The final implementation must also provide replaceState, mutateQueue, and pendingOperations using the same _serial tail. Change FinanceRepository.applyLocal, applyLocalAccount, applyLocalCategory, softDelete, pushPending, pullChanges, owner reset, demo restore, and every existing local.save/saveQueue call to use the session. Do not alter the contents or order of sync payloads.

Extract only HTTP mechanics from ApiClient into ApiTransport; keep ApiClient as a compatibility façade with its current public methods and token behavior. main.dart constructs one LocalStateSession and passes it through the repository graph.

- [x] Step 5: Run focused and full Phase 0 verification.

Run the focused Flutter tests, then the complete shared phase gate. Inspect git diff --check and confirm no direct aggregate LocalRepository.save remains outside LocalStateSession.

- [x] Step 6: Report and commit Phase 0.

Report changed files, serialization proof, baseline/full regression results, and the exact diff summary. Commit:

~~~powershell
git add outputs\wealthmate_flutter docs\superpowers
git commit -m "refactor(core): serialize local state writes"
~~~

---

### Task 2: Phase 1 — 抽取 Auth 职责

Files:
- Create: outputs/wealthmate_flutter/lib/features/auth/data/auth_repository.dart
- Create: outputs/wealthmate_flutter/lib/features/auth/data/auth_remote_data_source.dart
- Create: outputs/wealthmate_flutter/lib/features/auth/state/auth_store.dart
- Create: outputs/wealthmate_flutter/lib/features/auth/domain/auth_session.dart
- Create: outputs/wealthmate_flutter/test/features/auth/auth_store_test.dart
- Create: outputs/wealthmate_backend/app/auth/router.py
- Create: outputs/wealthmate_backend/app/auth/service.py
- Create: outputs/wealthmate_backend/app/auth/schemas.py
- Create: outputs/wealthmate_backend/app/core/dependencies.py
- Create: outputs/wealthmate_backend/app/core/security.py
- Modify: outputs/wealthmate_flutter/lib/main.dart, outputs/wealthmate_flutter/lib/ui/app_shell.dart, outputs/wealthmate_flutter/lib/ui/login_page.dart, outputs/wealthmate_flutter/lib/ui/profile_settings_page.dart, outputs/wealthmate_flutter/lib/ui/settings_page.dart
- Modify: outputs/wealthmate_backend/app/api.py, outputs/wealthmate_backend/app/main.py, outputs/wealthmate_backend/app/security.py
- Test: outputs/wealthmate_flutter/test/api_client_test.dart, outputs/wealthmate_backend/tests/test_api.py

Interfaces:
- AuthRemoteDataSource.login(String username, String password) -> Future<Map<String, Object?>> delegates to the current /auth/login contract.
- AuthRepository.login(String username, String password) -> Future<UserProfile> saves the token through the existing token store and returns the verified profile.
- AuthRepository.fetchProfile() -> Future<UserProfile> calls /auth/me and records the verified user ID.
- AuthRepository.updateProfile({String? displayName, String? username, List<QuickMemory>? quickMemories}) -> Future<UserProfile> and changePassword(String currentPassword, String newPassword) -> Future<UserProfile> preserve current behavior.
- AuthStore exposes UserProfile? profile, bool isAuthenticated, Future<bool> login(String username, String password), Future<bool> loadProfile(), Future<bool> updateProfile({String? displayName, String? username}), Future<bool> changePassword(String currentPassword, String nextPassword), Future<void> logout(), and void clearSession().
- app.auth.service exposes login(db, payload), get_current_user(db, token), update_profile(db, user, payload), and change_password(db, user, payload); routers only validate and delegate.

- [x] Step 1: Add Auth Store tests around current behavior.

Cover login token persistence, profile verification, profile update, password-change token rotation, logout, and 401 session clearing. Keep current test fakes and assert existing response fields. Do not add register, invitation, or any other endpoint absent from the current code.

- [x] Step 2: Run the focused Auth tests and verify the new Store/Repository surface is initially absent.

~~~powershell
Set-Location E:\codex\suixiangji\outputs\wealthmate_flutter
flutter test test\features\auth\auth_store_test.dart test\api_client_test.dart
~~~

Expected: compilation failure until the module classes are added.

- [x] Step 3: Extract Flutter Auth without moving unrelated state.

Move token restoration, login, profile, password and auth-expiry handling out of FinanceStore into AuthRepository and AuthStore. The Store may request owner binding through LocalStateSession, but it must not modify transactions, accounts, budgets, metrics, or queue entries. Keep lib/ui/login_page.dart as a compatibility export if the concrete widget moves under features/auth/ui/.

Use a narrow Store surface:

~~~dart
abstract interface class AuthStorePort {
  UserProfile? get profile;
  bool get isAuthenticated;
  Future<bool> login(String username, String password);
  Future<bool> loadProfile();
  Future<bool> updateProfile({String? displayName, String? username});
  Future<bool> changePassword(String currentPassword, String nextPassword);
  Future<void> logout();
  void clearSession();
}
~~~

- [x] Step 4: Extract Backend Auth Router/Service while keeping app/models.py untouched.

Move only the existing /auth/login, /auth/me, /auth/password route behavior. auth/service.py imports User from app.models; it does not create auth/models.py. app/core/security.py may re-export the existing password/JWT functions, while app/security.py remains a compatibility export. app/api.py includes auth.router and re-exports _user compatibility symbols without duplicating routes.

Each route must remain a thin delegation:

~~~python
@router.post('/auth/login')
def login(payload: LoginIn, db: Session = Depends(get_db)) -> dict:
    return auth_service.login(db, payload)
~~~

- [x] Step 5: Migrate app bootstrap and auth-related pages.

main.dart constructs AuthRepository/AuthStore; AppShell receives AuthStore for lifecycle and receives feature stores separately where needed. LoginPage talks only to AuthStore or an Auth-specific controller, never directly to ApiClient. Profile/settings pages use AuthStore for profile and password operations.

- [x] Step 6: Run Auth-focused tests, the full phase gate, review diff, report and commit.

Confirm that no Auth route changed and no SQLAlchemy model file changed. Commit:

~~~powershell
git add outputs\wealthmate_flutter outputs\wealthmate_backend
git commit -m "refactor(auth): extract authentication module"
~~~

Do not begin Phase 2 until this report is complete.

---

### Task 3: Phase 2 — 抽取 Ledger 职责

Files:
- Create: outputs/wealthmate_flutter/lib/features/ledger/data/ledger_repository.dart
- Create: outputs/wealthmate_flutter/lib/features/ledger/data/ledger_remote_data_source.dart
- Create: outputs/wealthmate_flutter/lib/features/ledger/domain/ledger_rules.dart
- Create: outputs/wealthmate_flutter/lib/features/ledger/state/ledger_store.dart
- Create: outputs/wealthmate_flutter/test/features/ledger/ledger_store_test.dart
- Create: outputs/wealthmate_backend/app/ledger/router.py
- Create: outputs/wealthmate_backend/app/ledger/service.py
- Create: outputs/wealthmate_backend/app/ledger/schemas.py
- Create: outputs/wealthmate_backend/app/ledger/domain.py
- Modify: outputs/wealthmate_flutter/lib/ui/ledger_page.dart, outputs/wealthmate_flutter/lib/ui/transaction_detail_page.dart, outputs/wealthmate_flutter/lib/ui/category_management_page.dart, outputs/wealthmate_flutter/lib/ui/dashboard_page.dart, outputs/wealthmate_flutter/lib/ui/widgets/transaction_form.dart
- Modify: outputs/wealthmate_flutter/lib/state/finance_store.dart, outputs/wealthmate_flutter/lib/data/finance_repository.dart, outputs/wealthmate_flutter/lib/data/api_client.dart
- Modify: outputs/wealthmate_backend/app/api.py, outputs/wealthmate_backend/app/main.py
- Test: outputs/wealthmate_flutter/test/finance_store_test.dart, outputs/wealthmate_flutter/test/data_repository_test.dart, outputs/wealthmate_flutter/test/transaction_flow_test.dart, outputs/wealthmate_backend/tests/test_api.py, outputs/wealthmate_backend/tests/test_domain.py

Interfaces:
- LedgerRemoteDataSource.fetchCategories() -> Future<List<Category>>, createCategory({required String name, required TransactionType type}) -> Future<Category>, updateCategory(String categoryId, {required String name, required bool active}) -> Future<Category>, and fetchTransactions() -> Future<List<FinanceTransaction>> preserve current payload parsing.
- LedgerRepository.applyTransaction(FinanceState Function(FinanceState), {SyncOperation operation}) -> Future<FinanceState> always writes through LocalStateSession.
- LedgerStore exposes List<FinanceTransaction> transactions, List<Category> activeCategories, Future<void> addTransaction(FinanceTransaction), Future<void> updateTransaction(FinanceTransaction), Future<void> deleteTransaction(String), Future<void> addCategory({required String name, required TransactionType type}), Future<void> updateCategory(String categoryId, {required String name, required bool active}), and Future<void> archiveCategory(String).
- ledger.service exposes list_categories, create_category, update_category, archive_category, list_transactions, create_transaction, update_transaction, and delete_transaction; all accept Session and User and return current API response shapes.

- [x] Step 1: Write Ledger Store tests for local CRUD and queue semantics.

Cover transaction create/edit/delete, category CRUD/archive, stable transaction IDs, new edit operation IDs, and the fact that every write reaches LocalStateSession. Reuse the existing sync regression cases instead of changing their expectations.

- [x] Step 2: Run focused Ledger tests and verify the new boundary is absent.

~~~powershell
Set-Location E:\codex\suixiangji\outputs\wealthmate_flutter
flutter test test\features\ledger\ledger_store_test.dart test\transaction_flow_test.dart test\data_repository_test.dart
Set-Location E:\codex\suixiangji\outputs\wealthmate_backend
python -m unittest tests.test_api tests.test_domain -v
~~~

- [x] Step 3: Extract pure Ledger rules before wiring the Store.

Move only transaction/category decisions from FinanceRules and FinanceRepository into features/ledger/domain/ledger_rules.dart. Keep money conversion and aggregate metrics in their current domain owner until the Assets/Insights phases. The rules accept DTOs/values, not Widgets, HTTP requests, or database Sessions.

- [x] Step 4: Implement Ledger Repository/Store through the session.

For every create/edit/delete, build the same SyncOperation payload and call LocalStateSession.write; do not call LocalRepository.save, repository.save, or queue.enqueue directly from a page. Keep FinanceRepository methods as delegating compatibility methods until all consumers move.

The Repository mutation shape is:

~~~dart
Future<FinanceState> saveTransaction(FinanceTransaction transaction) {
  return session.write(
    (state) => state.copyWith(
      transactions: [
        ...state.transactions.where((item) => item.id != transaction.id),
        transaction,
      ],
    ),
    appendOperations: [operationForTransaction(transaction)],
  );
}
~~~

- [x] Step 5: Extract Backend Ledger routes and services without touching models.

Move Category/Transaction response mappers, normalization, validation, and persistence into the Ledger module. When account existence is checked, import Account from unchanged app.models; do not move or duplicate its ORM class. Keep exact field aliases (date/occurred_on, type/kind, original amount/currency fields) and status codes.

The Router must only pass validated input to the Service:

~~~python
@router.post('/transactions')
def create_transaction(payload: TransactionIn, db: Session = Depends(get_db), user: User = Depends(get_current_user)) -> dict:
    return ledger_service.create_transaction(db, user, payload)
~~~

- [x] Step 6: Migrate Ledger pages and run the full Phase gate.

LedgerPage, TransactionDetailPage, CategoryManagementPage, and transaction form depend on LedgerStore. DashboardPage receives Ledger as a read-only input plus the later Assets/Budget/Insights stores; it must not regain a universal Store. Review for direct HTTP/database access, report the full diff and commit:

~~~powershell
git add outputs\wealthmate_flutter outputs\wealthmate_backend
git commit -m "refactor(ledger): extract ledger module"
~~~

---

### Task 4: Phase 3 — 抽取 Assets 职责

Files:
- Create: outputs/wealthmate_flutter/lib/features/assets/data/assets_repository.dart
- Create: outputs/wealthmate_flutter/lib/features/assets/data/assets_remote_data_source.dart
- Create: outputs/wealthmate_flutter/lib/features/assets/domain/asset_rules.dart
- Create: outputs/wealthmate_flutter/lib/features/assets/state/asset_store.dart
- Create: outputs/wealthmate_flutter/test/features/assets/asset_store_test.dart
- Create: outputs/wealthmate_backend/app/assets/router.py
- Create: outputs/wealthmate_backend/app/assets/service.py
- Create: outputs/wealthmate_backend/app/assets/schemas.py
- Create: outputs/wealthmate_backend/app/assets/domain.py
- Modify: outputs/wealthmate_flutter/lib/ui/wealth_page.dart, outputs/wealthmate_flutter/lib/ui/exchange_rates_page.dart, outputs/wealthmate_flutter/lib/ui/account_detail_page.dart, outputs/wealthmate_flutter/lib/ui/app_shell.dart
- Modify: outputs/wealthmate_flutter/lib/state/finance_store.dart, outputs/wealthmate_flutter/lib/data/finance_repository.dart, outputs/wealthmate_flutter/lib/domain/finance_rules.dart
- Modify: outputs/wealthmate_backend/app/api.py, outputs/wealthmate_backend/app/main.py, outputs/wealthmate_backend/app/scheduler.py
- Test: outputs/wealthmate_flutter/test/finance_rules_test.dart, outputs/wealthmate_flutter/test/finance_store_test.dart, outputs/wealthmate_backend/tests/test_api.py, outputs/wealthmate_backend/tests/test_domain.py

Interfaces:
- AssetsRemoteDataSource.updateAccount(Account), fetchExchangeRate(String base, {String quote = 'CNY'}), saveExchangeRate(Map<String, Object?>), and fetchWealth() preserve existing endpoints.
- AssetsRepository.saveAccount(Account account) -> Future<FinanceState> persists the account mutation through LocalStateSession.
- AssetStore exposes List<Account> accounts, List<ExchangeRateSnapshot> exchangeRates, Future<void> addAccount({required String name, required AccountType type, String currency = 'CNY', double openingBalance = 0, AccountKind accountKind = AccountKind.other}), Future<void> updateAccount(Account), Future<void> setDefaultAccount(String), Future<void> saveManualExchangeRate({required String baseCurrency, required double rate, required String rateDate, required String source}), Future<void> refreshExchangeRate(String), and read-only net-worth selectors.
- assets.service exposes account CRUD, exchange_rate, save_exchange_rate, and wealth operations; it imports ORM classes from app.models and leaves model definitions unchanged.

- [x] Step 1: Add tests for account validation, default account, currency snapshots and net worth.

Assert CNY and foreign-currency conversion behavior, preservation of rate/source/date snapshots, account name uniqueness, asset/liability handling, and no mutation of transactions.

- [x] Step 2: Run focused Assets tests and verify failure before implementation.

~~~powershell
Set-Location E:\codex\suixiangji\outputs\wealthmate_flutter
flutter test test\features\assets\asset_store_test.dart test\finance_rules_test.dart
Set-Location E:\codex\suixiangji\outputs\wealthmate_backend
python -m unittest tests.test_api tests.test_domain -v
~~~

- [x] Step 3: Extract Assets rules and Repository.

Move account and exchange-rate state changes into Assets; use LocalStateSession.write for all aggregate updates. Keep LocalRepository as the low-level serializer only. Reuse existing FinanceRules calculations until the Insights phase; do not change rounding or missing-rate semantics.

The Store delegates writes and exposes read-only selectors:

~~~dart
Future<void> updateAccount(Account account) async {
  _state = await repository.saveAccount(account);
  notifyListeners();
}

List<Account> get activeAccounts =>
    _state.accounts.where((item) => item.deletedAt == null).toList(growable: false);
~~~

- [x] Step 4: Extract Backend Assets routes/services.

Move account response mapping, duplicate-name validation, exchange-rate lookup/snapshot, and wealth aggregation into app/assets. Keep Account, ExchangeRate, and NetWorthSnapshot in app.models; no schema or migration change. Keep scheduler imports working through service-level functions, not Router internals.

The Service owns validation and persistence while the Router remains declarative:

~~~python
def update_account(db: Session, user: User, account_id: str, payload: AccountIn) -> dict:
    values = payload.model_dump()
    values['id'] = account_id
    user.sync_version += 1
    row = save_account(db, user, values, server_version=user.sync_version)
    db.commit()
    return account_json(row)
~~~

- [x] Step 5: Migrate Wealth, Exchange Rate and Account pages.

Pages use AssetStore; account edits and exchange-rate writes go through the Store. Update AppShell composition only to inject stores; do not create an aggregate FinanceStore replacement.

- [x] Step 6: Run full regression, diff review, report and commit Phase 3.

~~~powershell
git add outputs\wealthmate_flutter outputs\wealthmate_backend
git commit -m "refactor(assets): extract asset module"
~~~

---

### Task 5: Phase 4 — 抽取 Budget 职责

Files:
- Create: outputs/wealthmate_flutter/lib/features/budget/data/budget_repository.dart
- Create: outputs/wealthmate_flutter/lib/features/budget/data/budget_remote_data_source.dart
- Create: outputs/wealthmate_flutter/lib/features/budget/domain/budget_rules.dart
- Create: outputs/wealthmate_flutter/lib/features/budget/state/budget_store.dart
- Create: outputs/wealthmate_flutter/test/features/budget/budget_store_test.dart
- Create: outputs/wealthmate_backend/app/budget/router.py
- Create: outputs/wealthmate_backend/app/budget/service.py
- Create: outputs/wealthmate_backend/app/budget/schemas.py
- Modify: outputs/wealthmate_flutter/lib/ui/budgets_page.dart, outputs/wealthmate_flutter/lib/ui/dashboard_page.dart, outputs/wealthmate_flutter/lib/state/finance_store.dart
- Modify: outputs/wealthmate_backend/app/api.py, outputs/wealthmate_backend/app/main.py, outputs/wealthmate_backend/app/scheduler.py
- Test: outputs/wealthmate_flutter/test/finance_store_test.dart, outputs/wealthmate_flutter/test/overview_pages_test.dart, outputs/wealthmate_backend/tests/test_api.py

Interfaces:
- BudgetStore exposes List<Budget> budgets, List<BudgetAlert> alerts, Future<void> upsertBudget({String? id, required String month, required String categoryId, required double limit}), Future<List<BudgetAlert>> checkBudgetAlerts(), and void clearAlerts().
- budget_rules.dart exposes pure BudgetAlertLevel? levelForRatio(double ratio) and BudgetProgress progressFor(Budget budget, double spent) with current 80%/100%/over semantics.
- budget.service exposes list/create/update/delete operations with existing month filtering and response shapes.

- [x] Step 1: Add pure threshold and Store tests.

Cover healthy, warning, exhausted, and over states; month/category filtering; local persistence; queue identity; alert deduplication. Preserve existing auxiliary alert key storage behavior, but route aggregate state writes through LocalStateSession.

- [x] Step 2: Run focused Budget tests before implementation.

~~~powershell
Set-Location E:\codex\suixiangji\outputs\wealthmate_flutter
flutter test test\features\budget\budget_store_test.dart test\overview_pages_test.dart
Set-Location E:\codex\suixiangji\outputs\wealthmate_backend
python -m unittest tests.test_api -v
~~~

- [x] Step 3: Extract Budget Store/Repository and deterministic rules.

Move budget mutation and alert calculation from FinanceStore/FinanceRules to the Budget module. All FinanceState updates use LocalStateSession.write; no page gets access to LocalRepository or SyncQueue.

Keep threshold logic pure and explicit:

~~~dart
BudgetAlertLevel? levelForRatio(double ratio) {
  if (ratio > 1) return BudgetAlertLevel.over;
  if (ratio >= 1) return BudgetAlertLevel.exhausted;
  if (ratio >= .8) return BudgetAlertLevel.warning;
  return null;
}
~~~

- [x] Step 4: Extract Backend Budget Router/Service.

Move budget serialization, category ownership checks, month query and CRUD persistence into app/budget. Import Budget from unchanged app.models; preserve status codes and soft-delete behavior.

The endpoint remains a direct Service call with existing dependency injection:

~~~python
@router.get('/budgets')
def list_budgets(month: str | None = Query(default=None, pattern=r'^\d{4}-\d{2}$'), db: Session = Depends(get_db), user: User = Depends(get_current_user)) -> dict:
    return budget_service.list_budgets(db, user, month)
~~~

- [x] Step 5: Migrate Budget page and overview composition.

BudgetsPage depends on BudgetStore; DashboardPage consumes its read-only alert/progress view. Keep page navigation and copy unchanged.

- [x] Step 6: Run the full phase gate, diff review, report and commit.

~~~powershell
git add outputs\wealthmate_flutter outputs\wealthmate_backend
git commit -m "refactor(budget): extract budget module"
~~~

---

### Task 6: Phase 5 — 抽取 QuickEntry 职责

Files:
- Create: outputs/wealthmate_flutter/lib/features/quick_entry/data/quick_entry_repository.dart
- Create: outputs/wealthmate_flutter/lib/features/quick_entry/data/quick_entry_remote_data_source.dart
- Create: outputs/wealthmate_flutter/lib/features/quick_entry/domain/quick_entry_rules.dart
- Create: outputs/wealthmate_flutter/lib/features/quick_entry/state/quick_entry_store.dart
- Create: outputs/wealthmate_flutter/test/features/quick_entry/quick_entry_store_test.dart
- Create: outputs/wealthmate_backend/app/quick_entry/router.py
- Create: outputs/wealthmate_backend/app/quick_entry/service.py
- Create: outputs/wealthmate_backend/app/quick_entry/schemas.py
- Modify: outputs/wealthmate_flutter/lib/ui/dashboard_page.dart, outputs/wealthmate_flutter/lib/ui/widgets/draft_confirmation_card.dart, outputs/wealthmate_flutter/lib/ui/widgets/draft_editor.dart, outputs/wealthmate_flutter/lib/state/finance_store.dart
- Modify: outputs/wealthmate_backend/app/api.py, outputs/wealthmate_backend/app/main.py, outputs/wealthmate_backend/app/services/agent.py, outputs/wealthmate_backend/app/services/agent_workflow.py
- Test: outputs/wealthmate_flutter/test/finance_rules_test.dart, outputs/wealthmate_flutter/test/transaction_flow_test.dart, outputs/wealthmate_backend/tests/test_domain.py, outputs/wealthmate_backend/tests/test_api.py

Interfaces:
- QuickEntryStore exposes AgentDraft? draft, Future<void> createDraft(String text, {DateTime? now}), void updateDraft(AgentDraft draft), Future<bool> confirmDraft(AgentDraft draft, String? sourceText, Future<void> Function(FinanceTransaction) postTransaction), Future<void> rememberDraftChoice(String sourceText, AgentDraft draft), and void clearDraft().
- QuickEntryRepository.createDraft(String text, FinanceState context) -> Future<AgentDraft> uses local deterministic completion first and optional remote /agent/draft second.
- QuickEntryRepository.transactionFromDraft(AgentDraft draft) -> FinanceTransaction creates the same transaction payload currently used by confirmation.
- quick_entry.service.make_draft(db, user, payload) -> dict only returns a reviewable structured draft; it never inserts a Transaction.

- [x] Step 1: Write tests proving draft-only behavior.

Cover local parsing, remote fallback, missing facts, confidence threshold, editable draft fields, QuickMemory persistence through LocalStateSession, and the rule that confirm delegates exactly one real transaction mutation to LedgerStore.

- [x] Step 2: Run focused QuickEntry tests before implementation.

~~~powershell
Set-Location E:\codex\suixiangji\outputs\wealthmate_flutter
flutter test test\features\quick_entry\quick_entry_store_test.dart test\finance_rules_test.dart
Set-Location E:\codex\suixiangji\outputs\wealthmate_backend
python -m unittest tests.test_domain tests.test_api -v
~~~

- [x] Step 3: Extract QuickEntry local rules and Store.

Move draft state, source text, memory lookup, remote draft merge, and confirmation orchestration out of FinanceStore. The confirmation callback must be the Ledger boundary; QuickEntry cannot call LocalRepository, SyncQueue, or a backend transaction endpoint directly.

The confirmation boundary is explicit:

~~~dart
Future<bool> confirmDraft(
  AgentDraft draft,
  String? sourceText,
  Future<void> Function(FinanceTransaction) postTransaction,
) async {
  if (!QuickEntryRules.canPost(draft)) return false;
  await postTransaction(repository.transactionFromDraft(draft));
  if (sourceText != null) await repository.rememberChoice(sourceText, draft);
  clearDraft();
  return true;
}
~~~

- [x] Step 4: Extract Backend QuickEntry Router/Service.

Move only the existing /agent/draft endpoint and agent adapter invocation. Keep AgentLog handling and configuration behavior intact; no new model, AI provider, or auto-post endpoint.

The service returns a draft and does not call any Transaction persistence function:

~~~python
async def make_draft(db: Session, user: User, payload: DraftIn) -> dict:
    draft = await agent.make_draft(payload.text, user=user)
    log_agent_result(db, user, draft)
    return draft
~~~

- [x] Step 5: Migrate dashboard draft widgets.

Dashboard receives QuickEntryStore for draft operations and LedgerStore for the final transaction callback. Visual layout, confirmation wording, and modify-before-posting behavior remain unchanged.

- [x] Step 6: Run full regression, inspect the no-auto-post invariant, report and commit.

~~~powershell
git add outputs\wealthmate_flutter outputs\wealthmate_backend
git commit -m "refactor(quick-entry): extract quick entry module"
~~~

---

### Task 7: Phase 6 — 抽取 Insights 职责

Files:
- Create: outputs/wealthmate_flutter/lib/features/insights/data/insights_repository.dart
- Create: outputs/wealthmate_flutter/lib/features/insights/data/insights_remote_data_source.dart
- Create: outputs/wealthmate_flutter/lib/features/insights/domain/insight_rules.dart
- Create: outputs/wealthmate_flutter/lib/features/insights/state/insights_store.dart
- Create: outputs/wealthmate_flutter/test/features/insights/insights_store_test.dart
- Create: outputs/wealthmate_backend/app/insights/router.py
- Create: outputs/wealthmate_backend/app/insights/service.py
- Create: outputs/wealthmate_backend/app/insights/schemas.py
- Create: outputs/wealthmate_backend/app/insights/domain.py
- Modify: outputs/wealthmate_flutter/lib/ui/dashboard_page.dart, outputs/wealthmate_flutter/lib/ui/stats_page.dart, outputs/wealthmate_flutter/lib/state/finance_store.dart, outputs/wealthmate_flutter/lib/domain/finance_rules.dart
- Modify: outputs/wealthmate_backend/app/api.py, outputs/wealthmate_backend/app/main.py, outputs/wealthmate_backend/app/scheduler.py, outputs/wealthmate_backend/app/services/agent.py
- Test: outputs/wealthmate_flutter/test/finance_rules_test.dart, outputs/wealthmate_flutter/test/overview_pages_test.dart, outputs/wealthmate_flutter/test/finance_store_test.dart, outputs/wealthmate_backend/tests/test_api.py, outputs/wealthmate_backend/tests/test_domain.py

Interfaces:
- InsightsStore exposes FinanceMetrics get metrics, String get monthKey, Future<void> refresh({String? month}), Future<void> generateMonthlyReport(), and read-only trend/category/account series.
- insight_rules.dart exposes pure deriveMetrics(FinanceState state, String monthKey) -> FinanceMetrics, periodExpenseSeries(FinanceState state, DateTimeRange range) -> List<PeriodPoint>, expenseByCategory(FinanceState state, DateTimeRange range) -> Map<String, double>, and expenseByAccount(FinanceState state, DateTimeRange range) -> Map<String, double> with current calculation results.
- insights.service exposes stats and monthly-report operations; deterministic numbers are calculated before optional AI text generation.

- [x] Step 1: Add pure metric/report tests and Store tests.

Cover day/week/month zero-filled series, category/account aggregations, savings rate, budget progress composition, report fallback when AI is unavailable, and cache invalidation after a Ledger/Assets mutation.

- [x] Step 2: Run focused Insights tests before implementation.

~~~powershell
Set-Location E:\codex\suixiangji\outputs\wealthmate_flutter
flutter test test\features\insights\insights_store_test.dart test\finance_rules_test.dart test\overview_pages_test.dart
Set-Location E:\codex\suixiangji\outputs\wealthmate_backend
python -m unittest tests.test_api tests.test_domain -v
~~~

- [x] Step 3: Extract pure calculations and Insights Store.

Move metrics cache, period aggregations and report state out of FinanceStore. The Store consumes read-only snapshots from Ledger, Assets and Budget; it may not mutate their entities. Any report cache/aggregate snapshot write goes through LocalStateSession.

The Store receives read-only inputs and keeps the calculation pure:

~~~dart
class InsightsStore extends ChangeNotifier {
  InsightsStore({required this.snapshot, required this.repository});

  final ValueListenable<FinanceState> snapshot;
  final InsightsRepository repository;
  FinanceMetrics get metrics => InsightRules.deriveMetrics(snapshot.value, monthKey);
  String get monthKey => snapshot.value.currentMonth;
}
~~~

- [x] Step 4: Extract Backend Insights Router/Service.

Move /stats and /reports/monthly/{month} route bodies, response conversion and deterministic report numbers into app/insights. Keep scheduler.py calling services rather than Router functions. Do not change AI provider configuration or report response fields.

The Service computes programmatic numbers before requesting optional text:

~~~python
def monthly_report(db: Session, user: User, month: str, force: bool = False) -> dict:
    metrics = calculate_monthly_metrics(db, user, month)
    return report_service.build_report(db, user, month, metrics, force=force)
~~~

- [x] Step 5: Migrate Stats and Dashboard views.

StatsPage depends on InsightsStore; Dashboard receives a read-only metrics projection. Remove all new-page imports of FinanceStore, retaining only the thin compatibility façade for old tests during cleanup.

- [x] Step 6: Run full regression, diff review, report and commit.

~~~powershell
git add outputs\wealthmate_flutter outputs\wealthmate_backend
git commit -m "refactor(insights): extract insights module"
~~~

---

### Task 8: Phase 7 — 只抽取 Sync 边界与 Coordinator

Files:
- Create: outputs/wealthmate_flutter/lib/core/sync/sync_coordinator.dart
- Create: outputs/wealthmate_flutter/test/core/sync_coordinator_test.dart
- Create: outputs/wealthmate_backend/app/sync/router.py
- Create: outputs/wealthmate_backend/app/sync/service.py
- Create: outputs/wealthmate_backend/app/sync/schemas.py
- Create: outputs/wealthmate_backend/app/sync/conflict.py
- Create: outputs/wealthmate_backend/app/sync/ordering.py
- Modify: outputs/wealthmate_flutter/lib/data/finance_repository.dart, outputs/wealthmate_flutter/lib/data/sync_queue.dart, outputs/wealthmate_flutter/lib/core/database/local_state_session.dart, outputs/wealthmate_flutter/lib/app/bootstrap.dart
- Modify: outputs/wealthmate_backend/app/api.py, outputs/wealthmate_backend/app/main.py
- Test: outputs/wealthmate_flutter/test/auth_sync_gate_test.dart, outputs/wealthmate_flutter/test/cb01_conflict_resolution_red_test.dart, outputs/wealthmate_flutter/test/cb05_delete_operation_identity_red_test.dart, outputs/wealthmate_flutter/test/dc03_synced_edit_semantics_red_test.dart, outputs/wealthmate_flutter/test/offline_owner_recovery_test.dart, outputs/wealthmate_flutter/test/pending_create_edit_queue_consistency_test.dart, outputs/wealthmate_flutter/test/server_version_persistence_test.dart, outputs/wealthmate_flutter/test/startup_cursor_recovery_test.dart, outputs/wealthmate_backend/tests/test_sync_acceptance.py, outputs/wealthmate_backend/tests/test_server_seed_version_invariant_red.py, outputs/wealthmate_backend/tests/test_sc08_payload_contract_red.py

Interfaces:
- SyncCoordinator.sync(FinanceState state) -> Future<FinanceState> is the only public sync lifecycle entry. It reads/writes through LocalStateSession and delegates the existing push/pull behavior unchanged.
- SyncCoordinator.pushPending(FinanceState state) and pullChanges(FinanceState state) preserve current FinanceRepository semantics and error messages.
- app.sync.ordering.order_operations(operations) is a pure extraction of current stable dependency ordering; app.sync.service.push and pull preserve existing response ordering and transaction boundaries.

- [x] Step 1: Freeze current Sync behavior with characterization tests.

Run all existing Sync tests and add focused assertions for exact client_op_id, server-version handling, strict cursor, tombstone retention, conflict-specific queue removal, dependency ordering, user isolation and failed-batch rollback. Do not change expected values.

- [x] Step 2: Run the Sync-focused suite before extraction.

~~~powershell
Set-Location E:\codex\suixiangji\outputs\wealthmate_flutter
flutter test test\auth_sync_gate_test.dart test\cb01_conflict_resolution_red_test.dart test\cb05_delete_operation_identity_red_test.dart test\dc03_synced_edit_semantics_red_test.dart test\offline_owner_recovery_test.dart test\pending_create_edit_queue_consistency_test.dart test\server_version_persistence_test.dart test\startup_cursor_recovery_test.dart
Set-Location E:\codex\suixiangji\outputs\wealthmate_backend
python -m unittest discover -s tests -v
~~~

- [x] Step 3: Extract Flutter boundaries without changing algorithm code.

Move the current queue coordination and push/pull/recovery blocks into SyncCoordinator with behavior-preserving extraction. FinanceRepository becomes a compatibility façade that forwards to the Coordinator. All persistence still goes through LocalStateSession; no second queue, cursor, conflict resolver or operation identity generator is introduced.

The Coordinator is an orchestration boundary, not a new algorithm:

~~~dart
class SyncCoordinator {
  SyncCoordinator({required this.session, required this.api});

  final LocalStateSession session;
  final ApiClient api;

  Future<FinanceState> sync(FinanceState state) async {
    final pushed = await pushPending(state);
    return pullChanges(pushed);
  }
}
~~~

- [x] Step 4: Extract Backend Sync Router/Service boundaries.

Move only route definitions, request schemas, _order_sync_operations, conflict helpers and existing push/pull service calls into app/sync. Preserve operation ordering, response ordering, commit/rollback behavior and all existing field names. app/models.py remains untouched.

The ordering extraction must preserve the current pure function result:

~~~python
def order_operations(operations: list) -> list:
    priority = {'accounts': 0, 'categories': 0, 'transactions': 1, 'budgets': 1}
    indexed_upserts = [
        (index, operation)
        for index, operation in enumerate(operations)
        if operation.type == 'upsert' and operation.entity in priority
    ]
    ordered_upserts = iter(
        operation
        for _, operation in sorted(
            indexed_upserts,
            key=lambda item: (priority[item[1].entity], item[0]),
        )
    )
    return [
        next(ordered_upserts)
        if operation.type == 'upsert' and operation.entity in priority
        else operation
        for operation in operations
    ]
~~~

- [x] Step 5: Verify protocol equivalence by diffing characterization outputs.

Run Flutter and Backend Sync suites, compare accepted/conflict/pull payloads for the same fixtures, and inspect that no algorithmic change appears in diff. If any behavior change is discovered, stop Phase 7 and restore the extraction to a pure boundary move.

- [x] Step 6: Run the complete phase gate, report and commit.

~~~powershell
git add outputs\wealthmate_flutter outputs\wealthmate_backend
git commit -m "refactor(sync): isolate sync coordinator"
~~~

The commit must not include generated databases, Flutter build output, or dependency caches.

---

### Task 9: Final consolidation, architecture checks and documentation

Files:
- Create: outputs/wealthmate_flutter/test/architecture/module_boundaries_test.dart
- Create: outputs/wealthmate_backend/tests/test_architecture_boundaries.py
- Modify: outputs/wealthmate_flutter/lib/state/finance_store.dart
- Modify: outputs/wealthmate_flutter/lib/data/finance_repository.dart, outputs/wealthmate_flutter/lib/data/api_client.dart
- Modify: outputs/wealthmate_backend/app/api.py, outputs/wealthmate_backend/app/domain.py, outputs/wealthmate_backend/app/schemas.py, outputs/wealthmate_backend/app/security.py
- Modify: docs/architecture.md, docs/sync-architecture.md, README.md, FLUTTER-DELIVERY.md, outputs/wealthmate_backend/README.md
- Test: complete repository test suites

Interfaces:
- FinanceStore remains only a deprecated compatibility façade with composition/lifecycle forwarding; it contains no new feature business rules, direct HTTP calls, direct DB writes, or sync algorithm.
- FinanceRepository remains only a compatibility façade over Feature Repositories, LocalStateSession, and SyncCoordinator.
- ApiClient remains only a compatibility façade over ApiTransport and feature DataSources.
- app/api.py, app/schemas.py, app/domain.py, and app/security.py contain only compatibility exports/aggregation, not duplicate business implementations.

- [x] Step 1: Add architecture boundary checks.

The Flutter check parses/import-scans source files and fails if a feature UI imports data/drift_database.dart, data/local_repository.dart, core/network/api_transport.dart, or constructs http.Client; it also fails if a new feature Store calls LocalRepository.save or SyncQueue.enqueue directly. The Backend check fails if a Router calls db.commit() or contains domain calculations, and verifies that app.models is the only ORM model definition module.

Example Python assertion for the model constraint:

~~~python
from pathlib import Path

backend = Path(__file__).parents[1] / 'app'
model_files = [path for path in backend.rglob('models.py')]
assert model_files == [backend / 'models.py']
~~~

- [x] Step 2: Remove only duplicated implementation, not compatibility exports.

Use rg to confirm business logic exists in one module only. Keep old imports working for tests and downstream code, but make the old files delegate or re-export. Do not delete user data, database files, volumes, or unrelated uncommitted files.

- [x] Step 3: Update architecture documentation with the actual final tree.

Document the final file locations, LocalStateSession write rule, thin compatibility façade policy, unchanged API/Schema, unchanged Sync protocol, and deferred SQLAlchemy model split. Update README commands only where paths changed.

- [x] Step 4: Run the full final verification.

Run the shared phase gate, the architecture tests, git diff --check, and a final rg scan for direct page-to-HTTP/database access, duplicate Sync implementations, and module-level SQLAlchemy model files.

- [x] Step 5: Produce the final local report and commit.

The report must include current branch, HEAD SHA, dirty status, final directory tree, modules extracted, final FinanceStore and api.py roles, Sync protocol result, database/migration result, every test result, remaining technical debt, and next steps. It must explicitly state:

~~~text
Remote push: NO
PR created: NO
Server deployment: NO
Production DB touched: NO
~~~

Commit:

~~~powershell
git add outputs docs README.md FLUTTER-DELIVERY.md
git commit -m "refactor: complete modular monolith boundaries"
~~~

## Execution handoff

Implement this plan in order. Use a fresh review checkpoint after every Phase report; do not batch multiple Phases into one change. The next execution session must read both this plan and the spec, then use superpowers:subagent-driven-development or superpowers:executing-plans as required by the header.
