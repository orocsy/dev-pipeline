---
description: Full 12-phase feature pipeline — requirements through deploy. Use for new features, complex bugs, and refactors.
---

# Development Pipeline: Full Flow

Alias for the main pipeline (the `feature` recipe). Delegates immediately to `/dev-pipeline:dev-pipeline`, whose PHASE −1 first checks whether a lighter recipe fits (`recipes/recipes.json`).

All gates (G1–G4) apply. Do not skip phases. Do not write code before G3 approval.

Run `/dev-pipeline:dev-pipeline $ARGUMENTS`
