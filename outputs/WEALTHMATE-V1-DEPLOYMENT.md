# 随想记 V1.2 交付与部署

## 先说结论

真正的跨设备同步部署方式是：

```text
手机 Flutter App ─┐
                  ├─ http(s)://同一个服务器地址:18000 ─ FastAPI ─ PostgreSQL
Windows Flutter App┘
```

手机和电脑不直接互传数据，也不能把 `127.0.0.1` 填到手机配置里。服务端是共同账本；客户端离线时先写本地 SQLite/Drift，联网后按操作 ID 推送、按服务器版本拉取。

## 本次 V1.2 已落地

- 首页只保留“快捷记”和“记一笔”两个入口；最近账目可点开详情、编辑或删除。
- 快捷记支持“今天吃饭 30 元”这类一句话输入：自动根据自定义分类、账户名称、默认账户和最近已确认记录补齐；草稿保留“修改”和“确认入账”。修改后的分类/账户会形成快捷记忆，并随同一账号资料同步。
- 分类可自定义名称，可改名、归档和恢复；账户可点开修改名称、用途、币种、初始余额和流动资产配置。
- “我的 → 账户与登录”支持编辑显示名称、登录用户名和密码；密码只在服务端保存哈希，修改密码后其他设备需要重新登录。
- 预算已改为服务器共享数据，可修改月份、分类和额度；80%/100%/超支会在应用内提醒，并按预算、月份和阈值去重。
- 统计支持本日、本周、本月折线趋势、分类柱状图、饼图和支出汇总卡。
- 汇率页支持获取公开核验汇率或手动录入，并展示来源、日期和“待补充汇率”状态。
- 客户端缓存派生统计和稳定页面，减少切换页面时的重算和重建。

## 交付物

- `suixiangji-v1.2-source-20260904-clean.zip`：后端与 Android/Windows Flutter 源码打包文件。
- `suixiangji-v1.2-android-20260904.apk`：V1.2 Android 手机安装包，已按当前电脑局域网地址构建。
- `suixiangji-v1.2-windows-20260904.zip`：V1.2 Windows 客户端完整运行包，解压后运行 `wealthmate_flutter.exe`。
- `wealthmate_backend/`：FastAPI、SQLAlchemy、PostgreSQL、JWT、幂等同步、汇率快照、LangGraph 草稿流程、月度报告、备份恢复和 Docker Compose。
- `wealthmate_flutter/`：Android + Windows Flutter 源码，SQLite/Drift schema、本地队列、手动记账、自然语言草稿确认、账户管理、报告接口和同步接入。
- `wealthmate/`：可立即预览的 Web/PWA 版本。它是演示版，不承担手机与电脑的正式同步。

## A. 在一台 Windows 电脑上部署服务器

先安装 Docker Desktop，然后打开 PowerShell。首次部署时如果 `.env` 不存在，再执行：

```powershell
cd C:\Users\Admin\Documents\Codex\2026-09-03\an\outputs\wealthmate_backend
if (-not (Test-Path .env)) { Copy-Item .env.example .env }
notepad .env
docker compose up -d --build
Invoke-WebRequest http://127.0.0.1:18000/health
```

编辑 `.env` 时至少修改：

- `WEALTHMATE_DB_PASSWORD`
- `WEALTHMATE_DATABASE_URL` 中的数据库密码
- `WEALTHMATE_JWT_SECRET`
- `WEALTHMATE_DEMO_PASSWORD`

本机已实际启动服务器，浏览器访问 `http://127.0.0.1:18000/health` 返回 `status: ok`；登录接口和分类接口也已验证通过。

### 让手机访问 Windows 服务器

本机当前局域网地址为 `192.168.1.15`，手机端 API 地址应填写：`http://192.168.1.15:18000`。

1. 手机和 Windows 电脑连接同一个 Wi-Fi。
2. 在 Windows 执行 `ipconfig`，找到当前 Wi-Fi 网卡的 IPv4，例如 `192.168.1.20`。
3. 允许 Windows 防火墙接收 TCP 18000 入站连接；如果使用公司/公共网络，优先改用 HTTPS 服务器，不要长期开放明文 HTTP。
4. 手机浏览器先访问 `http://192.168.1.20:18000/health`。能打开才说明网络打通。

## B. 构建 Windows 客户端

客户端源码已经准备好，重新构建时使用以下命令（不需要再次执行 `flutter create`）：

```powershell
cd C:\Users\Admin\Documents\Codex\2026-09-03\an\outputs\wealthmate_flutter
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter run -d windows --dart-define=WEALTHMATE_API_BASE_URL=http://192.168.1.20:18000
```

确认同步、登录和记账流程后生成发布版：

```powershell
flutter build windows --release --dart-define=WEALTHMATE_API_BASE_URL=http://192.168.1.20:18000
```

