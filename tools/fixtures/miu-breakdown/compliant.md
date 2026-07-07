# Widget Creation — MIU Breakdown (fixture: fully compliant)

Fixture for `tools/validate-miu-breakdown.sh` — three units, all 8 mandatory
fields, contract defined before its consumers. Expected: exit 0.
(`run-fixture-tests.sh` also re-validates this file as a CRLF variant and a
column-0-bullet variant — both must pass.)

### MIU 1 — Define CreateWidgetDto (API contract)

- Block: BACKEND
- Files: apps/api/src/modules/widget/dto/create-widget.dto.ts
- Type: new-file
- Depends on: none
- What it does: Defines the CreateWidgetDto request schema (zod) that the service and controller consume in later units.
- Build/Deploy/Runtime impact: none
- Test plan: unit spec validates required fields and rejects unknown properties
- Done when:
  - create-widget.dto.ts compiles and exports CreateWidgetDto
  - validation spec passes for happy path and unknown-property rejection

### MIU 2 — Wire CreateWidgetDto into WidgetService

- Block: BACKEND
- Files: apps/api/src/modules/widget/widget.service.ts, apps/api/src/modules/widget/widget.controller.ts
- Type: modify-existing
- Depends on: MIU 1
- What it does: Imports CreateWidgetDto from create-widget.dto.ts and applies it in WidgetService.create plus the controller endpoint.
- Build/Deploy/Runtime impact: none
- Test plan: service spec covers create happy path and tenant scoping
- Done when:
  - WidgetService.create accepts a validated payload
  - controller returns 201 with the created widget id

### MIU 3 — Widget creation test coverage

- Block: TESTING
- Files: apps/api/src/modules/widget/widget.service.spec.ts
- Type: new-test
- Depends on: MIU 1, MIU 2
- What it does: Adds unit tests asserting happy-path creation and rejection of extra payload fields.
- Build/Deploy/Runtime impact: none
- Test plan: the new spec itself — runs in the app test suite
- Done when:
  - both new tests pass locally
  - suite remains green with no snapshot churn
