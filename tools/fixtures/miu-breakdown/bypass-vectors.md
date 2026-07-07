# Referral Programme — MIU Breakdown (fixture: validator bypass vectors, Codex round-1 on PR #7)

Fixture for `tools/validate-miu-breakdown.sh`. Each unit exercises one bypass
that the validator previously let through (prose says "unit N" — a column-0
"MIU N" line would itself parse as a header). Expected: exit 1 with exactly
five violations:

- unit 1 — consumer names only the exported SYMBOL (`CreateReferralDto`),
  never the contract file, of a contract defined by the LATER unit 2
  (finding 6).
- unit 3 — `Block: BACKEND + FRONTEND` (prefix-match bypass, finding 3),
  a single Files bullet packing 4 comma-separated paths (finding 2), and
  `Depends on: none, MIU 4` (the "none" shortcut must not swallow the
  forward ref, finding 1).
- unit 4 — `Depends on: none (uses API contract from MIU 9)` — the annotated
  "none" must still validate the dangling ref (finding 1).

Unit 2 (the contract definer) must NOT be flagged.

### MIU 1 — Referral form (frontend)

- Block: FRONTEND
- Files: apps/booking/src/app/book/referral-form.tsx
- Type: new-file
- Depends on: none
- What it does: Builds the referral form and types the submit payload with CreateReferralDto — naming only the symbol, never the dto file.
- Build/Deploy/Runtime impact: none
- Test plan: component test covers submit payload shape
- Done when:
  - form renders with validation errors surfaced
  - submit sends a typed payload

### MIU 2 — Define CreateReferralDto (API contract)

- Block: BACKEND
- Files: apps/api/src/modules/referral/dto/create-referral.dto.ts
- Type: new-file
- Depends on: none
- What it does: Defines the CreateReferralDto request DTO consumed by the referral form.
- Build/Deploy/Runtime impact: none
- Test plan: dto spec validates required fields
- Done when:
  - create-referral.dto.ts compiles and exports CreateReferralDto
  - dto spec passes

### MIU 3 — Wire referral service endpoints

- Block: BACKEND + FRONTEND
- Files:
  - apps/api/src/modules/referral/referral.service.ts, apps/api/src/modules/referral/referral.controller.ts, apps/api/src/modules/referral/referral.module.ts, apps/api/src/modules/referral/referral.constants.ts
- Type: modify-existing
- Depends on: none, MIU 4
- What it does: Wires the referral service create path and controller endpoint.
- Build/Deploy/Runtime impact: none
- Test plan: service spec covers create happy path and tenant scoping
- Done when:
  - controller returns 201 with the created referral id
  - service spec passes

### MIU 4 — Referral test coverage

- Block: TESTING
- Files: apps/api/src/modules/referral/referral.service.spec.ts
- Type: new-test
- Depends on: none (uses API contract from MIU 9)
- What it does: Adds unit tests asserting happy-path referral creation.
- Build/Deploy/Runtime impact: none
- Test plan: the new spec itself — runs in the app test suite
- Done when:
  - both new tests pass locally
  - suite remains green
