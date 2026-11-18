# Recipe changes

Every change to `recipes.json` gets a dated entry here with its evidence. The
learning watcher's consolidation pass appends proposals on the local
`learning/inbox` branch (evidence = sessions counted in its digest, never names);
a person reviews and merges them, then runs `python3 tools/render-recipes.py`.

## 2026-11-18 — initial map

- Added 16 recipes: the 10 task types the pipeline was missing a light path for
  (feature, enhancement, prd-digest, ui-design-round, review-only, test-only,
  bug-fix, hotfix, docs-sync, contract-change) plus the existing flows
  (trivial, new-project, pr-feedback, refactor, perf, deliver).
- Evidence: in the first 10 days of watcher data most sessions used no
  dev-pipeline command at all (counted as `ad-hoc`), and the routing table sent
  reviews, docs syncs, PRD digests and design rounds into the full pipeline.

## 2026-11-18 — iOS coverage

- `ui-design-round`, `enhancement` and `feature` now name the iOS checks
  (largest accessibility Dynamic Type size, VoiceOver, Reduce Motion, simulator
  run; engineering-craft `checklists/ios-swiftui-surface.md`).
- Evidence: an iOS design-system session found no iOS best-practice source
  anywhere in the router or the catalog; the project ships a SwiftUI app next to
  its web apps.

## 2026-11-18 — provider-setup

- New recipe `provider-setup` for third-party account setup where the owner
  must click through a dashboard: agent does every API/CLI step, reads the real
  dashboard in the browser, writes click-by-click steps (every field and pop-up),
  one list per environment, warns about locked settings up front, moves secrets
  only through secure-key-handoff, verifies with stack-setup.
- Evidence: a live payment-provider setup where the owner had to correct the
  steps (missed dialog choice and permission column, mixed environments, a lock
  discovered late) and two sandbox secrets were printed in chat.

## 2026-11-18 — first consolidation (by hand)

- `contract-change` gains a joint-run step: every consuming lane runs against
  the producer's local server before merge. Evidence: backend and web lane
  entries record the joint run finding a bug already live in production.
- `provider-setup` notes now hold the live payment-provider specifics
  (restricted-key dialog choice, the Connect permission column, where OAuth is
  locked and what unlocks it, value-pattern masking leaking quoted secrets).
- No other recipe change: recipes were not live yet (branch unmerged), so every
  session in the window was `ad-hoc` or inferred; there is no outcome evidence.
