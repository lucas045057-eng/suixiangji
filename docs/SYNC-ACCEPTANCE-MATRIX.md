# 随想记 V1.3 同步验收矩阵

记录时间：2026-09-04

状态值仅使用：`PASS`、`FAIL`、`BLOCKED`、`NOT_RUN`。

| ID | 场景 | 自动化 | 集成 | Android | Windows |
|---|---|---|---|---|---|
| SYNC-01 | 在线新增 | PASS | PASS | NOT_RUN | NOT_RUN |
| SYNC-02 | 离线 10 笔后恢复 | PASS | BLOCKED | NOT_RUN | NOT_RUN |
| SYNC-03 | 离线修改 | PASS | BLOCKED | NOT_RUN | NOT_RUN |
| SYNC-04 | 离线删除 | PASS | BLOCKED | NOT_RUN | NOT_RUN |
| SYNC-05 | `client_op_id` 幂等 | PASS | BLOCKED | NOT_RUN | NOT_RUN |
| SYNC-06 | App 重启队列恢复 | PASS | BLOCKED | NOT_RUN | NOT_RUN |
| SYNC-07 | 新设备全量恢复 | PASS | BLOCKED | NOT_RUN | NOT_RUN |

## 自动化依据

- SYNC-01、03、04、05：`outputs/wealthmate_backend/tests/test_sync_acceptance.py`
- SYNC-02：后端 10 笔幂等测试 + `outputs/wealthmate_flutter/test/data_repository_test.dart` 的 10 笔本地队列测试
- SYNC-06：`outputs/wealthmate_flutter/test/data_repository_test.dart` 的 Drift SQLite 队列持久化测试
- SYNC-07：后端全量 pull 测试 + `outputs/wealthmate_flutter/test/data_repository_test.dart` 的空本地仓库合并测试
- push 回执版本号：`outputs/wealthmate_flutter/test/data_repository_test.dart` 验证 `server_version` 回写本地交易
- Flutter 的队列与合并逻辑：`outputs/wealthmate_flutter/lib/data/finance_repository.dart`
- 服务端同步接口：`outputs/wealthmate_backend/app/api.py` 的 `/sync/push` 和 `/sync/pull`
- 跨用户隔离：`test_sync_cross_user_cannot_read_or_mutate_another_users_data`

## 判定边界

- `PASS` 只表示对应自动化测试通过。
- `BLOCKED` 表示该具体场景尚未在真实 FastAPI + PostgreSQL + Flutter Client 联调环境中完成。
- `NOT_RUN` 表示本次没有实际操作 Android 或 Windows 设备。
- 本矩阵不把 WebSocket 计入同步主链路；Batch 1 仍使用 REST push/pull。
