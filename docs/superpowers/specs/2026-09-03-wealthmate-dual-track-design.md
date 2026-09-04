# WealthMate 双轨交付设计

## 目标

基于 `product-handoff.md` 交付个人自用、单用户的“记账 + 极简财富管理”产品：一份可直接打开的本地优先 Web/PWA 演示版，以及一份面向 Android + Windows 的 Flutter 客户端源码。交接文档中的产品决策、85% Agent 确认门、转账不计入收支、应急金口径和“不会/待确认”纪律均为约束，不把缺失的后端或构建工具链伪装成已交付。

## 现状与边界

当前工作区没有交接文档所说的 `backend/` 和 `app/` 源码；可复用资产是上一轮生成的本地 Web WealthMate MVP。因而本次交付分成两条独立产物：

1. `outputs/wealthmate/`：整理后的可运行 Web/PWA，保留本地 localStorage 演示数据和核心闭环。
2. `outputs/wealthmate_flutter/`：从零补齐的 Flutter 客户端源代码与测试；通过 API 适配器接入既有后端契约，默认提供本地演示数据和离线队列，真实后端地址、JWT 和推送由配置注入。

本次不交付 APK、Windows 安装包、真实推送结果或 Compose/PostgreSQL 验收结论，因为当前环境没有 Flutter SDK、Android SDK、Visual Studio C++ 工作负载、Docker Desktop/WSL 或 Bark/ntfy 配置。Web/PWA 也不声称替代 Android/Windows 客户端。

明确不做：多人协作、多租户、支付通道、银行/支付宝自动连接、复杂投资组合、行情接入、多语言、真实外部 LLM、周度报告统计口径扩展和 XLSX 导出。

## 体验设计

### Web/PWA

保持上一轮已确认的深墨蓝工作台、奶油白内容区、青绿色财富强调色和紫色 Agent 卡片。桌面端使用左侧导航与主内容区；移动端使用底部导航，所有表单以抽屉/模态呈现。首页先呈现“本月收入、支出、储蓄率、净资产、预算进度、近期账目”，再提供快捷记账和待确认草稿。

### Flutter Android/Windows

Android 使用五 Tab：首页、账本、统计、财富、我的；Windows 使用左侧导航、中间列表、右侧详情。两端共享领域模型、API 客户端、同步队列、表单校验和状态派生逻辑，差异只留在布局层。手工记账和自然语言草稿均使用同一确认门：置信度 `>= 0.85` 显示“可确认入账”，低于 `0.85` 只能显示“待确认”并要求用户补全/修正。

## 架构

### 共享领域模型

客户端本地模型包括 `Account`、`Category`、`Transaction`、`Budget`、`Goal`、`Report`、`SyncQueueItem` 和 `SyncState`。账户区分 `asset` 与 `liability` 并支持期初余额；交易类型为 `income`、`expense`、`transfer`。所有实体保留服务端 ID、`clientOpId`、`serverVersion`、`updatedAt` 和 `deletedAt` 字段，以支持软删除与增量同步。

余额规则固定为：资产账户收入增加、支出减少；负债账户支出增加、收入/还款减少；转账只改变转出/转入账户，不进入收入或支出汇总。净资产 = 资产余额之和 − 负债余额之和；储蓄率 = (收入 − 支出) / 收入。应急金只统计用户勾选的流动资产账户，负债账户被选中时显示校验错误。

### 数据流

UI → `FinanceStore` → 本地 repository → 同步队列 → `ApiClient`。写操作先落本地并生成 `clientOpId`，网络可用时 push，随后 pull 以 `server_version` 合并。相同 `clientOpId` 重推不产生重复记录；服务端版本过期时保留冲突记录并提示用户选择。自然语言输入只走 `AgentDraftService`，永远不绕过确认卡直接写入交易表。

### 后端适配

Flutter 的 `ApiClient` 只依赖交接文档中既有资源：auth、accounts、categories、transactions、stats、wealth、budgets、agent、reports、sync。请求基址和 token 通过环境/设置注入；缺失配置时客户端进入本地演示模式，并在“我的”页明确写出“离线演示/待配置”，不假装已同步。

## 错误与安全处理

- 登录配置缺失、网络失败、服务端 401/409/422 都转为用户可理解的状态，不展示原始堆栈。
- 备注原文不写入 Agent 日志；本地导出由用户主动触发。
- 默认支付账户缺失时，自然语言草稿必须显示“请选择支付账户”，不能自行补充。
- 不确定字段统一显示“不会/待确认”；不调用未配置的外部 LLM。
- 删除交易采用软删除并进入同步队列，界面提供撤销；不会使用不可恢复的物理删除。

## 交付文件

- Web：`outputs/wealthmate/index.html`、`styles.css`、`app.js`、`manifest.webmanifest`、`service-worker.js`。
- Flutter：`outputs/wealthmate_flutter/pubspec.yaml`、`lib/` 下的模型、repository、API、同步、store、主题与页面、`test/` 下的单元测试，以及 Android/Windows 平台配置说明。
- 文档：本规格、实施计划和一份验收状态清单，明确哪些检查已实际执行，哪些因工具链缺失为 BLOCKED。

## 验证标准

### Web/PWA

1. 首次打开可看到收入、支出、储蓄率、净资产和近期账目。
2. 新增支出后，账目、月度支出、账户余额、预算进度同步更新。
3. “今天中午外卖 32 元，支付宝”生成餐饮/支出/32 元草稿，必须经确认后入账。
4. 预算达到 80% 和 100% 显示对应状态。
5. 财富页展示资产、负债、净资产和应急金进度。
6. 刷新后数据保留，可恢复演示数据并导出 JSON。
7. 移动宽度下无横向滚动，导航和表单可用。

### Flutter 源码

1. `dart format --output=none --set-exit-if-changed .` 和 `flutter analyze`（若工具链存在）无错误。
2. 领域测试覆盖余额、转账、预算阈值、自然语言草稿、85% 确认门、默认账户缺失、同步去重和过期冲突。
3. `flutter test`（若工具链存在）通过。
4. `flutter build apk --debug`、`flutter build windows --debug` 只在相应工具链存在时执行；缺失时状态为 BLOCKED，并记录原因。

## 取舍

推荐把可见的 Web 交付作为当天可评估入口，把 Flutter 源码作为面向目标平台的正式客户端基线。二者共享同一业务规则但不强行共享 UI 代码，既能立即交付可操作产品，也能保留 Android/Windows 的正确扩展边界。真实后端联调和安装包构建作为工具链就绪后的验收步骤，不在本机不可验证时提前宣称。
