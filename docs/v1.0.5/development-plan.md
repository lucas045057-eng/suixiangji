# V1.0.5 Implementation Plan

> 执行技能：superpowers:executing-plans；本会话按用户连续开发授权自行执行，逐任务记录，不额外设置规划审批停点。

**Goal:** 在既有系统闭环实现全部有效需求，保留双向验收证据。
**Architecture:** 统一发生日期/金额过滤与金融快照，扩展现有Feature Store、API和同步队列。增量数据库迁移保护用户ID和历史数据。
**Tech Stack:** Flutter、Drift/SQLite、FastAPI、SQLAlchemy/Alembic、PostgreSQL。
**Spec:** `docs/v1.0.5/architecture-plan.md`与`requirements-consolidation.md`。

## Global Constraints

- 分支feat/v1.0.5-requirements-closure；不直接main、不修改生产、不发布Release。
- 只增强Auth/Ledger/Assets/Budget/QuickEntry/Insights/Backup/Sync；业务UI不直接写库。
- 先失败验收测试再产品代码；逐包同步测试；缺环境NOT VERIFIED。
- 原需求原文不改、错位分析新增校正列；UR-015仍待澄清。
- 最终版本1.0.5+8、Android包名/签名延续；生产签名材料不入Git。

## Review Focus

- 归档与删除区别及旧客户端upsert覆盖字段：缺字段时保留现有新字段。
- 不同币种快速连续刷新：队列payload与本地金额必须来自同一最新状态。
- 分类其他/未分类下钻、同日跨时区日期、混合历史与当前月份。
- 恢复码重放/并发重置及跨用户身份隔离，不允许新用户身份替代旧ID。
- PostgreSQL真实锁测试不可用SQLite替代；旧数据库与离线队列不可清空。

### Task 1: 审计与需求矩阵

Files: `docs/v1.0.5/*`。
- [x] 读取全部工作表和实际模块，发现来源错位及真实架构缺口。
- [x] 运行原版Flutter/pytest/Web基线并记录统计。
- [ ] 输出机器矩阵和原始输入哈希，逐行覆盖检查。
- [ ] 提交审计/设计/计划；不得标记业务验收完成。

### Task 2: 账户生命周期与汇率闭环（WP-B/F/E）

Files: Account model、assets domain/store/repository、AccountDetailPage/Settings、backend assets/models/sync/backup、migrations。
Interfaces: `Account.note/archivedAt`, `AssetStore.archiveAccount/restoreAccount`, `AssetsRepository.saveExchangeRate`沿用原接口。
- [ ] RED：归档payload保持历史引用、恢复；HKD→USD→拉取不回退、并发snapshot独立；API缺字段不擦掉新状态；迁移保留旧行。
- [ ] 运行新增测试，记录预期失败。
- [ ] 增量迁移、字段、现有upsert同步、服务端缓存降级及客户端提示。
- [ ] 账户管理共用一个列表，搜索/分组/归档/恢复/用途，不重复开发。
- [ ] 运行资产、同步、升级测试＋完整回归，提交可验证改动。

### Task 3: 公共统计口径、查询与预算（WP-F/C/A）

Files: `domain/transaction_query.dart`、Insights/Budget domain/store、StatsPage/LedgerPage/BudgetsPage；后端insights/budget。
Interfaces: 同一查询对象筛选、排序、CNY转换；`__total__`预算标识。
- [ ] RED：历史混入、交易日期与时间冲突、闰年/当前日均、转账/删除/缺汇率、总预算不重复计入。
- [ ] 写共享查询；调用方聚合/预算/账本共用；添加月份选择与分类/账户维度及下钻回退。
- [ ] 总额入口、分类手动/等额分配、使用率/超支，复用现有预算API和队列。
- [ ] 行级聚合=明细测试、预算与统计一致、跨设备同步，再完整回归并提交。

### Task 4: 记账与首页体验（WP-A/C）

Files: transaction_form/draft_editor、QuickEntry domain/store、Ledger preferences、Dashboard/AppShell。
- [ ] RED：午饭16块常用语料/低置信修正，默认CNY/偏好/编辑原币，中文组合输入，真实昵称时段。
- [ ] 复用统一表单写入和草稿确认；常用币种选择、有效偏好、归档账户不可新选。
- [ ] Widget/领域回归，Android实际输入单列验收；完整回归并提交。

### Task 5: 恢复码找回密码（WP-D）

Files: User migration、Auth schemas/service/router/client repository/store、login/profile/reset UI。
Interfaces: 密码验证生成恢复码、未登录reset接口；复用auth_version撤销。
- [ ] RED：无权限生成、错误凭证一致消息、重放/并发、旧token撤销、用户ID和数据不变。
- [ ] 高熵恢复码只存哈希，锁内单次消费和限流；前后端完整操作入口。
- [ ] Auth/API/迁移/数据隔离回归；完整回归并提交。

### Task 6: 集成验收与候选构建（WP-E）

Files: PG测试环境脚本、版本元数据、release guard、报告、Excel更新。
- [ ] 隔离本地PostgreSQL并跑3项真实并发测试，保留旧实现RED和修复GREEN证据。
- [ ] Flutter全量/analysis、pytest全量、Web/PWA、旧SQLite+待同步队列、两端CRUD/归档/换算/预算/冲突。
- [ ] Android/Windows/Web候选构建；真实签名覆盖/双机/Windows运行按实际环境记证据。
- [ ] 逐行正向反向验收；补齐需求库实现/验收/证据/commit/遗留列，不覆盖原文。
- [ ] 完成整合、实施、测试、发布准备及最终清零报告；未达到全部门禁不得声明清零或正式发布就绪。