发布目录在 `build\windows\x64\runner\Release\`。把整个 Release 文件夹交给 Windows 客户端使用者，不要只复制 exe。

本次已构建好的 Windows 包为 `suixiangji-v1.2-windows-20260904.zip`；解压后双击 `wealthmate_flutter.exe`。

## C. 构建 Android 手机 App

手机端直接安装已生成的 `suixiangji-v1.2-android-20260904.apk`。如果要重新构建，先安装 Flutter stable、Android Studio、Android SDK，并打开手机的开发者模式和 USB 调试：

```powershell
cd C:\Users\Admin\Documents\Codex\2026-09-03\an\outputs\wealthmate_flutter
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter devices
flutter run -d <手机设备名> --dart-define=WEALTHMATE_API_BASE_URL=http://192.168.1.20:18000
```

生成 APK：

```powershell
flutter build apk --release --dart-define=WEALTHMATE_API_BASE_URL=http://192.168.1.20:18000
```

APK 默认在 `build\app\outputs\flutter-apk\app-release.apk`。

本次已构建好的手机包为 `suixiangji-v1.2-android-20260904.apk`。安装后，手机和 Windows 电脑连接同一个 Wi-Fi，登录同一账号即可同步。

局域网开发使用 `http://` 时，Android 平台生成后如遇明文流量拦截，需要在 `android/app/src/main/AndroidManifest.xml` 的 `<application>` 增加 `android:usesCleartextTraffic="true"`。正式使用应把 API 放到 HTTPS 域名，不建议长期打开明文流量。

## D. 第一次使用顺序

1. 手机或 Windows App 打开后输入服务端地址，登录 `.env` 中的用户名和密码。
2. 在“财富”页新增账户；账户可以选择资产/负债和币种，初始默认 CNY。
3. 手动记一笔，或输入“今天打车 23 元，微信支付”。
4. 快捷记只需输入消费事实，例如“今天吃饭吃了 30 元”。系统会按分类名称、账户名称、默认账户、最近记录和已确认记忆自动补齐；草稿下方始终提供“修改”，可调整金额、类型、分类、账户、日期、币种和备注，确认无误后点“确认入账”。没有账户、金额或不确定分类时不能正式入账。
5. 点击同步；另一台设备登录同一账号后即可看到同一笔账。
6. 外币先录原始金额和币种；在“财富 → 管理汇率”获取或手动录入有来源、日期的汇率快照，没有可靠汇率会显示“待补充汇率”。
7. 在“预算”页点击已有预算即可修改月份、分类和额度；支出达到阈值时会显示提醒。
8. 在“统计”页切换本日、本周、本月，查看折线、柱状和饼图；程序统计数字，AI 只解释这些数字。
9. 每月进入“我的”生成报告；未配置模型时会明确显示 AI 未配置/数据不足，基础记账仍然可用。
10. 如需修改账户显示名，进入“财富”点击账户，或进入“我的 → 账户名称与账户配置”；账户 ID 不变，历史账目不会丢失。
11. 如需修改昵称、用户名或密码，进入“我的 → 账户与登录”；修改用户名/密码后，在其他手机和电脑使用新凭证重新登录。

## E. AI 模型配置

默认 `WEALTHMATE_LLM_PROVIDER=none`，因此不依赖 AI 也能记账、同步、统计和备份。若要启用 DeepSeek、Qwen 或 Ollama，把它们配置为 OpenAI-compatible endpoint：

```text
WEALTHMATE_LLM_PROVIDER=deepseek
WEALTHMATE_LLM_MODEL=<你的模型名>
WEALTHMATE_LLM_BASE_URL=<兼容 /chat/completions 的地址>
WEALTHMATE_LLM_API_KEY=<在线服务需要时填写>
```

服务端会把调用任务、模型、状态、Token 元数据和结果摘要写入 `agent_logs`，不把原始备注写进日志。

## 当前环境验收状态

| 项目 | 状态 | 证据/说明 |
|---|---|---|
| 后端领域规则 | 通过 | 后端测试 17/17 |
| FastAPI API 合同 | 通过 | 含登录、幂等、分类 CRUD、预算 CRUD、周期统计、汇率、报告 |
| Python 语法编译 | 通过 | `compileall` |
| Flutter 依赖与 Drift 代码生成 | 通过 | `flutter pub get`、`dart run build_runner build` |
| Flutter analyze/test | 通过 | 静态检查 0 问题，测试 40/40 |
| Docker 实际启动 | 通过 | V1.2 镜像已重建，PostgreSQL healthy，FastAPI 已在 `127.0.0.1:18000` 运行；登录、资料、分类和预算接口验证通过 |
| Flutter 源码 | 已交付 | 含 Android/Windows 配置入口与 Drift SQLite schema |
| APK | 已生成 | `suixiangji-v1.2-android-20260904.apk`，已按 `http://192.168.1.15:18000` 构建 |
| Windows 客户端 | 已生成 | `suixiangji-v1.2-windows-20260904.zip`，包含 V1.2 完整 Release 运行目录 |
| Web/PWA 预览 | 通过 | 可本地打开，但不是正式跨设备同步方案 |

因此当前已经交付的是“V1 源码、已运行的本机服务端、Android 手机安装包、Windows 客户端运行包、客户端本地能力和测试通过的版本”。手机与电脑首次联机前，需要确保 Windows 防火墙允许 TCP 18000；本次会话因账户没有管理员权限未能自动创建该规则。若手机访问不了服务端，请用管理员 PowerShell 执行：

```powershell
New-NetFirewallRule -DisplayName "WealthMate API 18000" -Direction Inbound -Action Allow -Protocol TCP -LocalPort 18000 -Profile Private
```
