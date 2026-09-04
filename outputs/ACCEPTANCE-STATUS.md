# 随想记 V1.2 验收状态

源码打包文件：`suixiangji-v1.2-source-20260904-clean.zip`。

可直接使用的客户端：

- Android：`suixiangji-v1.2-android-20260904.apk`。
- Windows：`suixiangji-v1.2-windows-20260904.zip`。

## 已通过

- 手动收入/支出记账和软删除：客户端源代码与后端接口均已覆盖。
- 自然语言草稿：规则优先；服务端使用 LangGraph 编排规则解析、必要时模型复核、最终草稿，始终要求用户确认。
- 统计规则：程序计算收入、支出、结余、储蓄率、分类支出；转账不计入收入/支出。
- 账户和净资产：资产/负债账户、账户余额、总资产、总负债、净资产接口已实现。
- 多币种：原始金额、原始币种、CNY 金额、汇率、日期、来源和待补充状态已实现。
- 同步：客户端本地队列 + 服务端 `client_op_id` 幂等 + `server_version` 增量拉取已实现。
- 月报：程序生成结构化统计，AI 只解释统计；模型不可用时不阻塞基础记账。
- 备份：`/backup/export` 和 `/backup/restore` 已实现。
- 自定义分类：新增、改名、归档、恢复，历史账目仍保留原分类 ID。
- 账户配置：财富页账户可点开修改名称、账户用途、资产/负债、币种、初始余额、流动资产和默认支付配置。
- 快捷记自动补齐：根据自定义分类/账户、默认账户、最近交易和已保存习惯补齐；草稿支持修改后再确认入账。
- 用户资料：支持编辑显示名称、登录用户名和密码；服务端验证当前密码、用户名唯一性和新密码长度。
- 预算：服务端共享 CRUD，支持修改月份、分类和额度；80% 警告、100% 用完、超过 100% 超支提醒，并按阈值去重。
- 周期统计：本日/本周/本月折线趋势、分类柱状图、饼状图和支出汇总。
- 账目详情：最近账目可查看时间、原始金额、平台账户、分类、备注、人民币金额和汇率来源。
- 汇率管理：公开汇率获取、手动录入、来源/日期展示、缺失时“待补充汇率”。
- 性能：派生指标按状态缓存，页面按需创建，图表使用独立重绘区域。

## 已验证证据

- 后端：`python -m unittest discover -s tests -v`，17/17 通过。
- 后端：`python -m compileall -q app tests`，通过。
- Flutter：`flutter analyze`，无问题。
- Flutter：`flutter test`，40/40 通过。
- Flutter：`flutter pub get` 和 Drift `build_runner` 代码生成，通过。
- Docker Compose：V1.2 镜像已重建，PostgreSQL healthy，FastAPI 在 `http://127.0.0.1:18000` 运行，健康/登录/分类/预算/用户资料接口通过。
- Web/PWA：7/7 测试通过、浏览器桌面/移动布局检查通过、控制台无错误。
- Android：V1.2 `flutter build apk --release` 成功，已按 `http://192.168.1.15:18000` 构建。
- Windows：V1.2 `flutter build windows --release` 成功，Release 目录已打包；已按 `http://192.168.1.15:18000` 构建。
- Android SDK 已配置到 `E:\Android\Sdk`，Visual Studio C++ 构建环境已被 Flutter 识别。

## 交付后仍需执行的真实设备验收

- 手机与 Windows 在同一局域网下的真实登录、离线记账、恢复网络后去重同步。
- Windows 防火墙允许 TCP 18000 入站；本次会话因当前账户没有管理员权限，未能自动创建防火墙规则。

当前服务端地址为 `http://192.168.1.15:18000`。Android 和 Windows 构建已通过；Flutter 的许可证检查仍显示兼容性提示，但 Gradle 已实际接受所需许可证并成功完成构建。完整安装和同步步骤见 [WEALTHMATE-V1-DEPLOYMENT.md](WEALTHMATE-V1-DEPLOYMENT.md)。
