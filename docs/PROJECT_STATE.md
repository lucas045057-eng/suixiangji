# 随想记 V1.0.0 项目状态

冻结目标日期：2026-09-13
产品版本：`V1.0.0`
Flutter Version：`1.0.0+3`
Android versionName：`1.0.0`
Android versionCode：`3`

## Git 目标

- 分支：`main`
- Tag：`v1.0.0`
- 最终 SHA：以冻结时 `git rev-parse v1.0.0` 与 `git rev-parse main` 的一致性校验为准。
- 工作区：clean；最终只保留主工作目录。
- 历史 Tag `modular-monolith-v1`、`sync-v1.0-rc1` 保留。

## 发布范围

- 已完成集中配置入口：`WEALTHMATE_ENVIRONMENT`、`WEALTHMATE_API_BASE_URL`。
- 正式环境只接受 HTTPS API 基址；缺少基址时客户端保持离线演示，不伪造同步成功。
- 已完成匿名 `GET /app/version` 与 App 内启动/设置页更新提醒。
- 升级顺序只比较 `latest_build > local_build`，用于兼容历史 Beta `1.2.0+2` 到正式 `1.0.0+3`。
- 未修改数据库 schema、`0001_legacy_baseline`、`0002_beta_users` 或 Sync 协议。

## 安全验收

```text
PRODUCTION DOMAIN：NOT CONFIGURED
APK UPDATE SIGNING：VERIFIED
```

已对照历史 Beta APK 与 V1.0.0 候选 APK：applicationId 相同、Beta versionCode `2` 小于正式 versionCode `3`、证书 SHA-256 相同，因此支持直接覆盖安装。当前仓库的 Android release signing 配置仍使用 Android Debug 证书；正式商店分发前不得替换为未经证明的新证书。

详细证据与旧分支审计见 [V1.0.0 Git 清理与语义审计报告](V1.0.0-GIT-CLEANUP-REPORT.md)。
