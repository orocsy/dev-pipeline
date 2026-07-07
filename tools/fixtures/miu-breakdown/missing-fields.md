# Notification Retry — MIU Breakdown (fixture: missing/invalid fields)

Fixture for `tools/validate-miu-breakdown.sh`. Expected: exit 1, flagging
(a) missing "Test plan" and "Done when" on the first unit, and (b) an invalid
Block enum, a 4-path Files list, and a single done-when criterion on the
second unit.

### MIU 1 — Add retry wrapper to email sender

- Block: BACKEND
- Files: apps/api/src/modules/notification/email.sender.ts
- Type: modify-existing
- Depends on: none
- What it does: Wraps the email send call in a bounded retry with jitter.
- Build/Deploy/Runtime impact: none

### MIU 2 — Persist retry attempts

- Block: DATABASE
- Files: apps/api/src/modules/notification/retry.store.ts, apps/api/src/modules/notification/retry.types.ts, apps/api/src/modules/notification/notification.module.ts, apps/api/src/modules/notification/notification.constants.ts
- Type: modify-existing
- Depends on: MIU 1
- What it does: Records each retry attempt so operators can inspect delivery health.
- Build/Deploy/Runtime impact: none
- Test plan: store spec covers write and read of attempt records
- Done when:
  - attempt records appear after a forced retry
