# Referral Programme — MIU Breakdown (fixture: legitimate forms NEAR the bypass vectors)

SHOULD-PASS sibling of `bypass-vectors.md` — proves the tightened checks add no
false positives. Expected: exit 0. Covers:

- Symbol heuristic + co-editor exemption (finding 6): MIU 1 mentions BOTH the
  symbol `CreateReferralDto` and the dto file, but lists the file in its own
  `Files:` — a co-editor/definer, not a consumer-before-contract. MIU 3
  mentions the symbol AFTER the contract unit — correctly ordered.
- Exactly-"none" and annotated-none forms (finding 1): `Depends on: None`
  (capitalized) skips validation; `none (uses API contract from MIU 2)`
  validates the backward MIU 2 ref and passes.
- Comma-split bullet counting (finding 2): MIU 3 lists 3 paths across two
  bullets, one of them comma-separated — at the cap, not over it.
- Exact Block enums (finding 3): every unit uses a bare enum value.

### MIU 1 — Scaffold create-referral.dto.ts

- Block: BACKEND
- Files: apps/api/src/modules/referral/dto/create-referral.dto.ts
- Type: new-file
- Depends on: None
- What it does: Creates the initial CreateReferralDto skeleton in create-referral.dto.ts with the required fields.
- Build/Deploy/Runtime impact: none
- Test plan: dto compiles under tsc
- Done when:
  - create-referral.dto.ts compiles
  - skeleton exports CreateReferralDto

### MIU 2 — Finalize CreateReferralDto validation rules (API contract)

- Block: BACKEND
- Files: apps/api/src/modules/referral/dto/create-referral.dto.ts
- Type: modify-existing
- Depends on: MIU 1
- What it does: Completes the CreateReferralDto request DTO validation rules consumed by later units.
- Build/Deploy/Runtime impact: none
- Test plan: dto spec validates required fields and rejects unknown properties
- Done when:
  - dto spec passes
  - unknown properties are rejected with 400

### MIU 3 — Referral form (frontend)

- Block: FRONTEND
- Files:
  - apps/booking/src/app/book/referral-form.tsx, apps/booking/src/app/book/referral-form.test.tsx
  - apps/booking/src/app/book/use-referral.ts
- Type: new-file
- Depends on: none (uses API contract from MIU 2)
- What it does: Builds the referral form and types the submit payload with CreateReferralDto.
- Build/Deploy/Runtime impact: none
- Test plan: component test covers submit payload shape
- Done when:
  - form renders with validation errors surfaced
  - submit sends a typed payload
