# Local-First Multi-Device Sync Architecture

## 1. 身份与版本字段

这四个字段承担不同职责，不能混用：

```text
Transaction.id
= entity identity
= 这是谁

SyncOperation.client_op_id
= mutation identity
= 这是哪一次操作

serverVersion
= entity version

User.sync_version
= user-level incremental sync cursor
```

`Transaction.id` 在编辑和删除时保持不变；每次新的逻辑变更使用新的 `client_op_id`。用户游标只前进，不因冲突恢复而回退。

## 2. Push

```text
Local mutation
→ SyncOperation
→ persistent SyncQueue
→ POST /sync/push
```

服务端在执行 batch 前进行稳定的依赖排序，使同批次内的 Account/Category 先于依赖它们的 Transaction/Budget 保存。原始 payload 顺序不被客户端改写，返回结果仍按 `client_op_id` 对应原操作。

```text
client_op_id already accepted
→ idempotent replay

new operation + valid base version
→ accepted

new operation + stale entity serverVersion
→ HTTP 200 + conflicts[]
```

真实缺失或跨用户的 Account/Category 必须被受控拒绝，不能映射到默认账户或分类。失败 batch 回滚，不能留下部分业务写入。

## 3. Pull

```text
GET /sync/pull?since_version=<cursor>
```

正常增量 pull 只返回严格大于游标的服务端变更，客户端合并后持久化新的游标。冲突权威恢复时，pull 查询可以临时使用冲突操作的 base serverVersion，例如从 14 拉取服务器在 15 生成的权威实体；但持久化 cursor 使用 `max(previous, push, pull)`，永不回退。

## 4. Tombstone

```text
Delete != physical row deletion
deleted_at != NULL
serverVersion advances
```

客户端收到 tombstone 后从活跃 UI 隐藏实体，同时保留权威删除信息，避免后续 pull 或重启将已删除数据复活。

## 5. Queue semantics

```text
new logical mutation
→ new client_op_id

same logical mutation retry/restart
→ same client_op_id

accepted
→ exact queue removal

conflict
→ authoritative pull
→ apply server state
→ exact conflict operation removal
```

同一实体的待提交编辑保存最新的完整操作快照，避免队列中保留旧金额、旧备注或旧关联 ID。冲突处理只移除对应的冲突操作，禁止全局清空队列。

## 6. Authentication gate

启动时先恢复 token 和本地 owner，再以 `/auth/me` 结果决定是否进入业务同步。认证失败不会继续执行 push/pull；401 会清理失效凭据，但保留本地 FinanceState、Queue、owner 和 cursor，以便受保护的离线恢复流程继续工作。
