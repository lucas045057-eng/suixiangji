# 随想记 V1.0.2 设计说明

## 目标

在不改变现有同步协议、数据隔离和 V1.0.1 Embedded Cronet 网络方案的前提下，完成 V1.0.2 的 P0 正确性与数据安全修复：金额解析、收支分类约束、双设备同步、余额校准、最近账目跳转，以及版本号更新。

## 范围与不可变约束

- Remote baseline：`69c42c99c9d2d26844a58db3c2cb68f198f96478`。
- 本地 Git 仅为临时开发历史；不得把本地初始化历史当成 GitHub 原仓库历史。
- 本轮只允许 P0 修复、自动化测试、V1.0.2 版本更新、本地验证、本地 commit 和实施报告。
- 不 push、不 force push、不创建 tag、不创建 GitHub Release、不部署、不修改生产数据库、不上传 APK。
- Flutter 版本必须是 `1.0.2+5`；运行时 `kProductVersion = '1.0.2'`、`kProductBuild = 5`。
- minimum supported version/build 维持现有 `1.0.0` / `3`。
- 保留 V1.0.1 Embedded Cronet 方案及 `cronetHttpNoPlay=true`。
- 不新增依赖版本；本机缺少已经声明的依赖时只安装现有声明依赖。
- Windows Developer Mode / symlink 导致的 Flutter 无法执行必须记录为 `BLOCKED: Windows Developer Mode / symlink requirement`，不能标记 PASS。

## 现状与边界

仓库由 GitHub `main.zip` 恢复到 `E:\suixiangji`，本地快照已单独初始化 Git。Flutter 客户端位于 `outputs/wealthmate_flutter`，FastAPI 后端位于 `outputs/wealthmate_backend`。现有同步链路为 `LocalStateSession -> SyncQueue -> SyncCoordinator -> ApiClient/ApiTransport`，服务端以每用户 `sync_version`、实体 `server_version` 和 `client_op_id` 实现增量同步及幂等。

金额解析目前只识别阿拉伯数字，Flutter 与后端规则不一致；分类表单只按 active 过滤，未按交易类型过滤；同步已有生命周期、冲突、版本游标和队列测试，但缺少稳定的同账号 A/B 设备端到端场景；余额调整通过伪造 `FinanceTransaction` 实现；Dashboard 的“查看全部”回调为空。

## 设计决策

### 1. 金额解析

在后端 `quick_entry/domain.py` 增加纯函数式的中文金额解析器，并在 Flutter `finance_rules.dart` 增加同语义的本地解析器。解析顺序为：

1. 先匹配带单位的中文金额片段；
2. 识别整数、小数、元/块/块钱、角/毛、分及常用中文数字（含“两”）；
3. 按“元 + 角/毛 + 分”组合金额；
4. 仅有“块五”“2块5”时将尾数解释为五角；
5. 无法无歧义解析时返回空值，不猜测金额。

必须支持：`16块86`、`16元8角6分`、`16元8毛6`、`两元`、`两块`、`两块五`、`2块5`、`16.86元`、`32元`。金额统一保留两位小数；解析失败进入 `missing_facts`/缺失金额提示，不能绕过确认或自动记账。

后端继续兼容现有 `missing_fields` 响应，同时在 Quick Entry 服务输出 `missing_facts`，保证 Flutter 在线端不会丢失缺失信息；规则解析和模型解析都继续强制草稿确认。

### 2. 收支分类类型耦合

客户端的分类候选集合定义为 `active && category.type == transactionType`。编辑已有交易时，若历史分类仍与交易类型匹配，即使已归档也暂时保留为编辑候选，避免合法历史数据被清空；用户切换交易类型时，若当前分类不属于新类型，则重置为新类型第一个 active 分类，没有候选则置空。

Ledger Store/规则层在提交前拒绝非转账交易使用另一类型分类；后端 `ledger.service.save_transaction` 在所有写入路径（HTTP CRUD 和同步 `_save_tx`）执行同一校验，返回明确的 422/冲突错误。转账仍按现有无分类语义处理。客户端不因历史合法但已归档的分类而破坏旧交易。

### 3. 双设备同步

不重写现有协议。先使用现有真实 `SyncCoordinator`、`LocalStateSession`、`SyncQueue` 和 fake `ApiTransport` 建立同账号 A/B 的可重复场景，并逐条记录失败点：

1. A 创建并 push，B 用旧 `serverVersion` pull 得到 A；
2. B 修改并 push，A 再 pull 得到 B；
3. A/B 同时新增不同实体；
4. 离线操作进入待同步队列，网络失败后仍保留；
5. 重试成功后不重复写入；
6. 同一 `client_op_id` 幂等，冲突保留本地修改并可恢复；
7. 重启、重新登录及游标持久化后继续从正确位置同步；
8. 交易、账户、分类、预算四类实体均无回退。

