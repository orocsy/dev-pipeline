---
name: excalidraw-diagram-generator
description: Generate .excalidraw diagram files from natural language descriptions. Mandatory in Phase 2 (HLD diagrams: system context, container/service, deployment) and Phase 5 (LLD diagrams: sequence, ER/data model, component dependencies, state machine, API flow). Produces properly structured JSON files saved to .claude/diagrams/. If excalidraw MCP is connected, also renders + screenshots for visual verification. Falls back to .excalidraw JSON file only if MCP is unavailable.
---

# Excalidraw Diagram Generator Skill

## Activation Banner (print exactly once when this skill loads)

```
🔧 [dev-pipeline] skill: excalidraw-diagram-generator — diagram output active
   Generating .excalidraw files → .claude/diagrams/
   MCP: checking yctimlin/mcp_excalidraw connection...
```

After printing, check if `mcp_excalidraw` is in `~/.claude/settings.json mcpServers`. If yes, print:
```
   MCP: ✅ connected — iterative rendering enabled
```
If no:
```
   MCP: ⚠️  not connected — generating .excalidraw JSON files only (open in VS Code / excalidraw.com)
```

---

## When This Skill Fires

**Phase 2 (HLD) — MANDATORY, never skip:**
- System Context Diagram (who uses the system and what external systems it talks to)
- Container / Service Architecture Diagram (what services exist, how they connect, what tech each uses)
- Infrastructure / Deployment Diagram (where each service runs, how traffic flows, what managed services)

**Phase 5 (LLD) — MANDATORY for any feature that touches more than one module:**
- Sequence Diagram (for each key user flow in the feature — e.g. booking creation, payment processing)
- ER / Data Model Diagram (whenever a schema migration or new entity is involved)
- Component Dependency Diagram (which modules this MIU touches and their relationships)
- State Machine Diagram (when the feature introduces a new status field or multi-step state)
- API Flow Diagram (request/response path through services for each new endpoint)

**Trigger count rule:** A feature with 3 MIUs should have at least 2 diagrams. A feature with 6+ MIUs should have at least 4 diagrams. Diagrams are not optional documentation — they ARE the design.

---

## Diagram Type Reference

### 1. System Context (C4 Level 1)
Actors + system boundaries. Max 10 elements.
- Shapes: user → ellipse, your system → large rectangle (center), external system → rectangle
- Arrows show: "sends booking request", "processes payment", "sends email"
- Colors: your system = `#a5d8ff`, external = `#e9ecef`, user = `#b2f2bb`

### 2. Container / Service Architecture
Services + their communication channels. Max 15 elements.
- Each service = rectangle with label `Service Name\n[tech: Next.js / NestJS / PostgreSQL]`
- Arrows labeled with protocol: REST, GraphQL, WebSocket, queue, SQL
- Group related services in a dashed bounding box

### 3. Infrastructure / Deployment
Physical + logical hosting. Max 12 elements.
- Cloud regions as large rectangles
- Managed services (DB, queue, CDN) as parallelograms
- Traffic flow with Load Balancer → Service arrows
- Include: CDN, DNS, LB, compute, DB, cache, queue

### 4. Sequence Diagram
Time-ordered message flow between actors/services. Max 20 messages.
- Actors as vertical lines (rectangles at top)
- Messages as horizontal arrows, labeled with the call and return value
- Activation boxes on the receiving actor
- Use dashed arrows for async / event-driven calls

### 5. ER / Data Model
Entities and relationships. Max 15 entities.
- Each entity = rectangle with fields listed: `field: type [PK/FK/index]`
- Relationship arrows: `1---<` (one-to-many), `>---<` (many-to-many)
- Label FK relationships with the constraint name

### 6. Component Dependency
Module graph. Boxes = modules, arrows = imports/dependencies. Max 15 nodes.
- Direction: top = higher-level (UI/API), bottom = lower-level (DB/infra)
- Cyclic dependency = red arrow + label "CIRCULAR — needs fix"

### 7. State Machine
States + transitions for a status field. Max 12 states.
- States = rounded rectangles
- Start = filled circle, end = double circle
- Transitions = labeled arrows (event → action)
- Include: INITIAL, terminal states, error/cancelled paths

