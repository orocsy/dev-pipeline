# Workflow routes

Dev-pipeline chooses a route and composes existing commands. External skills supply technical decision rules. Resolve them through the installed skill router or the linked source; record the version used and any fallback. The same agent can follow each route. Add specialist review only when authorized and warranted.

[View the website route and ownership diagram](diagrams/web-delivery.html).

| User intent | Command sequence | Evidence before finishing |
|---|---|---|
| First build | New project scaffold when needed → plan → implement → validate → review → deliver | Requirements matched to working journeys. For public websites run the SEO and performance routes after the first runnable build; validate the affected routes again after deployment |
| Change existing requirements | update or plan the affected slice → implement → validate → review → deliver | Contract and data compatibility plus the changed user journey |
| Repair a defect | fix → validate the reproduction and affected callers → review → authorized delivery | Failing old behavior, verified fix and the real entry after delivery |
| Production incident | hotfix for immediate restoration → verify current service → diagnose root cause → fix and review | Recovery and permanent correction have separate evidence |
| Refactor | refactor proposal → plan accepted slice → implement → validate unchanged behavior → review → deliver | Before/after public behavior and any measurable benefit |
| SEO audit | seo → fix verified blockers in authorized scope → validate/review/deliver → read platform outcomes | Exact URL, cause, live repair, platform state and measured search results |
| Performance | perf → fix measured bottleneck in authorized scope → validate/review/deliver → matched after | Trace, a controlled comparison and user-journey guard |
| Evidence and practice updates | learn → consolidate-lessons → distribution according to project authority | Observed incident and link, reusable rule, counterexample and checked upstream version |

For technical SEO choose engineering-craft's `technical-seo-audit`; for browser or server performance choose `web-performance-audit`. Stack-specific advice comes from the matched external skills, such as Vercel's React guidance. Project-specific URLs, evidence, credentials and deployment decisions belong in the project. Shared release briefings use [Delivery evidence](DELIVERY_EVIDENCE.md). No route expands the user's authority to deploy, dispatch agents, or modify an unrelated system.