只根据红灯位置修复。重点保护两种竞态：push 在途时同一实体再次编辑不能被旧响应误完成；pull 合并不能用较旧实体覆盖较新本地/远端状态。队列完成和实体版本更新必须只作用于仍对应被接受的操作快照；分类、预算也按 `server_version` 使用与交易/账户一致的版本门控。同步游标只前进不后退，pull 成功后才记录同步成功时间。

FinanceStore 在网络调用前设置 `isSyncing`，状态按“同步中、失败、冲突、待同步、已同步/最近时间、未配置或离线”显示。重试复用现有首页同步按钮。只有服务端 push 接受且 pull 成功后才显示成功；失败显示原因并保留 pending；冲突显示待处理而不伪装成功。状态优先复用现有 `SyncState`，必要的最后同步时间持久化为向后兼容的状态元数据，不改变 API/数据库协议。

### 4. 余额校准

“余额校准”表示把当前账户在总资产 CNY 展示口径下的计算余额修正到用户输入的目标余额；输入 delta 为目标余额减当前余额。它不是一笔收入或支出，因此不创建 `FinanceTransaction`，不改变账目数量、月收入、月支出、储蓄率、预算和图表数据，只改变资产净值。

优先在 `AssetRules` 增加纯校准规则，并由 `AssetsRepository/AssetStore` 保存账户 upsert：

- CNY 账户：调整 `openingBalance`；
- 外币账户：调整 `openingCnyAmount`（CNY 展示口径），保留原币 opening、汇率、日期和来源元数据；若服务端重新计算外币 opening CNY，仍按现有账户 API 的字段协议传输；
- 金额按两位小数，拒绝非有限数和零变化。

AccountDetailPage 改为调用 AssetStore 的校准方法，按钮文案为“保存校准”，不再注入 LedgerStore。账户更新走既有 Accounts 同步队列，因此可离线、可重试、可幂等。除非现有测试证明必要，不新增数据库字段、迁移或同步协议字段。

### 5. Dashboard 查看全部

AppShell 注入 `onViewAllTransactions` 回调，内部直接选择已有 tab index `1`（Ledger），Dashboard 的“查看全部”调用该回调。移动端 NavigationBar 与桌面端导航共用 `_selectPage`，不 push 新路由、不创建重复账目页。增加移动端和桌面端 widget 测试，验证回调后现有 Ledger 页面可见且导航选中状态一致。

### 6. 版本更新

更新当前生效配置和文档中的 V1.0.2 版本值：Flutter pubspec、运行时常量、后端 app/config、compose/.env 示例、API app version、后端包版本、当前发布/交付文档和更新检查测试。latest 为 `1.0.2` / `5`，minimum supported 保持 `1.0.0` / `3`。历史版本报告中的历史事实不做批量改写。Android 继续由 Flutter versionName/versionCode 生成，并保留 Embedded Cronet 开关。

## 测试策略

每个 P0 均遵守 TDD：先增加最小失败测试，单独运行确认是预期红灯，再写最小实现，单测/组件测试转绿后再运行相关回归。同步测试必须先证明复现场景能捕获缺陷，再修根因；禁止只通过放宽断言或增加等待时间解决。

后端：运行金额解析、分类类型校验及同步服务测试；若 `python-jose` 已在 `pyproject.toml` 声明，只安装已有依赖，不修改依赖声明。Flutter：优先执行可运行的纯 Dart/domain 测试；Flutter analyze/test 若仍触发 Windows symlink 限制，统一标记 `BLOCKED: Windows Developer Mode / symlink requirement`，不把阻塞结果写成 PASS。Node/Web 回归按现有 package scripts 执行。

## 不在本次实现中的内容

- 任何 GitHub push、force push、tag、Release 或部署。
- 生产数据库、线上数据、正式账号和测试用户 APK。
- 与 P0 无关的 UI 重构、架构重写、依赖升级和历史文档事实改写。
- 未由红灯证据证明需要的同步协议、数据库 schema 或迁移变更。

## 验收标准

- 金额例子及失败安全行为均有自动化证据。
- 分类候选和服务端写入都阻止明显跨类型分类，编辑历史合法分类不回退。
- A/B 双设备场景覆盖创建、修改、并发新增、离线失败保留、重试幂等、冲突恢复、重启游标和四类实体。
- 余额校准不新增 FinanceTransaction，只有账户资产/净值按规则变化，并能进入账户同步队列。
- “查看全部”进入现有 Ledger 页，移动/桌面导航一致。
- 版本值准确，minimum supported 不变，Cronet 参数仍保留。
- 最终报告包含 Remote baseline、本地快照基线、V1.0.2 final local HEAD、测试命令与逐项 PASS/BLOCKED/FAIL、迁移/schema、生产操作和 git status。
