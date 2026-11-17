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
