---
description: Performance audit — static bundle analysis, runtime profiling, Lighthouse, React render tracing. Identifies bottlenecks and optionally fixes them via pipeline.
---

# Development Pipeline: Performance Audit

You are auditing performance. Find bottlenecks first, then fix — never the reverse.
All steps are pre-approved. Run to completion.

---

## STEP 1: Static Analysis

### Bundle size
```bash
# Next.js
npx @next/bundle-analyzer 2>/dev/null || \
npx vite-bundle-visualizer 2>/dev/null || \
npx source-map-explorer 'dist/**/*.js' 2>/dev/null || true

# Find large deps
cat package.json | jq '.dependencies | keys[]' | \
  xargs -I{} sh -c 'du -sh node_modules/{} 2>/dev/null' | \
  sort -rh | head -20
```

### Unused exports / dead code
```bash
npx ts-prune 2>/dev/null | head -30 || true
npx knip 2>/dev/null | head -30 || true
```

### Import cost hotspots
Check for: lodash (should be lodash-es), moment (replace with date-fns), full icon library imports.

---

## STEP 2: TypeScript / Build

```bash
time npx tsc --noEmit 2>&1 | tail -5
time npm run build 2>&1 | tail -10
```

Flag any build over 30s as a bottleneck.

---

## STEP 3: Runtime Profiling (if browser app)

Check for common React performance issues in the codebase:
```bash
# Components missing memo/useMemo/useCallback on expensive renders
grep -r "useState\|useEffect" src/ --include="*.tsx" -l | head -20
# Large lists without virtualization
grep -r "\.map(" src/ --include="*.tsx" -l | xargs grep -l "return.*<" | head -10
```

Identify:
- Components rendering on every parent render (missing `memo`)
- Expensive recalculations not in `useMemo`
- Event handlers not in `useCallback` causing child re-renders
- Large lists not using `react-virtual` / `@tanstack/react-virtual`

---

## STEP 4: Lighthouse (if web app with dev server)

```bash
# Start dev server in background if not running
npx lighthouse http://localhost:3000 \
  --only-categories=performance \
  --output=json \
  --output-path=.claude/perf-report.json \
  --chrome-flags="--headless" 2>/dev/null \
  && node -e "
    const r = require('./.claude/perf-report.json');
    const c = r.categories.performance;
    console.log('Score:', Math.round(c.score * 100));
    r.audits['render-blocking-resources']?.details?.items?.forEach(i => console.log('Blocking:', i.url));
    r.audits['unused-javascript']?.details?.items?.slice(0,5)?.forEach(i => console.log('Unused JS:', i.url, i.wastedBytes));
  " 2>/dev/null || true
```

---

## STEP 5: Report & Action Plan

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
⚡ PERFORMANCE AUDIT RESULTS
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Lighthouse:   [score]/100
Build time:   [Xs]
Bundle size:  [X MB]

🔴 Critical (fix now):
  [list]

🟡 Should fix:
  [list]

🟢 Good:
  [list]
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

If critical issues found, offer: "Fix now via `/dev-pipeline:dev-pipeline`? [Y/N]"
If user confirms, create performance MIUs and run the pipeline.
