From MIU to Factory: A Phased, Gated, Assembly-Line Redesign of orocsy/dev-pipeline
TL;DR
Verdict on the current repo: dev-pipeline is unusually disciplined for a Claude Code plugin — 20 hard rules, 12 numbered phases, 4 gates (G1–G4), 8 specialised sub-agents, post-commit/pre-push enforcement, and the MIU concept itself — but it collapses seven distinct kinds of architectural thinking (high-level design, tech-stack trade-off, scaffolding, code-quality charter, contracts, skeletons, units) into a single "Phase 4: Architecture + MIU spec" gated by G3, then races into TDD at Phase 7. This is the "going too fast" the user identifies. The fix is not to add rules to CLAUDE.md; it is to split Phase 4 into four phases (Architect, Scaffolder, Contract Designer, Skeleton Builder), redefine the MIU as a much smaller "tiny single-purpose function" (target ≤ 25 LOC), and put a schema-validated artifact + structured-output gate between every pair.
The redesign in one line: Intake → Architect → Scaffolding → Interface Contracts → Module Skeletons → Unit Implementation → Assembly, with each phase emitting a Zod-validated JSON artifact, each transition guarded by a Reviewer Agent running an explicit checklist + automated checks, and a four-layer hybrid knowledge stack (LLM training → curated playbooks → live multi-source retrieval → feedback corpus) injected per-phase.
Most impactful single change to ship first: introduce Phase 3 "Interface Contracts" as a forced, code-free phase that produces only *.types.ts, *.contract.ts (Zod), and OpenAPI fragments — and forbid commands/implement.md from creating any file that isn't referenced by a previously-generated contract. This alone forces architect-to-implementer handoff to be carried by typed signatures, not prose, and unlocks every other improvement.
Part 1 — Repository Audit
1.1 What dev-pipeline currently is

orocsy/dev-pipeline is a Claude Code plugin distributed via a local marketplace symlink. Repo layout (from public README):

.claude-plugin/    plugin manifest
agents/            8 sub-agent .md files
commands/          slash-command definitions
skills/            owned skills (miu-methodology, project-detector, skill-router, …)
docs/              methodology notes (PHILOSOPHY.md cited extensively)
hooks/             session-start, pre-compact, session-stop, post-commit, pre-push
tools/             helper scripts
CLAUDE.md          512-line auto-loaded plugin instruction file
deps.json          v2 dependency manifest naming owned + external skills

Described as "Personal Claude Code plugin — methodology, commands, agents, skills for full-stack feature development. Decoupled sibling of spec-forge." Its sibling spec-forge is the new-project scaffolder; dev-pipeline owns existing-project feature work. 
github

1.2 Current pipeline flow (12 phases + 4 documented gates)

From the README and CLAUDE.md Pipeline Gate Enforcement tables:

Phase(s)	Owner command	Output	Gate
1 Requirements	/dev-pipeline:plan via requirements-analyst	Requirements doc	G1: "Requirements ready. Questions resolved?" 
github

2 Research	/dev-pipeline:plan	Context notes	—
3 Design check	/dev-pipeline:plan via design-checker	Design review	G2: "Design reviewed. Approve to continue to architecture?" 
github

4 Architecture + MIU	/dev-pipeline:plan via technical-architect+tech-lead	Architecture doc + MIU list	G3: "APPROVE ARCHITECTURE — I will not write code until you confirm." 
github

5–6 Module + test plan	/dev-pipeline:plan via tech-lead+test-planner	Module map + test scenarios	G4: "FINAL APPROVAL — after this I run autonomously to production." 
github

7 Implement (TDD)	/dev-pipeline:implement	Code	—
7.5/8.1/8.2/8.6 verify	verify-contract, verify-blast-radius, verify-visual, verify-traceability	Reports	hard-fail
8 Validate	/dev-pipeline:validate via validator	lint+tsc+unit+e2e+build	hard-fail
8.5 Review	/dev-pipeline:review	.claude/.last-reviewed-sha "blessing"	pre-push hook
9 Commit	/dev-pipeline:deliver	conventional commit	—
9.5 Conflict gate (Rule 15)	gh pr view --json mergeable	rebase if CONFLICTING	hard-fail
10 Push + PR	/dev-pipeline:deliver	PR URL	—
10.5 Browser E2E (Rule 16)	Playwright vs Vercel preview	Pass/fail	hard-fail
11–12 CI + deploy	/dev-pipeline:deliver	merged + deployed	—
12.5 Production smoke (Rule 17)	Playwright vs prod URLs	Triage commands on fail	post-deploy

The README mentions "G1–G5" but CLAUDE.md only documents G1–G4; G5 is referenced but not defined in CLAUDE.md (almost certainly in commands/pipeline.md, which our fetcher could not retrieve — flagged in Caveats). 
github

1.3 MIU — what it is

MIU = Minimum Implementable Unit. From CLAUDE.md MIU System Reference:

"MIU is the work-decomposition unit this plugin enforces. […] Two-level decomposition: Level 1 (Product Task) → Level 2 (Technical MIU). Never confuse. Every Technical MIU output MUST include the 8-field format from the skill. If an MIU description fits in one line, it's not detailed enough." 
github

So:

Level 1 Product Task = e.g. "Add Stripe billing."
Level 2 Technical MIU = sub-unit with 8 fields (exact schema lives in skills/miu-methodology/SKILL.md).
MIU is "done" when post-commit hook fires AUTO-REVIEW DIRECTIVE and assumption-checker passes (Rule 14).
1.4 The 8 agents

From the README:

Agent	Role	Model	Tools
requirements-analyst	Product Owner/BA	sonnet	Read-only 
github

technical-architect	Senior Architect	sonnet	Read-only 
github

tech-lead	Module & task breakdown	sonnet	Read-only 
github

test-planner	QA Lead	sonnet	Read-only 
github

validator	QA Engineer	haiku	Bash only 
github

review-analyzer	Review parser	sonnet	Read + gh 
github

design-checker	Design gatekeeper	haiku	Read-only 
github

skill-scout	Tooling specialist	haiku	Read + ls 
github

A recommendation committee, not an assembly line. Six of eight are read-only; only validator (haiku) can execute; there is no agent whose role is "write code" — that is left to the unrestricted Claude top-level session inside /dev-pipeline:implement.

