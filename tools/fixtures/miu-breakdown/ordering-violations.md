# Referral Programme — MIU Breakdown (fixture: ordering violations + co-editor exemption)

Fixture for `tools/validate-miu-breakdown.sh`. Expected: exit 1 with exactly
two violations, both on the third unit — a forward dependency, and a
consumer-before-contract reference to create-referral.dto.ts (defined by the
fourth unit). The first two units BOTH list apps/api/prisma/schema.prisma in
their own "Files:" — two sequential units legitimately editing the same file
in the correct order — and must NOT be flagged (co-editor exemption to the
contract-source rule).

### MIU 1 — Add loyaltyTier column to Customer

- Block: BACKEND
- Files: apps/api/prisma/schema.prisma
- Type: modify-existing
- Depends on: none
- What it does: Adds the loyaltyTier column to the Customer model in schema.prisma.
- Build/Deploy/Runtime impact: requires prisma migrate + client regeneration
- Test plan: migration applies cleanly on a scratch database
- Done when:
  - migration applies with no drift
  - prisma client regenerates without type errors

### MIU 2 — Add Referral model

- Block: BACKEND
- Files: apps/api/prisma/schema.prisma
- Type: modify-existing
- Depends on: MIU 1
- What it does: Adds the Referral model to schema.prisma — the same schema file the previous unit edits, in the correct order.
- Build/Deploy/Runtime impact: requires prisma migrate + client regeneration
- Test plan: migration applies cleanly on a scratch database
- Done when:
  - Referral table exists after migrate
  - prisma client exposes the Referral delegate

### MIU 3 — Referral form (frontend)

- Block: FRONTEND
- Files: apps/booking/src/app/book/referral-form.tsx
- Type: new-file
- Depends on: MIU 4
- What it does: Builds the referral form and imports CreateReferralDto from create-referral.dto.ts to type the submit payload.
- Build/Deploy/Runtime impact: none
- Test plan: component test covers submit payload shape
- Done when:
  - form renders with validation errors surfaced
  - submit sends a typed payload

### MIU 4 — Define CreateReferralDto (API contract)

- Block: BACKEND
- Files: apps/api/src/modules/referral/dto/create-referral.dto.ts
- Type: new-file
- Depends on: MIU 2
- What it does: Defines the CreateReferralDto request DTO consumed by the referral form.
- Build/Deploy/Runtime impact: none
- Test plan: dto spec validates required fields
- Done when:
  - create-referral.dto.ts compiles and exports CreateReferralDto
  - dto spec passes
