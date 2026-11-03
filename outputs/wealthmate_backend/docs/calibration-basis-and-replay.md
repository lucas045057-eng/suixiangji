# 余额基准与日期回放 API

所有金额判断使用服务端 Decimal。新客户端应持久保存并原样重发 token，不解码或自行计算摘要。

## 取基准

`GET /assets/accounts/{account_id}/balance-basis?effective_on=2026-09-30`

建议统一发送 `X-Wealthmate-Sync-Protocol: 2`。effective_on 缺省为服务器今天，不接受未来日期；账户必须属于当前用户且未归档、未删除。读取持有共享用户锁，既不写收据也不推进版本。

```json
{
  "account_id": "cash",
  "effective_on": "2026-09-30",
  "balance_cny": "1000.000000",
  "basis_version": 1,
  "basis_token": "b1.<payload>.<signature>",
  "ttl_seconds": 600,
  "expires_at": "2026-11-03T10:10:00+00:00",
  "server_version": 42
}
```

token 为 URL-safe Base64 JSON + HMAC-SHA256，签名密钥从 JWT secret 做域隔离派生。载荷含 basis_version/user_id/account_id/as_of/balance_cny/digest/issued_at/expires_at。金额固定六位小数字符串，零规范为 0.000000。有效期 10 分钟；token 只证明该用户、账户与日期下的相关财务内容，没有下载游标推进含义。

摘要覆盖账户资产/负债类型、币种、有效 opening CNY 值以及截止日期内每个有效流水的 ID、腿角色、业务日期和有符号 CNY 影响，按 ID/腿排序。不包含名称、备注、分类、updated_at、全局 sync_version、无关账户或之后发生的流水。即使新流水净效应为零也会改变摘要；相同财务内容的 ABA 允许相等。

## 提交

`POST /assets/accounts/{account_id}/calibration`

```json
{
  "client_op_id": "calibration-op-1",
  "adjustment_id": "adjustment-1",
  "target_cny": "1200.00",
  "effective_on": "2026-09-30",
  "basis_token": "b1.<payload>.<signature>"
}
```

expected_current_cny 仍可单独使用，保留旧客户端请求。二者同时出现时 token 优先，expected_current_cny 完全忽略（包括 double 产生的额外小数）。effective_on 必须与 token 对应；目标继续限制两位小数。

锁用户后先查幂等收据，再验证尚未接受的 token、重放当前余额与摘要。已接受的相同操作即使 token 过期仍返回原条目；换了 token 或目标不要复用已接受的操作 ID。摘要不符时不自动把旧目标 rebase，不写调整、收据或水位；客户端刷新账目和基准后由用户重新确认。

| HTTP | code | 含义 |
|---|---|---|
| 400 | invalid_basis_token | 格式、版本、签名或签发时间非法 |
| 422 | basis_scope_mismatch | 用户、账户或生效日不匹配 |
| 409 | basis_expired | 尚未接受的 token 已满 600 秒 |
| 409 | balance_changed | token 所指财务内容已变化，包括从完整变成待换算 |
| 409 | conversion_pending | 取基准/旧数字路径缺少可用 CNY 快照 |
| 422 | basis_out_of_range | 回放余额超出现有校准/备份元数据金额域 |
| 422 | invalid_effective_on | 取基准日期在未来 |
| 409 | operation_mismatch | 已使用的操作 ID 改了请求 |
| 404 | 现有 detail | 账户不存在或不可访问 |
| 409 | account_inactive | 账户已归档或删除 |
| 409 | balance_unchanged | 目标与当前余额相同，不写零额调整 |
| 426 | upgrade_required | 低于用户/环境的协议 floor |

400/409/422 的领域错误均有根对象 code/detail；请求外壳类型/日期错误仍走 FastAPI 422 字段校验。

## 净值口径

`GET /wealth?as_of_date=2026-09-30` 携带协议 2 头，按业务日 occurred_on <= D 回放（含当天所有调整，不含之后调整）。资产和负债 adjustment 均直接加有符号差额，净值=资产-负债。

已有 cny_amount/opening_cny_amount 优先并保持冻结；不会按公共候选缓存的最新价格重估。对于只保存了 rate/date 而未保存 CNY 金额的旧记录，可以用该记录截至 D 可用的持久汇率快照作六位小数只读换算。缺少金额和可用日期快照时标 pending，不使用候选缓存编造落账金额。该口径是人民币账面回放，不是外币原币余额按市价重估。

协议 2 响应增加 as_of_date/excludes_later_adjustments/valuation_mode。有待换算项的账户 cny_balance 为 null，对应资产/负债总额为 null，net_worth 为 null；known_cny_balance/known_total_assets/known_total_liabilities 只表示已知部分。客户端不能把 null 当 0。账户 cny_balance_exact 为六位字符串；校准基准仍以取基准接口为准。

无协议头保留旧财富响应键与旧的部分金额约定，并继续不含 adjustment。没有显式 as_of_date 时保留原当前视图的行为；校准和历史报表总是传明确日期。

月报内部统一调用相同 Decimal 回放，截止月末。协议 2 月报新增 net_worth_snapshot；既有收支/储蓄率指标仍排除调整。财务写入使受影响月份及之后的净值缓存失效；账户 opening/框架变化清除全部月份。缓存命中时仍按月末重算净值，不调用 LLM 重写旧叙述。既有消费指标/叙述继续原 force 缓存策略。

账户没有历史开户日或财务框架版本：opening 是历史基线，不猜测开户日期；归档/删除按现存时间戳的 UTC 日期确定历史可见性。历史账目编辑/删除后是对当前账本按业务日重新回放，不是还原当时数据库的审计快照。

## 备份 v3 重放措辞

同 restore_id 零写入；新 restore_id 业务行不重复、仅新增一条 backup_restore 收据。新 ID 可重分配既有可变行版本并推进水位，已接受调整保持原行。不要把“幂等”误解为不同恢复命令也不推进水位。