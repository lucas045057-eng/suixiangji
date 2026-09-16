# 随想记 Flutter 客户端

这是按 V1 交接文档补齐的 Android + Windows 客户端。它与 Web/PWA 使用相同的业务规则：本地优先、转账不计入收入/支出、随想记助手只生成草稿，置信度低于 85% 时必须待确认。

## 运行前提

需要 Flutter stable、Android SDK（Android 构建）和 Visual Studio Desktop development with C++（Windows 构建）。当前机器已完成 Flutter 依赖、Drift 代码生成、静态检查和测试；Android SDK 与 Visual Studio 尚未安装，因此暂不包含 APK 或 Windows 安装包。

首次生成平台目录：

```text
flutter create . --platforms=android,windows
flutter pub get
```

本地离线演示：

```text
flutter run -d windows
```

接入后端时通过集中构建参数注入。开发/测试可以使用本机 HTTP：

```text
flutter run -d windows --dart-define=WEALTHMATE_ENVIRONMENT=development --dart-define=WEALTHMATE_API_BASE_URL=http://127.0.0.1:18000 --dart-define=WEALTHMATE_API_TOKEN=<jwt>
```

未提供基址时，界面会显示“离线演示/待配置”，不会显示虚假的同步成功。

正式环境只能注入 HTTPS API 地址。V1.0.1 目标版本为 `1.0.1+4`，正式 API 为 `https://api.suixiangji.icu`。

```text
PRODUCTION DOMAIN: api.suixiangji.icu
```

Android 运行、Android 集成测试和 Release 构建必须统一使用 Embedded Cronet，不依赖 Google Play Services：

```text
flutter run -d <android-device> --dart-define=WEALTHMATE_ENVIRONMENT=production --dart-define=WEALTHMATE_API_BASE_URL=https://api.suixiangji.icu --dart-define=cronetHttpNoPlay=true
flutter test --dart-define=cronetHttpNoPlay=true
pwsh -NoProfile -File ../../tools/build-android-release.ps1 -FlutterProjectPath . -OutputPath build/app/outputs/flutter-apk/app-release.apk -SigningPropertiesPath <controlled-signing-properties-path> -Environment production -ApiBaseUrl https://api.suixiangji.icu -VersionName 1.0.3 -VersionCode 6 -CronetHttpNoPlay
```

目标 Cronet distribution 为 `Embedded`，Google Play Services required 为 `NO`。Android App 内所有请求继续经过 `ApiClient → ApiTransport`。

应用会按 `latest_build > local_build` 判断是否有更新；更新下载仅打开经过校验的 HTTPS 地址，不执行静默安装。V1.0.1 基线与 V1.0.3 build 6 已证明使用同一签名证书，但真实设备覆盖安装和双设备同步仍需单独验收：

```text
APK UPDATE SIGNING: VERIFIED
REAL TWO-DEVICE TEST: NOT RUN
```

在真实设备覆盖安装与数据保留验收完成前，不得声称发布已完成，也不得通过卸载旧 App 规避本地数据问题。

## 结构

- `lib/domain/`：模型、演示数据和纯财务规则
- `lib/data/`：local repository、API client、同步队列和冲突合并
- `lib/state/`：本地优先状态容器与 Agent 确认门
- `lib/ui/`：Android 五 Tab、Windows 宽屏导航、账本/统计/财富/预算/我的页面
- `test/`：领域、仓库、同步、状态与页面行为测试

## 重要行为

- 资产账户收入增加、支出减少；负债账户支出增加、还款减少。
- 转账使用 `fromAccountId`/`toAccountId`，不进入收入、支出或预算。
- 应急金只统计选中的流动资产账户；选中负债账户会显示“应急金账户必须是资产账户”。
- “今天中午外卖 32 元，支付宝”先生成餐饮支出草稿；只有“确认入账”才会落入交易列表。
- 删除是软删除并进入待同步队列，冲突不会自动覆盖。
