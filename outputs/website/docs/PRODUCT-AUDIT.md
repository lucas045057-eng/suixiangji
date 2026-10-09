# 产品真实性审计

审计时间：2026-10-09（北京时间）。依据真实代码与 GitHub API，不以需求中的功能描述作为已实现证据。

## 仓库基线

- 远程：https://github.com/lucas045057-eng/suixiangji
- 初始工作树：干净；初始分支：main。
- 更新后的 origin/main 与开发起点：`6a87b0ef694ae87ad5e8780839f5d568692ea09a`。
- 官网分支：`feat/official-website`，从当前 origin/main 创建，未从 Tag 创建。
- Tags：`modular-monolith-v1`、`sync-v1.0-rc1`、`v1.0.0`、`v1.0.1`、`v1.0.2`、`v1.0.3`、`v1.0.4`。
- 已读：根 README.md、WEB-DELIVERY.md、FLUTTER-DELIVERY.md、ACCEPTANCE-STATUS.md、docs/release/ 下全部七份文档；遍历 outputs/。
- 未发现 AGENTS.md。原项目没有独立成熟官网框架；根 npm test 是七项 Web/PWA 测试。采用零运行时依赖的 HTML/CSS/ES modules。
- 图片盘点：仅发现应用图标，没有可用真实产品截图。首屏依据 Flutter dashboard_page.dart、app_shell.dart、预算与统计页面建立 CSS 示意；演示数据明确标注。截图路径集中在 siteConfig.screenshots，加载失败保留 CSS 示意。

## 当前发布

GitHub API `/releases` 与 `/releases/latest` 为发布来源；当前最新非 draft、非 prerelease：

- Release：[`v1.0.4`](https://github.com/lucas045057-eng/suixiangji/releases/tag/v1.0.4)，发布于 2026-09-19。
- APK：`v1.0.4-build7-regression.apk`，版本 `1.0.4`、build `7`。
- 大小：`80,143,658` bytes，即 `80.14 MB`（十进制；约 `76.43 MiB`）。
- 真实资产 URL：https://github.com/lucas045057-eng/suixiangji/releases/download/v1.0.4/v1.0.4-build7-regression.apk
- 完整下载成功，文件大小及 SHA-256 与 Release asset digest、v1.0.4-signing-evidence.md 一致：`93acc15e02095d06480ab6806a3d564de55bfab93e3d6ef11587257a75f2f3bd`。
- Windows：Release 列表中没有 exe/msix/zip；Git 跟踪文件中没有公开安装包。根历史交付文档记录过 ATL 构建阻塞；outputs/ACCEPTANCE-STATUS.md 另有旧 V1.2 局域网构建/ZIP 名称记录，但未提供现版本公开资产，也未确认真实设备安装与同步。不能仅凭旧文档中的文件名启用当前正式下载。客户端源码与宽屏布局存在，官网 `enabled=false`，不生成 URL。

发布说明与早期 v1.0.4-device-acceptance.md 仍有 NOT VERIFIED；当前 main 的 v1.0.4-test-evidence.md 后续追加了 2026-09-20 真机和生产双向同步通过的证据。官网采用最新仓库证据描述多端能力；本轮没有重新执行客户端真机验收、数据库或生产同步测试，不能把历史结果视为本轮 PASS。

## 七项 AI 能力

| 能力 | 状态 | 代码证据与限度 | 官网处理 |
|---|---|---|---|
| 固定支出发现 | PLANNED | 全量检索 lib/ 与 app/ 无重复支出识别、周期规则生成；scheduler.py 为预算/月报调度，不能视为固定支出发现 | 正在打磨；场景演示 |
| 账本清理 | PLANNED | 没有废弃分类/重复账户/空预算诊断；LocalRepository pendingAccountCleanup 是注销后本机数据清理，与产品账本清理无关 | 正在打磨；场景演示 |
| 退款自动配对 | PLANNED | models.dart TransactionType 仅 expense/income/transfer；Backend ledger/models 无 refund 关系或配对规则 | 正在打磨；场景演示 |
| AA / 垫付实际支出 | PLANNED | 无共享支出、应收款关系与归还款关联计算；普通转账不能等同 AA 净支出识别 | 正在打磨；场景演示 |
| 账本自动归因 | PARTIAL | Backend insights/service.py `stats` / `monthly_report`、insights/domain.py 与 Flutter insight_rules.dart 有分类/账户/周期统计、月报与可选模型叙述；没有具体交易变化因果归因，“晚餐外卖更多”所需细节未进入月报结构化输入 | 已有统计/月报；明确具体消费归因仍在打磨 |
| 自适应分类 | PARTIAL | Flutter category_management_page.dart 支持自定义管理；finance_rules.dart `_resolveCategory` 可用名称/关键词/已确认 QuickMemory；无自动分类合并、停用或使用频度调整算法 | 已有自定义及确认记忆；自动整理正在打磨 |
| 个人称呼记忆 | PARTIAL | finance_rules.dart `quickMemoryKey`、`_resolveCategory`、`_resolveAccount`；quick_entry_repository.dart `rememberChoice`；quick_entry_store.dart `confirmDraft` 形成确认→持久化→复用闭环。QuickMemory 只存 key/categoryId/accountId，未存“面馆”地点解释；本地金额解析要求单位或货币符号，裸 `老地方 28` 不满足完整草稿 | 明示当前仅确认后的分类/账户记忆；裸金额和地点语义为方向示例 |

状态定义：IMPLEMENTED = 需求中的完整能力存在；PARTIAL = 已有相关可用基础、但不足以支持完整承诺；PLANNED = 未找到该能力实现。所有七项都有中心配置状态，页面不将 PARTIAL/PLANNED 写成现已自动完成。

## 边界

只增加 outputs/website/。既有 Web/PWA、Flutter、Backend、数据库、同步、Tag、Release、域名、DNS、证书和生产配置均未修改。未 push、未合并、未部署。canonical 预设为需求中指定的 `https://suixiangji.icu/`，部署前应再次确认最终公开入口；本轮没有修改该域名。
