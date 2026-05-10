---
name: cloud-design-patterns
description: Architecture audit using 42 industry-standard cloud design patterns across reliability, performance, messaging, security, and deployment categories. FIRST HIT in Phase 2 (HLD) for every pipeline run. Evaluates proposed design against established patterns, selects the right ones, documents architectural decisions in an ADR. Never skipped — even backend-only features touch at least reliability and data patterns.
---

# Cloud Design Patterns — Architecture Audit Skill

## Activation Banner (print exactly once when this skill loads)

```
🔧 [dev-pipeline] skill: cloud-design-patterns — architecture audit active (Phase 2 HLD)
   Auditing against 42 industry patterns across reliability, performance, messaging, security, deployment.
```

---

## When This Skill Fires

- **Always** at Phase 2 (HLD) of `/dev-pipeline:pipeline` and `/dev-pipeline:update` — it is the FIRST step, before any design diagram or UI spec.
- `/dev-pipeline:init` for new projects — establishes the baseline architecture posture.
- Architecture-tier items in `/dev-pipeline:refactor` proposals.
- Any time the user says "design", "architecture", "how should we structure", "which pattern".

It does NOT fire for: hotfix flows, pure E2E test additions, dependency-only updates.

---

## What This Skill Does

Evaluates the proposed feature/change against the 42 patterns below. Output is an **Architecture Decision Record (ADR)** that:
1. Lists every pattern evaluated (chosen + rejected)
2. Explains WHY each chosen pattern fits this specific workload
3. Flags trade-offs and risks of each choice
4. Blocks G2 (design gate) if a chosen approach violates a pattern's hard constraints

This is an **audit**, not a suggestion list. If the proposed design uses a pattern incorrectly (e.g. CQRS without event sourcing in a write-heavy flow), the skill emits a G2 blocker and the user must resolve it before Phase 3.

---

## Pattern Reference (42 patterns — evaluate all relevant, skip clearly inapplicable)

### Reliability & Resilience (9)
| Pattern | Use when | Hard constraint |
|---|---|---|
| **Ambassador** | Offload cross-cutting concerns (retry, circuit breaker, logging) from service to a proxy | Do not put business logic in the ambassador |
| **Bulkhead** | Isolate failures — partition resources so one failure doesn't cascade | Requires resource quotas/limits per partition |
| **Circuit Breaker** | Prevent cascading failures to a degraded dependency | State must be shared across instances (not per-pod) |
| **Compensating Transaction** | Undo completed steps in a failed long-running workflow | Each compensating step must itself be idempotent |
| **Health Endpoint Monitoring** | Expose dedicated health check routes for infra/load balancer | Health endpoints must NOT be protected by auth |
| **Leader Election** | Coordinate a single active worker among multiple instances | Requires distributed lock (Redis/DB — not in-memory) |
| **Retry** | Handle transient failures with exponential backoff | NEVER retry non-idempotent operations without dedup |
| **Saga** | Manage distributed transactions across services | Each saga step must publish its outcome event |
| **Sequential Convoy** | Process ordered messages without blocking | Requires a message broker with per-key ordering |

### Performance (10)
| Pattern | Use when | Hard constraint |
|---|---|---|
| **Async Request-Reply** | Long-running operations that shouldn't block the HTTP response | Client must poll or receive webhook — never assume sync |
| **Cache-Aside** | Read-heavy data that is expensive to recompute | Cache invalidation must be explicit on writes |
| **CQRS** | Read and write models have divergent scaling needs | Do not apply to simple CRUD — adds significant complexity |
| **Index Table** | Secondary access patterns on non-primary-key fields | Secondary index cost in write amplification |
| **Materialized View** | Pre-computed aggregations for reporting queries | Staleness window must be defined and acceptable |
| **Priority Queue** | Different work items have different urgency | Prevents starvation of low-priority items — must have minimum throughput guarantee |
| **Queue-Based Load Leveling** | Smooth traffic spikes between producer and consumer | Queue depth must be monitored as a scaling signal |
| **Rate Limiting** | Protect downstream from being overwhelmed | Apply at the edge, not per-service |
| **Sharding** | Partition data to scale beyond single-node limits | Shard key choice is irreversible — validate carefully |
| **Throttling** | Degrade gracefully under sustained overload | Must communicate throttling to callers (429 + Retry-After) |