1.5 The existing hybrid knowledge layer

deps.json (v2) lists:

8 owned skills: miu-methodology, project-detector, skill-router, prd-parser, spec-elicitor, code-refactor, cloud-design-patterns, excalidraw-diagram-generator. 
github
4 marketplaces: claude-plugins-official, local, developer-kit (community), fullstack-dev-skills (community, "66 skills as one plugin"). 
github
~17 external skills/plugins with trigger, usedBy, container, supersedes metadata (e.g. react-best-practices, nestjs-best-practices, typescript-pro, security-reviewer, playwright-expert).
2 MCPs: stitch-mcp, context7. 
github
hybridSkills[] that composes owned skills with public ones.

This is the foundation of the hybrid layer the user wants — already mixes owned playbooks, community skills, and live MCP retrieval. The user's request is essentially: make this layer the primary input to a phased pipeline rather than an ambient auto-activation system.

1.6 What the 20 rules tell us

Several rules are reactive scars from real incidents (the 2026-05-21 luxebook outage cited 5×):

Rule 10 — architect caught back-inferring architecture from a single config file.
Rule 11 — implementer caught adding per-input symptomatic fixes instead of fixing class.
Rule 13 — Claude continued forward on a corrected assumption.
Rule 18 — refactor deleted a load-bearing fallback whose doc-comment named the failure mode.
Rule 19 — Claude rewrote services-page.test.tsx to assert the opposite of what it previously asserted, giving false confidence. 
github

These are symptoms of a pipeline that hands the implementer too much latitude in one step — exactly the user's diagnosis.

1.7 Concrete weak points
#	Weak point	Citation	Why it matters
W1	Phase 4 fuses architecture + MIU breakdown	README "phases 1–6"; CLAUDE G3	Architect, scaffolder, contract designer, unit decomposer are 4 different roles producing 4 different artifacts — G3 approves them all at once
W2	No phase produces interface contracts (types, Zod, OpenAPI) standalone	No such phase in README phase list	Implementer at Phase 7 starts from prose, not signatures — Rules 18, 19 are inevitable consequences
W3	No phase produces compiling skeletons before logic	Phase 7 is "TDD" directly	Implementer must invent module boundaries while writing logic
W4	MIU is "minimum implementable" not "minimum testable in isolation"	CLAUDE.md MIU section	An MIU today is typically a full feature slice; should be a single pure function
W5	Scaffolding/code-quality charter is implicit via skill-router file-extension triggers	deps.json hybridSkills triggers	Lint config, folder layout, naming, test framework are decided after code exists
W6	Knowledge retrieval is reactive, not phase-targeted	skill-router/SKILL.md design phase rules	Architect doesn't get tradeoff-comparison material; Implementer doesn't get design-pattern templates; they share the same auto-activated context
W7	Code-quality goals not separated from functional at planning time	No "quality-lead" agent exists	The user's exact complaint
W8	All planning agents read-only sonnet; no agent writes artifact files	README Agents table	Top-level Claude is free to skip/reinterpret read-only recommendations; no schema-validated write boundary
W9	No feedback loop captures lessons in queryable form	.claude/instincts/, agent-events.jsonl are session-scoped	Rule 18's post-mortem ended up in prose in CLAUDE.md, not in retrievable form
W10	G5 referenced in README but not enumerated in CLAUDE.md	README "G1–G5"; CLAUDE.md table only G1–G4	Documentation drift

These ten points are the surface area this proposal targets.

Part 2 — Redesigned Architecture: the seven-phase assembly line
2.1 Top-level flow
Phase 0Intake
G0
Phase 1Architect
G1
Phase 2Scaffolding
G2
Phase 3InterfaceContracts
G3
Phase 4ModuleSkeletons
G4
Phase 5UnitImplementationMIUs in parallel
G5
Phase 6Assembly
G6
dev-pipeline:deliver

Each gate is schema-validated + automated-check + reviewer-agent-checklist. Refusal-to-advance is the default.

2.2 Phase 0 — Intake & Goal Decomposition
Agent: intake-orchestrator (sonnet, read + retrieval).
Input: user request, BRIEF.md if present, the existing .claude/docs/PROJECT_STATUS.md and ARCHITECTURE.md.
Output (artifacts/phase-0/goals.json):
ts
  z.object({
    requestId: z.string().uuid(),
    summary: z.string().min(20),
    functionalGoals: z.array(z.object({ id: z.string(), statement: z.string(), acceptance: z.array(z.string()).min(1) })).min(1),
    technicalGoals: z.array(z.object({ id: z.string(), statement: z.string(), rationale: z.string() })),
    qualityGoals: z.array(z.object({ id: z.string(), statement: z.string(), measurableCriterion: z.string() })),
    constraints: z.array(z.string()),
    nonGoals: z.array(z.string()),
    openQuestions: z.array(z.string()),
  })
