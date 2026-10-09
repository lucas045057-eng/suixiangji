# Execution ledger — plan: docs/v1.0.5/development-plan.md

- Baseline 2026-10-09: Git 0020f0f; Flutter 367 passed; backend 139 passed/3 PG skipped/17 subtests/1 upstream warning; Web 7 passed.
- Source: latest desktop workbook confirmed by user; 5 sheets, 18 requirement records +12 engineering requirements; one truncated raw feedback and one duplicate derived row.
- Decision: use user-authorized continuous execution; no additional design permission gate. Recovery identity: user chose pre-saved recovery code.
- Task 1: complete (commit c7748ec); audit/design and machine mapping preserve all 18 source records and 12 engineering requirements.
- Task 2: complete implementation; Flutter 373 passed, backend 144 passed/3 PG skipped/17 subtests, Flutter analyzer clean. Archive/note/restore, sequential and concurrent FX, offline reopen, two-device sync and old-schema upgrade covered. Physical-device acceptance still NOT VERIFIED.
- Task 3: complete implementation. Shared business-date/snapshot query, elapsed-day averages, selectable month/custom range, category/account chart drill into existing Ledger, monthly total and category allocation. Flutter 377 passed; WSL backend 149 passed/0 skipped/17 subtests, including real PostgreSQL. Automated flow preserves selected month on return.
- Tasks 4–6: pending; physical-device acceptance and truncated UR-015 prevent a final closure claim.
- Environment: user confirmed local WSL2. Ubuntu Python 3.12 venv and isolated PostgreSQL 16.15 container on 127.0.0.1:55442 available. No production services changed. Android/Windows real acceptance not performed.
- Task 2 RED: Flutter 4 failing scenarios (archive ignored, no snapshot queue x2, infinite rate JSON corruption); backend 5 failing scenarios after correcting test fixture infrastructure.
- Ruling: queue test expects 2 latest entity snapshots, not 3 historical mutations — existing SyncQueue intentionally coalesces per entity; assertions still pin latest HKD=91/USD=350 and original balances. Changing queue semantics would violate existing idempotency behavior.
- PostgreSQL first real run: 1 failed/2 passed. The old concurrency harness waits for two threads inside a lock that deliberately permits one; BrokenBarrierError proves a harness deadlock. Correct scheduling preserves all version/cursor assertions and synchronizes unlocked historical allocators at flush, locked allocators before push.
- PostgreSQL historical implementation 711766e: 2 failed/1 passed (duplicate versions and stale identity map); current implementation: 3 passed. Logs postgres-historical-red.log/postgres-current.log. No production database used.
- Task 3 RED→GREEN: cross-month timestamp gave chart 14 vs correct 30; same monthly total created duplicate; backend total budget rejected nonexistent category. Four focused Flutter assertions plus two backend contracts passed. Existing hourly timezone regression was caught and repaired without changing its assertions.