### 8. API Flow
Request lifecycle through the stack. Max 15 steps.
- Vertical: Client → Gateway → Service → DB/External
- Each box = layer, arrows = calls with method + path
- Include: auth check, validation, DB call, response shape

---

## JSON Output Format

All diagrams must conform to this schema. Save to `.claude/diagrams/<phase>-<type>-<slug>.excalidraw`.

```json
{
  "type": "excalidraw",
  "version": 2,
  "source": "https://excalidraw.com",
  "elements": [
    {
      "id": "unique-id-1",
      "type": "rectangle",
      "x": 100,
      "y": 100,
      "width": 200,
      "height": 80,
      "angle": 0,
      "strokeColor": "#1e1e1e",
      "backgroundColor": "#a5d8ff",
      "fillStyle": "solid",
      "strokeWidth": 2,
      "roughness": 1,
      "opacity": 100,
      "text": "Service Name\n[Next.js]",
      "fontSize": 18,
      "fontFamily": 5,
      "textAlign": "center",
      "verticalAlign": "middle"
    },
    {
      "id": "arrow-1",
      "type": "arrow",
      "x": 300,
      "y": 140,
      "width": 150,
      "height": 0,
      "points": [[0, 0], [150, 0]],
      "startBinding": {"elementId": "unique-id-1", "gap": 5, "focus": 0},
      "endBinding": {"elementId": "unique-id-2", "gap": 5, "focus": 0},
      "label": {"text": "REST /api/bookings", "fontSize": 14, "fontFamily": 5}
    }
  ],
  "appState": {
    "viewBackgroundColor": "#ffffff",
    "gridSize": 20
  },
  "files": {}
}
```

**Technical requirements (non-negotiable):**
- `fontFamily: 5` on ALL text elements (Excalifont — any other value renders incorrectly)
- Horizontal spacing: 200–300px between sibling elements
- Vertical spacing: 100–150px between rows
- Max 20 elements per diagram — split into two diagrams if more are needed
- Font size: 16–24px for labels, 12–14px for annotations
- Color palette: primary `#a5d8ff`, secondary `#b2f2bb`, emphasis `#ffd43b`, alert `#ffc9c9`, neutral `#e9ecef`

---

## MCP Rendering (when yctimlin/mcp_excalidraw is connected)

After generating the JSON file:

1. Announce: `🤖 [dev-pipeline] agent: excalidraw-renderer — rendering diagram for visual verification`
2. Call `create_view` or batch-create elements via the MCP tools
3. Take a screenshot via MCP `screenshot` tool
4. Inspect the screenshot: check that labels are readable, arrows point in the right direction, layout is not overlapping
5. If layout issues detected: adjust x/y coordinates and re-render (up to 2 iterations)
6. Save the final `.excalidraw` file with corrected coordinates

When MCP is NOT connected: generate the JSON file and print:
```
📄 Diagram saved: .claude/diagrams/<filename>.excalidraw
   Open in: VS Code (Excalidraw extension) or https://excalidraw.com (drag to drop)
```

Do NOT call `export_to_excalidraw_url` — this uploads to excalidraw.com servers. Local files only.

---

## Naming Convention

```
.claude/diagrams/
  hld-context-<feature-slug>.excalidraw
  hld-services-<feature-slug>.excalidraw
  hld-deployment-<feature-slug>.excalidraw
  lld-sequence-<flow-name>.excalidraw
  lld-er-<domain>.excalidraw
  lld-components-<module>.excalidraw
  lld-state-<entity>-<field>.excalidraw
  lld-api-<endpoint>.excalidraw
```

---

## Quality Gate

Before emitting the diagram as complete, verify:
- [ ] All text uses `fontFamily: 5`
- [ ] No element overlaps another
- [ ] All arrows have both startBinding and endBinding set
- [ ] Arrow labels describe the relationship/call (not generic "calls" or "uses")
- [ ] Color scheme matches palette
- [ ] File saved to `.claude/diagrams/`
- [ ] Filename follows naming convention
- [ ] If MCP connected: screenshot verified, no layout issues
