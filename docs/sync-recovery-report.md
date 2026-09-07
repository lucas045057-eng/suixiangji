# Sync Recovery Engineering Report

## 1. Dependency ordering

问题是客户端 batch 中 Transaction/Budget 可能排在其 Account/Category 之前，服务端按原顺序执行会在依赖尚未创建时失败。

修复为 `/sync/push` 内部稳定排序：Account/Category 先于依赖实体，同时保持同类 operation 的原始相对顺序和响应映射。`_save_tx`、`_save_budget` 的存在性与用户归属校验仍然保留。

## 2. Batch atomicity

失败 batch 回滚，后续 operation 不执行，`User.sync_version` 不推进，不留下部分业务写入。数据库约束与应用层校验共同保护实体完整性。

## 3. Entity conflict detection

冲突比较：

```text
payload.server_version
vs
server entity.server_version
```

过期操作返回受控的 `HTTP 200 + conflicts[]`，不会作为新的 SyncOperation 写入。客户端随后拉取服务器权威状态并移除对应冲突操作。

## 4. serverVersion persistence

Flutter FinanceState 正确持久化服务器游标和实体版本。push 回执、pull 合并和重启恢复均不把已保存 cursor 无故重置为 0。

## 5. Local user isolation

客户端绑定本地 owner 和已验证用户：

```text
same user relogin → preserve local finance state
different user → clear previous user's local finance state
```

服务器端同时校验实体 `user_id`，防止仅凭可猜测 ID 读取或修改其他用户数据。

## 6. Offline owner recovery

离线恢复只在以下三者匹配时允许：

```text
token
verified user
local owner
```

网络失败不会清除本地财务数据、队列或 cursor。无法证明 owner 的新环境不应擅自恢复其他用户的本地账本。

## 7. Queue stale snapshot

同一实体存在待提交变更时，最新完整操作快照替换过期 payload，避免编辑后仍上传旧金额、备注或关联账户。重启和重试保留同一 mutation identity。

## 8. Auth gate

历史 Bug：`/auth/me` 失败路径可能仍继续业务同步。

修复为显式认证成功/失败 gate。401 会清理失效凭据，但保留 local owner、FinanceState、Queue 和 cursor。历史测试日志中的 401 仅作为历史现场记录，不对其来源作未经证实的归因。

## 9. Edit operation identity

历史错误是 Edit 复用已接受 Create 的 `client_op_id`。现在：

```text
new logical Edit → unique edit client_op_id
Transaction.id remains stable
```

## 10. Conflict recovery cursor

历史问题是 push 冲突返回服务器版本后，客户端从该新版本开始 pull，可能漏掉恰好该版本的权威实体。

修复为按冲突操作的 base version 拉取，例如 stale based 14、服务器权威版本 15 时恢复 pull 从 14 开始；持久化 cursor 仍采用最大值，不回退。

## 11. Delete operation identity collision

历史错误是 Delete 使用 `<transaction.clientOpId>:delete`，导致不同客户端的逻辑删除可能共享 operation ID，被错误当作幂等重试。

修复为新逻辑 Delete 生成唯一 operation ID；同一队列操作的重试/重启继续复用该 ID。

## 12. Windows IME note bug

历史错误是 Windows IME 仍处于 composing 状态时保存，controller 读取过早而得到空备注，随后触发错误分类 fallback。

修复为先结束编辑/取消 composing，等待当前 frame，再读取 controller。最终真实回归备注 `FINAL2-RC-WINDOWS-EDIT` 已正确保存并传播。

## 13. cnyAmount stale derived field

历史错误是编辑 `91.91 → 92.92` 后，`cnyAmount` 仍为 91.91，导致 Dashboard 的 canonical amount 与 derived metric 不一致。

当前规则：

```text
CNY:
  cnyAmount = amount
  exchangeRate = 1.0

Foreign currency:
  cnyAmount = amount × exchangeRate
  rounded to 2 decimals

Missing exchange rate:
  conversionStatus = pending
  do not invent conversion
```

## Engineering conclusion

本阶段解决并验证的是已列入矩阵的同步问题：依赖排序、批次原子性、版本冲突、游标持久化、用户隔离、队列一致性、操作幂等、tombstone 和双端传播。
