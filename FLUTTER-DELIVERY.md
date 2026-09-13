# 随想记 Flutter 交付与验收状态

源码目录：`outputs/wealthmate_flutter/`

## 已交付源码

- Flutter package metadata 与 Material 3 主题
- Account / Category / Transaction / Budget / Goal / FinanceState JSON 模型
- 收支、转账、净资产、储蓄率、预算阈值、应急金口径规则
- 自然语言金额/分类/账户解析和 85% 确认门
- local repository、幂等同步队列、软删除、过期更新冲突记录
- Feature RemoteDataSource：auth、accounts、categories、transactions、stats、wealth、budgets、agent、backup、sync 资源边界；ApiClient 仅保留兼容 façade
- 模块化 Feature Store/Repository：Auth、Ledger、Assets、Budget、QuickEntry、Insights、Backup；SyncCoordinator 只编排既有同步行为
- LocalStateSession 作为 FinanceState、SyncQueue、cursor 和冲突恢复的唯一串行写入口
- 平台安全 Token 存储、App 重启恢复和 401 自动清除登录状态
- Android 五 Tab：首页、账本、统计、财富、我的
- Windows 宽屏左侧导航 + 中间内容 + 右侧详情面板
- 手工记账、自然语言草稿确认、编辑、软删除、预算/财富/设置页
- 单元测试与 Widget 测试源文件

## 验收矩阵（2026-09-04）

| 检查项 | 状态 | 事实 |
|---|---|---|
| Dart/Flutter 可执行文件 | TESTED | Flutter 3.47.2、Dart 3.13.2 |
| `flutter pub get` | TESTED | 依赖解析成功，含 `flutter_secure_storage` |
| `dart format --output=none --set-exit-if-changed .` | NOT_RUN | 本批次未执行格式检查 |
| `flutter analyze` | TESTED | 无问题 |
| `flutter test` | TESTED | 241/241 通过 |
| `flutter build apk --debug` | NOT_RUN | 本批次未重新构建 |
| `flutter build windows --debug` | NOT_RUN | 本批次未重新构建 |
| 后端真实联调 | BLOCKED | 尚未执行真实 FastAPI + PostgreSQL + Flutter Client 联调 |
| 真实推送 | BLOCKED | Bark/ntfy 未配置，未作任何成功声称 |

源码级检查已做：所有测试引用的模型、规则、仓库、状态和页面文件均已建立；未把缺少工具链的项目写成 PASS。

## V1.0.1 Android Network Contract

V1.0.1 目标版本为 `1.0.1+4`，Android `versionCode=4`。Android 请求使用 `cronet_http: 1.9.0` 的 Embedded Cronet；Google Play Services required 为 `NO`。Web 和非 Android 平台继续使用现有 `package:http` transport。

所有 Android 相关 Flutter 命令必须带：

```text
--dart-define=cronetHttpNoPlay=true
```

Release candidate 使用：

```text
flutter build apk --release --dart-define=WEALTHMATE_ENVIRONMENT=production --dart-define=WEALTHMATE_API_BASE_URL=https://api.suixiangji.icu --dart-define=cronetHttpNoPlay=true
```