Gate G0: schema validates; ≥ 1 functional + ≥ 1 technical + ≥ 1 quality goal (forces the user's three-axis split); zero openQuestions downstream; human confirmation.
2.3 Phase 1 — Architect
Agent: architect-agent (sonnet, curated + live retrieval).
Output (artifacts/phase-1/architecture.json):
ts
  z.object({
    stack: z.object({ runtime: z.enum(["node","bun","deno"]), language: z.literal("typescript"), framework: z.string(), packageManager: z.enum(["pnpm","npm","yarn","bun"]), versions: z.record(z.string(), z.string()) }),
    tradeoffs: z.array(z.object({
      decision: z.string(),
      options: z.array(z.object({ name: z.string(), pros: z.array(z.string()), cons: z.array(z.string()) })).min(2),
      chosen: z.string(),
      justification: z.string().min(80),
      sourcesConsulted: z.array(z.object({ source: z.string(), excerpt: z.string() })).min(2)
    })).min(1),
    boundaries: z.array(z.object({ id: z.string(), name: z.string(), responsibility: z.string(), publicSurface: z.string().describe("one-sentence interface promise — deep module per Ousterhout, A Philosophy of Software Design, Ch. 4 'Modules Should Be Deep'") })),
    dependencyGraph: z.array(z.tuple([z.string(), z.string()])),
    risks: z.array(z.object({ risk: z.string(), mitigation: z.string() })),
  })
Gate G1: schema validates; every chosen has ≥ 2 sourcesConsulted with verbatim excerpts (forces multi-source retrieval); publicSurface ≤ 200 chars (encourages deep modules with simple interfaces and rich implementation — Ousterhout's Ch. 4 thesis that "the most important technique for achieving deep modules is information hiding … each module should encapsulate a few pieces of knowledge, which represent design decisions"); dependency graph acyclic; Reviewer "why-X" checklist PASS; human approval. 
Milkov
2.4 Phase 2 — Scaffolding
Agent: scaffolding-agent (sonnet, write inside scaffolding allow-list only).
Output (real files): package.json, pnpm-workspace.yaml, tsconfig.base.json (strict, composite), ESLint+Prettier configs, .husky/pre-commit, vitest.config.ts, .github/workflows/ci.yml, empty apps/+packages/ per architecture boundaries, docs/CONVENTIONS.md, artifacts/phase-2/manifest.json.
Gate G2: pnpm install+typecheck+lint+test all green on empty project; layout matches a vetted reference — for React/Next.js seed, Robin Wieruch, "React Folder Structure Best Practices [2026]" (robinwieruch.de/react-folder-structure/, last updated May 5 2026): "From a single file to feature folders and a production monorepo: how to structure React projects with files, technical folders, and clean boundaries"; no business-logic files — Reviewer fails the gate if any file outside the allow-list appears.
2.5 Phase 3 — Interface Contracts (the new pivotal phase)
Agent: contract-designer-agent (sonnet, write only **/*.{types,contract,dto,schema}.ts + openapi/*.yaml).
Output: for every boundary:
*.types.ts — TypeScript type aliases + branded types + enums
*.contract.ts — Zod schemas (single source of truth — runtime + tests + OpenAPI)
*.errors.ts — discriminated-union error types
*.service.ts interface-only (bodies allowed to be throw new Error("not implemented"))
openapi/<boundary>.yaml for HTTP boundaries
Gate G3: pnpm typecheck green; OpenAPI validates against 3.1 spec; Zod schemas are strict (safeParse(undefined).success === false); Reviewer runs Ousterhout deep-module checklist; refusal-to-advance rule: Phase 4 may not create files that don't import from Phase-3 contracts (enforced via dependency-cruiser); human approval.
2.6 Phase 4 — Module Skeletons
Agent: skeleton-builder-agent (sonnet, must import from Phase-3 contracts).
Output: real files (*.service.ts, *.controller.ts, *.tsx) that compile but bodies are throw new Error("Pending MIU <id>"); dependency-graph.json; MIU manifest (artifacts/phase-4/mius.json):
ts
  z.array(z.object({
    id: z.string(),                              // MIU-0001
    signature: z.string(),
    module: z.string(),
    intent: z.string().max(280),
    inputs: z.string(),
    output: z.string(),
    contractRef: z.string(),
    dependsOn: z.array(z.string()),
    qualityGoals: z.array(z.string()),
    testCases: z.array(z.object({ name: z.string(), arrange: z.string(), assert: z.string() })).min(2),
    sizeBudget: z.number().int().max(25),        // LOC cap — the new "tiny"
    designPatternHint: z.string().optional(),
  }))
Gate G4: pnpm build green; every MIU sizeBudget ≤ 25; every MIU references a Phase-3 contract; every MIU reachable from a functional goal (traceability); dependency graph between MIUs acyclic; Reviewer runs multi-goal scoring rubric (Part 5.6); last human gate before parallel implementation.
2.7 Phase 5 — Unit-Level Implementation (the real MIUs)
Agent: unit-implementer-agent (sonnet for hard, haiku for trivial, routed by designPatternHint). Many parallel instances.
Input: one MIU + its contracts + relevant playbook entry.
Output: one method body + Vitest spec.
Constraints (hook-enforced): edit only files in MIU's module field; no new public exports; LOC delta ≤ sizeBudget; cannot modify any Phase-3 contract.
Gate G5 (per MIU, automatic): Vitest passes; mutation test (Stryker) ≥ 70 % (deters Rule-19 tautology); tsc --noEmit whole-repo green; ESLint --max-warnings 0; Reviewer diff-checklist.
Parallelism: MIUs with no dependsOn dispatched in parallel via Claude Code subagents / Agent Teams; topological scheduler.
2.8 Phase 6 — Assembly
Agent: assembler-agent (sonnet, writes only DI/composition root + integration tests).
Output: DI files; integration tests at module level and component level; smoke test; traceability.json mapping functionalGoal → contract → MIU → integration test → smoke test.
Gate G6: full pnpm build && pnpm test green; integration coverage ≥ 80 % of Phase-3 public surface; Playwright E2E (Rule 16) green against local preview; traceability matrix has zero unmapped goals; Reviewer PASS.
After G6, control returns to existing /dev-pipeline:deliver (Phases 9–12 + 9.5/10.5/12.5 unchanged).
2.9 The MIU redefined
	Current MIU	Redesigned MIU
Scope	Feature slice (controller + service + repo)	One pure function or one React component
LOC budget	Implicit, often > 100	Hard cap 25 LOC
Lives in	Free-text 8-field markdown	Schema-validated JSON
Contract source	Prose	*.contract.ts Zod schema referenced by contractRef
Goals addressed	Functional	≥ 1 functional + ≥ 1 technical + ≥ 1 quality (multi-goal scoring at G4)
Test obligation	"tests pass"	Tests and mutation-score ≥ 70 %
Parallelism	Sequential	Topologically parallel
2.10 Agent-role hierarchy
Knowledge Curatorcross-cutting
Reviewer Gate Agentcross-cutting
Intake Orchestrator
Architect
Scaffolding
Contract Designer
Skeleton Builder
Unit Impl #1
Unit Impl #2
Unit Impl #n
Assembler
Part 3 — Agent / Role Specifications
3.1 Common prompt-template skeleton (six fixed sections)
# Role           – who you are, what you OWN
# Inputs         – file paths + schemas to consume
# Knowledge Pack – auto-injected from playbooks/ + L3 retrieval
# Output Contract – Zod schema + paths to write
# Constraints    – file allow-list, forbidden ops, refusal conditions
# Hand-off       – next agent, gate to pass, where to write artifacts
3.2 Architect Agent (Phase 1)
Scope: choose stack, decompose into bounded contexts, surface trade-offs grounded in retrieved evidence.
Inputs: goals.json, prior architectures (L4), framework comparison docs (L3).
Outputs: architecture.json + architecture.md.
Retrieval: playbooks/architecture/tradeoffs/; context7 MCP for framework docs; web-fetch constrained to *.dev, github.com, framework docsites; GitHub-MCP topic:nextjs-app-router stars:>500 for exemplary repos.
Refusal: fewer than 2 sources cited per trade-off → must request more retrieval.
3.3 Scaffolding Agent (Phase 2)
Scope: realise conventions and layout from architecture.
Outputs: package.json, tsconfig.base.json, ESLint/Prettier, husky, CI workflow, empty dirs, docs/CONVENTIONS.md.
Refusal: any business-logic file in diff → self-reject.
3.4 Contract Designer Agent (Phase 3)
Scope: translate boundaries into types, Zod schemas, OpenAPI, unimplemented interfaces.
Constraints: allow-list of file extensions; bodies may only be throw new Error("not implemented").
3.5 Skeleton Builder Agent (Phase 4)
Scope: realise modules that compile but throw; emit MIU manifest.
Splitting rule: if a stub's intended implementation > 25 LOC, split the boundary into two MIUs.
3.6 Unit Implementer Agent (Phase 5)
Scope: implement exactly one MIU.
Parallelism: spawned one per ready MIU; orchestrator caps concurrency by token budget.
Tools: Vitest + the relevant skill (e.g. playwright-expert, security-reviewer from fullstack-dev-skills).
Refusal: any diff outside MIU's module → auto-reverted by post-tool hook.
3.7 Assembler Agent (Phase 6)
Scope: wire MIUs into modules, modules into components, components into product.
Outputs: DI/composition root, integration tests, smoke tests, traceability.json.
3.8 Reviewer / Gate Agent (cross-cutting)
Scope: run phase-specific checklist + automated checks, emit PASS/FAIL.
Output (review.json):
ts
  z.object({
    phase: z.number(),
    verdict: z.enum(["PASS","FAIL"]),
    findings: z.array(z.object({ severity: z.enum(["P1","P2","P3"]), check: z.string(), evidence: z.string(), fix: z.string().optional() })),
    automatedChecks: z.record(z.string(), z.boolean()),
  })
Rule: any P1 or ≥ 4 P2 → FAIL → route back to owning agent (reuses Rule 8's existing post-commit reviewer pattern).
3.9 Knowledge Curator Agent (cross-cutting)
Scope: maintain the four-layer knowledge stack — curate playbooks, refresh retrieval index, run retrospectives, demote stale entries.
Trigger: scheduled (existing dev-pipeline schedule skill, same mechanism Rule 9's refactor sweep uses).
Outputs: updated playbooks/*, updated deps.json hybridSkills[], weekly playbook-changelog.md.
Part 4 — The Hybrid Knowledge Layer
4.1 The four layers
Layer	What	Where	Refresh
L1 Base training	Sonnet 4.6 / Opus 4.7 default intuition	Inside the model	At model upgrade
L2 Curated playbooks	dev-pipeline-owned best practices per stack/pattern/phase	playbooks/	Weekly via Knowledge Curator
L3 Live retrieval	Multi-source: framework docs (context7), exemplary repos (github-mcp), expert blogs (web-fetch)	MCPs + URL allow-list	Per phase, per query
L4 Feedback corpus	Captured lessons (post-mortems, gate FAILs, retro notes)	retrospectives/*.md + retrospectives/index.json (embeddings)	After every G6 + every incident
4.2 Proposed folder structure
playbooks/
  architecture/
    tradeoffs/         auth-session-vs-jwt-vs-oauth.md, orm-prisma-vs-drizzle.md, monorepo-pnpm-vs-nx-vs-turborepo.md, ssr-vs-rsc-vs-csr.md
    patterns/          ports-and-adapters.md, cqrs-light.md, result-or-throw.md, branded-types.md
  scaffolding/
    nextjs-app-router/ folder-layout.md, eslint-config.cjs, tsconfig.base.json, vitest.config.ts
    nestjs-10/         module-structure.md, …
    pnpm-monorepo/     workspace-yaml.md, project-references.md
  contracts/           zod-patterns.md, zod-to-openapi.md, error-taxonomy.md, branded-id-types.md
  modules/             deep-modules-ousterhout.md, feature-folder.md, public-api-via-index-ts.md
  units/
    pure-function-templates/   hash-password.ts.tmpl, verify-token.ts.tmpl, …
    react-component-templates/ controlled-input.tsx.tmpl, …
  testing/             vitest-patterns.md, mutation-testing-stryker.md, contract-tests.md, playwright-e2e.md
  security/            auth-best-practices-2026.md, secrets-handling.md, rate-limiting.md
retrospectives/
  index.json           vector index for retrieval
  2026-05-21-luxebook-fallback.md  (already referenced from CLAUDE.md Rule 18)
4.3 Retrieval strategy
Phase	L1	L2 (which subdir)	L3 (which MCP)	L4
0 Intake	✓	tradeoffs index only	—	similar requests
1 Architect	✓	architecture/*	context7 framework docs + github-mcp exemplary repos + web-fetch whitelisted blogs (≥ 2 sources required)	past tradeoff decisions
2 Scaffolding	✓	scaffolding/<framework>/	—	scaffolding gotchas
3 Contracts	✓	contracts/*	context7 for chosen framework	✓
4 Skeletons	✓	modules/*	—	✓
5 Unit	✓ (heaviest)	units/* template + testing/vitest-patterns.md + topic playbook (e.g. security/auth-best-practices-2026.md)	optional context7 for API quirks	✓
6 Assembly	✓	testing/contract-tests.md, testing/playwright-e2e.md	—	✓

Multi-source merge rule: when ≥ 2 sources required (G1's sourcesConsulted.min(2)), sources must come from different domains (framework doc + community repo + optional expert blog). Reviewer fails the gate if all from the same site.

4.4 Injection mechanism

tools/inject-knowledge.ts:

ts
const pack = await composePack({
  phase: 1, goals: await readGoals(),
  archHints: ["authentication", "session"],  // NER on goals
  k: 6,
});
prompt = prompt.replace("{{KNOWLEDGE_PACK}}", pack.render());

composePack calls L2 (file globs), L3 (MCP queries), L4 (vector search over retrospectives/index.json), returns a token-budgeted Markdown blob with citations.

4.5 Feedback loop — "architect's evolved experience"

After every G6 PASS (and after every Rule-8 emergency override), the Knowledge Curator:

Retrospective: read agent-events.jsonl, gate-FAILs, override log → produce retrospectives/YYYY-MM-DD-<slug>.md with whatHappened, rootCause, playbookEdit, tags.
Playbook patch: open a PR against playbooks/ editing the most relevant entry; tag for human review.
Index refresh: re-embed updated playbooks into retrospectives/index.json.
4.6 What to seed for Node + TS + React

Concrete first-cut playbooks (sources cross-checked against authoritative references):

playbooks/scaffolding/pnpm-monorepo/ — pnpm workspaces + TypeScript project references with composite: true.
playbooks/scaffolding/nextjs-app-router/ — feature-folder + public-API-via-index.ts per Robin Wieruch, "React Folder Structure Best Practices [2026]" (robinwieruch.de/react-folder-structure/). 
robinwieruch
Robin Wieruch
playbooks/contracts/zod-patterns.md — strict Zod + safeParse + z.infer for end-to-end types.
playbooks/security/auth-best-practices-2026.md — per the OWASP Password Storage Cheat Sheet (cheatsheetseries.owasp.org/cheatsheets/Password_Storage_Cheat_Sheet.html): "Use Argon2id with a minimum configuration of 19 MiB of memory, an iteration count of 2, and 1 degree of parallelism"; RS256 JWT with short expiry, httpOnly+SameSite=Strict cookies, refresh-token rotation, denylist via Redis for revocation. 
OWASP Cheat Sheet Series + 2
playbooks/modules/deep-modules-ousterhout.md — John Ousterhout, A Philosophy of Software Design (Yaknyam Press), Ch. 4 "Modules Should Be Deep": small interface, rich implementation, information hiding ("each module should encapsulate a few pieces of knowledge, which represent design decisions"). 
Milkov
playbooks/testing/mutation-testing-stryker.md — threshold rationale.
playbooks/architecture/patterns/result-or-throw.md — Result<T,E> discriminated union + neverthrow.
Part 5 — Enforcement Mechanisms

The whole point: stop the LLM from "claiming best practices" without enforcing them.

5.1 Schema-validated outputs

Every phase emits a JSON file parsed by a Zod schema in the orchestrator. Failure to parse = automatic FAIL with a structured error message the owning agent consumes on retry. Same pattern OpenAI Structured Outputs + Vercel generateObject + Zod use today; converts "the model usually returns valid JSON" into a hard contract. 
DEV Community

5.2 Lint/typecheck/test/build gates between phases

After Phase 2, pnpm install && pnpm typecheck && pnpm lint && pnpm test must be green at every subsequent gate. Codebase is in deployable shape from Phase 2 onward — the "stays runnable" migration requirement.

5.3 Reviewer agent with explicit checklists

Per-phase checklists from Part 2 gate criteria, encoded as Markdown templates in agents/reviewer-checklists/phase-N.md, rendered into the Reviewer's prompt at runtime. Output (review.json) is schema-validated (Part 3.8).

5.4 "Why did you choose X?" — justification against curated playbook

For every architectural decision in architecture.json, schema requires chosen + justification.min(80) + sourcesConsulted.min(2). Reviewer additionally semantic-checks: does justification reference at least one playbook by name or one external source by URL? If not → FAIL.

This operationalises the user's complaint that "LLMs say 'follow best practices' but don't reason through them."

5.5 Refusal-to-advance

The orchestrator (LangGraph-style state machine in tools/orchestrator/) has no edge from PhaseN→PhaseN+1 that does not pass through GateN. A FAIL re-routes to the owning agent with the failure report attached; three consecutive FAILs halt and require human intervention.

5.6 Multi-goal scoring

At Phase 4 and Phase 5, every MIU is scored on three axes:

ts
z.object({ functional: z.number().int().min(0).max(2), technical: z.number().int().min(0).max(2), quality: z.number().int().min(0).max(2) })

Pass threshold: all three ≥ 1. An MIU scoring 0 on any axis is rejected — forcing the implementer to explicitly satisfy code-quality goals (testability, logging, rate-limiting, etc.).

5.7 Existing dev-pipeline enforcement we keep
Post-commit AUTO-REVIEW DIRECTIVE (Rule 2) — still fires after Phase 5 MIU commits. 
github
Pre-push bless-file (.claude/.last-reviewed-sha, Rule 8) — still gates push at Phase 6→Deliver. 
github
Conflict gate 9.5, browser E2E 10.5, prod smoke 12.5 — unchanged.
Assumption-checker agent (Rule 14) — promoted to Reviewer Agent's first sub-check at every gate.
Part 6 — Worked Example: Authentication
Phase 0 — Goals (artifacts/phase-0/goals.json)
json
{
  "requestId": "req-2026-05-26-001",
  "summary": "Add email/password authentication with session management to the Next.js admin app.",
  "functionalGoals": [
    {"id":"F1","statement":"User can sign up with email + password","acceptance":["POST /auth/signup returns 201 with session cookie","email uniqueness enforced"]},
    {"id":"F2","statement":"User can log in","acceptance":["POST /auth/login returns 200 with session cookie","wrong password returns 401"]},
    {"id":"F3","statement":"User can log out","acceptance":["POST /auth/logout invalidates session"]},
    {"id":"F4","statement":"User can request password reset","acceptance":["POST /auth/forgot-password sends email","token expires in 15 min"]}
  ],
  "technicalGoals": [
    {"id":"T1","statement":"Stateless verification via JWT access + opaque refresh","rationale":"horizontal scaling without shared session store on read paths"},
    {"id":"T2","statement":"Argon2id for password hashing per OWASP Password Storage Cheat Sheet (m=19456, t=2, p=1)","rationale":"current OWASP minimum recommendation"},
    {"id":"T3","statement":"httpOnly + SameSite=Strict + Secure cookies","rationale":"prevents XSS-stealing"},
    {"id":"T4","statement":"Refresh-token rotation with Redis denylist","rationale":"immediate revocation on logout"}
  ],
  "qualityGoals": [
    {"id":"Q1","statement":"Login rate-limited to 5 attempts / 15 min / IP","measurableCriterion":"6th attempt returns 429"},
    {"id":"Q2","statement":"All auth events logged with userId + ip + ua","measurableCriterion":"audit log row per auth action"},
    {"id":"Q3","statement":"No plaintext secrets in code or .env.example","measurableCriterion":"gitleaks scan green"},
    {"id":"Q4","statement":"Every public function has unit test with ≥70% mutation score","measurableCriterion":"stryker report"}
  ],
  "constraints":["Postgres already provisioned","Redis available"],
  "nonGoals":["OAuth / social login","MFA (v2)"],
  "openQuestions":[]
}
Phase 1 — Architecture (architecture.json, abridged)
json
{
  "stack":{"runtime":"node","language":"typescript","framework":"nextjs-15-app-router","packageManager":"pnpm","versions":{"next":"15.0.0","typescript":"5.5.0"}},
  "tradeoffs":[{
    "decision":"Token strategy for the access path",
    "options":[
      {"name":"Server-side sessions in Redis","pros":["instant revocation","small payload"],"cons":["read-path Redis hit","stickier scaling"]},
      {"name":"Stateless JWT","pros":["no shared store on read","CDN cache friendly"],"cons":["revocation latency","payload size"]},
      {"name":"Hybrid: short-lived JWT access + opaque refresh in Redis with rotation","pros":["best of both","industry standard 2026"],"cons":["two flows"]}
    ],
    "chosen":"Hybrid: short-lived JWT access + opaque refresh in Redis with rotation",
    "justification":"T1 + T4 explicitly require stateless verification on the hot path AND immediate revocation. The hybrid pattern is recommended by 2026 industry guides and matches the rotation+denylist pattern. Access TTL: 15 min; refresh TTL: 14 days, rotated on each use.",
    "sourcesConsulted":[
      {"source":"workos.com/blog/nodejs-authentication-guide-2026","excerpt":"Stateless (JWT-based) … Stateful (session-based) … Both approaches are valid."}, 
      {"source":"authgear.com/post/nodejs-security-best-practices","excerpt":"Short expiry + refresh rotation: Keep access tokens very short-lived and rotate refresh tokens on each use, invalidating the old one immediately."} 
    ]
  }],
  "boundaries":[
    {"id":"B-auth-domain","name":"@app/auth-domain","responsibility":"Pure auth logic: password hashing, token signing/verifying, session lifecycle","publicSurface":"hashPassword, verifyPassword, signAccessToken, verifyAccessToken, issueRefreshToken, rotateRefreshToken, revokeRefreshToken"},
    {"id":"B-auth-http","name":"@app/auth-http","responsibility":"HTTP adapter — Next.js route handlers","publicSurface":"POST /auth/signup, /auth/login, /auth/logout, /auth/refresh, /auth/forgot-password"},
    {"id":"B-auth-infra","name":"@app/auth-infra","responsibility":"Postgres user repo + Redis token store","publicSurface":"UserRepository, TokenStore"},
    {"id":"B-auth-middleware","name":"@app/auth-middleware","responsibility":"Edge middleware verifying access token","publicSurface":"withAuth(handler)"}
  ],
  "dependencyGraph":[["B-auth-http","B-auth-domain"],["B-auth-domain","B-auth-infra"],["B-auth-middleware","B-auth-domain"]],
  "risks":[{"risk":"Argon2 native build on serverless","mitigation":"use @node-rs/argon2 (pure napi)"}]
}
Phase 2 — Scaffolding

pnpm-workspace.yaml + packages/auth-{domain,http,infra,middleware}/ empty with package.json + tsconfig.json. ESLint import/no-restricted-paths enforces auth-domain cannot import from auth-infra (ports-and-adapters). CI green on empty repo.

Phase 3 — Interface Contracts
ts
// packages/auth-domain/src/types.ts
export type Email = string & { readonly __brand: "Email" };
export type UserId = string & { readonly __brand: "UserId" };
export type HashedPassword = string & { readonly __brand: "HashedPassword" };
export interface User { id: UserId; email: Email; passwordHash: HashedPassword; createdAt: Date; }
export interface AccessTokenClaims { sub: UserId; iat: number; exp: number; }
export interface RefreshToken { id: string; userId: UserId; expiresAt: Date; revokedAt: Date | null; }
ts
// packages/auth-domain/src/contract.ts
import { z } from "zod";
export const EmailSchema = z.string().email().brand<"Email">();
export const SignupInputSchema = z.object({
  email: EmailSchema,
  password: z.string().min(12).max(128),
});
export const LoginInputSchema = SignupInputSchema;
export type SignupInput = z.infer<typeof SignupInputSchema>;
export type LoginInput = z.infer<typeof LoginInputSchema>;
ts
// packages/auth-domain/src/errors.ts
export type AuthError =
  | { kind: "EmailAlreadyExists" }
  | { kind: "InvalidCredentials" }
  | { kind: "TokenExpired" }
  | { kind: "TokenRevoked" }
  | { kind: "RateLimited"; retryAfterSeconds: number };
ts
// packages/auth-domain/src/auth.service.ts — interface only
import type { Result } from "neverthrow";
import { AuthError } from "./errors";
import { User, AccessTokenClaims } from "./types";
import { SignupInput, LoginInput } from "./contract";

export interface AuthService {
  signup(input: SignupInput): Promise<Result<{ user: User; accessToken: string; refreshToken: string }, AuthError>>;
  login (input: LoginInput ): Promise<Result<{ user: User; accessToken: string; refreshToken: string }, AuthError>>;
  logout(refreshTokenId: string): Promise<Result<void, AuthError>>;
  verifyAccess(token: string): Promise<Result<AccessTokenClaims, AuthError>>;
  rotateRefresh(refreshTokenId: string): Promise<Result<{ accessToken: string; refreshToken: string }, AuthError>>;
}

OpenAPI fragment auto-generated by zod-to-openapi. pnpm typecheck + pnpm build green (no implementations yet).

Phase 4 — Module Skeletons + MIU manifest
ts
// packages/auth-domain/src/password.ts
export async function hashPassword(plain: string): Promise<HashedPassword> {
  throw new Error("Pending MIU-0001");
}
export async function verifyPassword(plain: string, hash: HashedPassword): Promise<boolean> {
  throw new Error("Pending MIU-0002");
}

artifacts/phase-4/mius.json (excerpt):

json
[
  {"id":"MIU-0001","signature":"hashPassword(plain: string): Promise<HashedPassword>","module":"packages/auth-domain/src/password.ts","intent":"Argon2id hash a plaintext password with OWASP Password Storage Cheat Sheet minimum parameters (m=19456, t=2, p=1).","inputs":"plain: string","output":"Promise<HashedPassword>","contractRef":"packages/auth-domain/src/types.ts","dependsOn":[],"qualityGoals":["Q3","Q4"],"testCases":[{"name":"produces different hashes for same input (salted)","arrange":"plain='hunter2'","assert":"two calls produce different hashes"},{"name":"output verifies","arrange":"h=hashPassword('hunter2')","assert":"verifyPassword('hunter2',h)===true"}],"sizeBudget":12,"designPatternHint":"playbooks/security/auth-best-practices-2026.md#argon2id"},
  {"id":"MIU-0002","signature":"verifyPassword(plain: string, hash: HashedPassword): Promise<boolean>","module":"packages/auth-domain/src/password.ts","intent":"Constant-time verification.","inputs":"plain, hash","output":"Promise<boolean>","contractRef":"packages/auth-domain/src/types.ts","dependsOn":[],"qualityGoals":["Q3","Q4"],"testCases":[{"name":"correct verifies","arrange":"h=hashPassword('hunter2')","assert":"verifyPassword('hunter2',h)===true"},{"name":"wrong fails","arrange":"h=hashPassword('hunter2')","assert":"verifyPassword('wrong',h)===false"}],"sizeBudget":10,"designPatternHint":"playbooks/security/auth-best-practices-2026.md#argon2id"}
]
Phase 5 — Unit Implementation (parallel)

MIU-0001 and MIU-0002 have no dependsOn → dispatched in parallel.

ts
// MIU-0001 implementation (12 LOC, within budget)
// Parameters match OWASP Password Storage Cheat Sheet minimum for Argon2id: m=19456 KiB (19 MiB), t=2, p=1.
import { hash as argon2hash } from "@node-rs/argon2";
import type { HashedPassword } from "./types";
const ARGON2_OPTS = { memoryCost: 19456, timeCost: 2, parallelism: 1 } as const;
export async function hashPassword(plain: string): Promise<HashedPassword> {
  if (plain.length < 12) throw new Error("password too short");
  return (await argon2hash(plain, ARGON2_OPTS)) as HashedPassword;
}
ts
// MIU-0001 tests (Vitest)
import { describe, it, expect } from "vitest";
import { hashPassword, verifyPassword } from "./password";

describe("hashPassword", () => {
  it("produces different hashes for same input (salted)", async () => {
    const a = await hashPassword("correcthorsebattery");
    const b = await hashPassword("correcthorsebattery");
    expect(a).not.toBe(b);
  });
  it("rejects short passwords", async () => {
    await expect(hashPassword("short")).rejects.toThrow();
  });
});

Mutation testing via Stryker on these 12 lines exercises the length-check branch and the option object → ≥ 70 % mutation score achievable → G5 PASS. Similar small MIUs follow: signAccessToken, verifyAccessToken, issueRefreshToken, rotateRefreshToken, revokeRefreshToken, each ≤ 25 LOC.

Phase 6 — Assembly
ts
// apps/admin/src/lib/auth/composition.ts
export const authService: AuthService = makeAuthService({
  userRepo: makePgUserRepo(db),
  tokenStore: makeRedisTokenStore(redis),
  clock: () => new Date(),
  hashPassword, verifyPassword,
  signAccessToken, verifyAccessToken,
  issueRefreshToken, rotateRefreshToken, revokeRefreshToken,
});

Integration tests use real Postgres + Redis (testcontainers). E2E (Playwright) hits /auth/signup → /auth/login → protected page → /auth/logout against the local preview. traceability.json maps every functional goal F1–F4 to ≥ 1 integration + ≥ 1 E2E spec. G6 PASS → control returns to existing /dev-pipeline:deliver (Phases 9–12 unchanged).

Part 7 — Migration Path from Current dev-pipeline

Concrete, ordered, runnable. Repo stays shippable at every step.

Step 0 — Keep & rename for clarity (no functional change)

Keep all existing agents, commands, hooks, skills, CLAUDE.md rules. Rename current numbered phases internally as "v1 path" so they coexist with v2.

Step 1 — Add orchestrator scaffolding (new code, no behaviour change)
New folder tools/orchestrator/: small TypeScript LangGraph-style state machine (LangGraph, XState, or 200-line custom). Nodes = phases; edges = gates; state = artifact JSON.
New artifacts/ (gitignored except .gitkeep), schemas/ (Zod schemas).
New command /dev-pipeline:pipeline-v2. Keep /dev-pipeline:pipeline (v1) untouched.
Step 2 — Add the missing agents
agents/architect-agent.md (extends technical-architect.md)
agents/scaffolding-agent.md
agents/contract-designer-agent.md
agents/skeleton-builder-agent.md
agents/unit-implementer-agent.md
agents/assembler-agent.md
agents/reviewer-gate-agent.md (generalises Rule 8's parallel reviewers)
agents/knowledge-curator-agent.md
Existing requirements-analyst, test-planner, validator, review-analyzer, design-checker, skill-scout remain as helpers.
Step 3 — Re-author the MIU skill

Rewrite skills/miu-methodology/SKILL.md with the 25-LOC budget + Zod schema from Part 2.6. Add a supersedes note: "v1 MIU = feature slice; v2 MIU = unit." Seed skills/miu-methodology/examples/ with the auth worked example.

Step 4 — Seed the playbooks

Create playbooks/ per Part 4.2. Initial seed: 6 playbooks (auth, monorepo scaffolding, deep modules, Zod patterns, mutation testing, Result-or-throw). Add playbooks/INDEX.md enumerating phase→playbook routing. Add tools/inject-knowledge.ts.

Step 5 — Wire the schema-validated gates

For each gate G0–G6, add tools/gates/gate-N.ts that reads artifacts/phase-N/*.json, parses with Zod, runs automated checks (tsc/eslint/vitest/mutation-test/dependency-cruiser), invokes Reviewer Agent, exits 0/1. Wire into tools/orchestrator/ edges. Wire pre-push hook to refuse pushes whose artifacts/phase-6/review.json.verdict !== "PASS" — replaces/extends .last-reviewed-sha mechanism.

Step 6 — Migrate verify-* commands
verify-contract → fold into G3 (Phase 3 contracts are canonical).
verify-blast-radius → keep as cross-cutting tool invoked by G5 + G6.
verify-visual → fold into G6's Playwright run.
verify-traceability → fold into G6's traceability.json validation.
Step 7 — Migrate /dev-pipeline:deliver

No change to delivery flow itself. Change entry condition: requires artifacts/phase-6/review.json.verdict === "PASS" (in addition to .last-reviewed-sha). Conflict gate 9.5, E2E 10.5, prod smoke 12.5 unchanged.

Step 8 — Cut over

Set /dev-pipeline:pipeline to dispatch v2 by default, --v1 flag falls back. Update CLAUDE.md Mandatory Workflow Routing to route NEW_FEATURE to v2. Update Pipeline Gate Enforcement table to list G0–G6 and explicitly document G5 (the previously-undocumented gate from W10).

Step 9 — Operate the feedback loop

After every G6 PASS, Knowledge Curator opens a small playbook PR. After every override (Rule 8's REVIEWED=1, Rule 14 cross-check failures), it must create a retrospectives/YYYY-MM-DD-*.md entry within the same session.

What to keep / refactor / add — at a glance
	Keep	Refactor	Add
CLAUDE.md	All 20 rules	Replace G1–G4 table with G0–G6; add MIU-v2 cross-ref	"Phase-to-agent ownership map" section
agents/	All 8 existing	technical-architect → expand to Architect Agent spec	7 new agents (scaffolding, contract, skeleton, unit, assembler, reviewer-gate, knowledge-curator)
commands/	deliver, validate, review, verify-* (fold into gates)	plan splits or becomes wrapper; implement becomes orchestrator entry	pipeline-v2, intake, architect, scaffold, contracts, skeletons, units, assemble
skills/	project-detector, skill-router, prd-parser, spec-elicitor, excalidraw-diagram-generator	miu-methodology rewritten with 25-LOC unit definition	—
Hooks	All existing	pre-push reads artifacts/phase-6/review.json	—
New folders	—	—	playbooks/, retrospectives/, schemas/, artifacts/, tools/orchestrator/, tools/gates/, tools/inject-knowledge.ts
deps.json	Existing structure	hybridSkills[] extended with phase routing	New playbooks[] index
Recommendations

Staged, with the threshold that changes each:

Within 1 week — ship Phase 3 (Interface Contracts) as a standalone command. Even before the full redesign, forbidding /dev-pipeline:implement from writing any file not preceded by *.contract.ts / *.types.ts is the highest-ROI move. Escalate if: ≥ 30 % reduction in P1 findings at the existing Phase 8.5 review gate over two weeks.
Within 2 weeks — rewrite skills/miu-methodology/SKILL.md with the 25-LOC unit + Zod 8-field format. Threshold: average MIU size in mius.json ≤ 30 LOC across the next 10 features.
Within 1 month — stand up playbooks/ with the six seed entries + tools/inject-knowledge.ts. Threshold: every Phase-1 architecture.json has ≥ 2 sourcesConsulted; every Phase-5 implementation cites the design-pattern playbook used.
Within 6 weeks — wire the full G0–G6 orchestrator behind /dev-pipeline:pipeline-v2 in shadow mode (both v1 and v2 produce artefacts; v1 still ships). Cut over when: v2 produces equal-or-fewer review FAILs than v1 over 5 consecutive features.
Within 3 months — turn on Knowledge Curator's automatic retrospective PRs. Threshold: ≥ 1 playbook edit lands per incident.
Re-evaluate at 6 months: if mutation scores plateau < 70 %, raise unit-implementer to Opus 4.7 for hard MIUs; if Architect's sourcesConsulted are repeatedly from the same domain, expand the L3 retrieval allow-list.
Caveats
Files we could not retrieve verbatim (fetcher's URL-permission model blocked them): skills/miu-methodology/SKILL.md (the exact 8-field format), agents/technical-architect.md, agents/requirements-analyst.md, agents/tech-lead.md, commands/pipeline.md (where G5 is presumably defined), commands/plan.md, commands/implement.md, docs/PHILOSOPHY.md §§7–13. Claims about those files in Part 1 are reconstructed from public README, CLAUDE.md, and deps.json v2, which we did fetch verbatim. The redesign in Parts 2–7 does not depend on their internals — it is a superset.
G5 is referenced in README but not enumerated in CLAUDE.md. Most likely the pre-delivery bless-file gate (Rule 8), but flagged as documentation drift to verify against commands/pipeline.md.
External tools cited (LangGraph, Zod, Stryker, dependency-cruiser, @node-rs/argon2, neverthrow, Vitest, Playwright, zod-to-openapi) are stable as of May 2026 but versions move; pin in package.json and treat the playbook seeds as living docs.
The full seven-phase flow is heavy for small enhancements. Keep /dev-pipeline:update and /dev-pipeline:fix as lightweight paths that invoke only Phases 3 + 5 + 6.
Cost. Multi-agent pipelines burn tokens. Per "Code in Harmony: Evaluating Multi-Agent Frameworks" (anonymous, OpenReview, openreview.net/pdf?id=URUMBfrHFy), "Large agent groups such as MetaGPT and ChatDev introduce high communication costs, often exceeding $10 per HumanEval task, due to many serial messages being billed and processed." Mitigations baked in: haiku for Reviewer automated checks; sonnet only where reasoning depth pays; Opus only on Architect for hard tradeoffs and on Unit Implementer for hard MIUs. If > 3× v1 baseline after 4 weeks, downshift Reviewer to haiku and shorten playbook injection. 
OpenReview
The redesign does not yet address update, refactor, hotfix flows — preserved as lightweight escape hatches per the current CLAUDE.md routing table. Their "tiny-MIU" equivalents are follow-up work.