### Messaging & Integration (7)
| Pattern | Use when | Hard constraint |
|---|---|---|
| **Choreography** | Services react to events without a central orchestrator | Each service must handle event ordering and idempotency |
| **Claim Check** | Large message payloads in message queues | The claim (reference) must have the same TTL as the payload |
| **Competing Consumers** | Scale out message processing horizontally | Messages must be idempotent — any consumer may retry |
| **Messaging Bridge** | Connect disparate messaging systems | Adds a translation layer — failure here is a single point |
| **Pipes and Filters** | Chain processing steps independently | Each filter must be independently deployable and testable |
| **Publisher-Subscriber** | Decouple producers from consumers via a topic | At-least-once delivery — consumers must be idempotent |
| **Scheduler Agent Supervisor** | Coordinate multi-step workflows with failure recovery | Requires persistent state store for workflow progress |

### Architecture & Design (7)
| Pattern | Use when | Hard constraint |
|---|---|---|
| **Anti-Corruption Layer** | Integrate with a legacy or third-party system | Do not let external model concepts leak into your domain |
| **Backends for Frontends (BFF)** | Different clients (web/mobile/API) have different data needs | One BFF per client type — do not share BFFs across client types |
| **Gateway Aggregation** | Client needs data from multiple backend services in one call | Aggregator must not contain business logic |
| **Gateway Offloading** | Cross-cutting concerns (auth, rate limit, TLS) at the API layer | Never offload authorization logic — only authentication |
| **Gateway Routing** | Route requests to services based on path/header/domain | Do not use gateway routing to implement business rules |
| **Sidecar** | Attach supporting capabilities (logging, config, proxy) to a service without code changes | Sidecar lifecycle must be coupled to main container |
| **Strangler Fig** | Incrementally migrate from a legacy system | The facade must never call both old and new simultaneously for the same request |

### Deployment & Operational (5)
| Pattern | Use when | Hard constraint |
|---|---|---|
| **Compute Resource Consolidation** | Multiple small workloads can share infra without interference | Isolation requirements (security, perf) must be verified first |
| **Deployment Stamps** | Deploy independent copies per tenant/region | Stamp management (versioning, upgrade orchestration) adds ops overhead |
| **External Configuration Store** | Configuration shared across services or environments | Secrets must NEVER go into the config store — use secrets manager |
| **Geode** | Serve users from the geographically nearest deployment | Data residency and sovereignty rules apply per region |
| **Static Content Hosting** | Serve static assets directly from storage/CDN | CDN cache invalidation strategy must be defined |

### Security (3)
| Pattern | Use when | Hard constraint |
|---|---|---|
| **Federated Identity** | Delegate authentication to an external identity provider | Token validation must happen on every request — not cached |
| **Quarantine** | Validate and sanitize content before allowing it into the system | Quarantine failures must be logged with full content hash |
| **Valet Key** | Grant clients time-limited direct access to a resource (e.g. S3 pre-signed URL) | Valet key scope must be minimum-required — never wildcard |

### Event-Driven Architecture (1)
| Pattern | Use when | Hard constraint |
|---|---|---|
| **Event Sourcing** | Audit trail + ability to replay state is a first-class requirement | Events are immutable — never update or delete events |

---

## ADR Output Format

Write to `.claude/docs/adr-<phase>-<feature-slug>.md`:

```markdown
# ADR: <feature name>
Date: <iso>
Phase: 2 (HLD)
Author: dev-pipeline cloud-design-patterns skill

## Context
<1-paragraph summary of what the feature does and its non-functional requirements>

## Patterns Selected
| Pattern | Why chosen | Trade-off accepted |
|---|---|---|
| Circuit Breaker | Booking service calls payment provider — must tolerate payment provider outages | Adds complexity to API client layer |
| Cache-Aside | Booking availability is read 10:1 vs write — cache reduces DB load | Cache invalidation must fire on any booking mutation |

## Patterns Considered and Rejected
| Pattern | Why rejected |
|---|---|
| CQRS | Write volume is low — added complexity not justified |

## G2 Blockers (user must resolve before Phase 3)
- [ ] None / list specific blockers

## Architecture Decision
<2-3 paragraphs summarizing the chosen design posture>
```

---

## G2 Blocker Conditions

Emit a G2 blocker if ANY of these are true:
- Retry is proposed on a non-idempotent write without a deduplication key
- CQRS is proposed on a simple CRUD feature with no read/write model divergence
- Shared in-memory state is proposed for Leader Election or Circuit Breaker across multiple instances
- Auth secrets are stored in the External Configuration Store (not secrets manager)
- A Saga is proposed without a defined compensating transaction for each step

When blocking G2, state exactly: *"G2 BLOCKED: [reason]. Resolve this before approving Phase 3."*
