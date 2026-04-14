# CadFlow Architecture Decision Records — Summary

## ADR Summary Matrix

| ADR | Key Decision | Primary Trade-off | Confidence |
|-----|-------------|-------------------|------------|
| **001: Product Scope** | Tiered MVP: core SSR modeling + CFD preprocessing (surface naming, defeaturing, domain creation, watertight validation) | Defers sweep/loft to V1.1, assemblies to V2 | High |
| **002: UI Design** | Hybrid agentic layout: left intent tree + center 3D viewport + right properties + bottom chat/code + escalating AI autonomy | UI complexity from mixed-initiative patterns + progressive disclosure | High |
| **003: Frontend Stack** | React + TypeScript + Three.js (R3F) + shadcn/ui + Zustand (UI) + XState (workflows) + server-side geometry | React's runtime overhead (mitigated by R3F for 3D) | High |
| **004: Backend Architecture** | Modular monolith (FastAPI) + isolated geometry workers (subprocess pool) + REST/WebSocket/SSE protocol mix | Worker communication latency (~10-50ms); single-language (Python) backend | High |
| **005: Agentic Workflow** | ~20 structured tools with progressive autonomy (Suggest → Propose → Execute → Autonomous) + preview-before-apply + transaction undo | Preview doubles geometry computation; tool schema maintenance overhead | Medium-High |
| **006: Testing Strategy** | Adapted 4-layer pyramid (deterministic + replay + benchmark + judgment) + BRepCheck_Analyzer in all tests + Playwright visual regression | LLM test infrastructure overhead; visual regression flakiness | High |
| **007: Dev Process** | ADR-driven, TDD-first, AI-augmented; pnpm monorepo + Turborepo; GitHub Flow + Conventional Commits; CLAUDE.md conventions | Process overhead; AI dependency for velocity | High |
| **008: Data Model** | Intent graph as JSON (primary); BREP cache per node; append-only event log; JSON files → PostgreSQL JSONB migration path | JSON files limit concurrency in Phase 1; BREP cache invalidation complexity | High |
| **009: CFD Preprocessing** | Smart geometry prep + mesher integration (not built-in meshing); surface naming via intent graph metadata + CadQuery selectors → STL solid names / GMSH Physical Groups | No built-in meshing in V1; selector ambiguity risk | High |
| **010: Security** | Layered defense-in-depth: gVisor/Firecracker + nsjail + process isolation + code whitelist + resource limits (2 threads, 2GB, 60s) | Multiple layers add configuration complexity; gVisor I/O overhead | Medium-High |
| **011: Billing** | Tiered subscription + credit-based AI/compute usage; Stripe billing; reserve-commit cost control; free tier with upgrade triggers | Credit system complexity; Stripe integration effort | Medium |

## Dependency Graph

```
ADR-001 (Product Scope)
  ├──→ ADR-002 (UI Design)
  ├──→ ADR-003 (Frontend Stack)
  ├──→ ADR-004 (Backend Architecture)
  ├──→ ADR-005 (Agentic Workflow)
  ├──→ ADR-008 (Data Model)
  └──→ ADR-009 (CFD Preprocessing)

ADR-002 (UI Design)
  └──→ ADR-003 (Frontend Stack)

ADR-003 (Frontend Stack)
  └──→ ADR-004 (Backend Architecture) [consumes geometry via WebSocket]

ADR-004 (Backend Architecture)
  ├──→ ADR-005 (Agentic Workflow) [Claude SDK integration]
  ├──→ ADR-008 (Data Model) [PostgreSQL JSONB]
  └──→ ADR-010 (Security) [worker sandboxing]

ADR-005 (Agentic Workflow)
  ├──→ ADR-009 (CFD Preprocessing) [CFD-specific tools]
  └──→ ADR-010 (Security) [sandboxed code execution]

ADR-006 (Testing Strategy)
  ├── depends on ADR-003 (what to test in frontend)
  ├── depends on ADR-004 (what to test in backend)
  └── depends on ADR-005 (how to test agent)

ADR-007 (Dev Process)
  └── cross-cutting: informs all other ADRs

ADR-008 (Data Model)
  └──→ ADR-009 (CFD Preprocessing) [surface group metadata]

ADR-010 (Security)
  └──→ ADR-011 (Billing) [cost control feeds into billing]
```

### Simplified Dependency Layers

```
Layer 1 (Foundation):  ADR-001 (Scope) + ADR-007 (Process)
Layer 2 (Architecture): ADR-003 (Frontend) + ADR-004 (Backend) + ADR-008 (Data Model)
Layer 3 (Intelligence): ADR-002 (UI) + ADR-005 (Agent) + ADR-009 (CFD)
Layer 4 (Operations):  ADR-006 (Testing) + ADR-010 (Security) + ADR-011 (Billing)
```

## Open Questions

### Architecture

1. ~~**Build123d vs CadQuery:**~~ **Resolved:** Stick with CadQuery for V1. The LLM training data advantage is decisive (Text-to-CadQuery paper, 69.3% exact match). The intent graph abstracts over the DSL, so switching later is feasible. Accept build123d objects at the OCP level for interop.

2. ~~**Client-side geometry for lightweight operations:**~~ **Resolved:** Yes, hybrid architecture. Use OpenCascade.js in a Web Worker for lightweight read-only operations (measurements, clipping, simple preview) while server handles heavy computation (booleans, complex features, CFD preprocessing). Requires careful memory management (.delete() discipline) and a ~10-30MB WASM bundle (lazy-loaded after initial app render).

3. ~~**Yjs CRDT from day one:**~~ **Resolved:** No — start with plain JSON for V1 (per ADR-008). Keep the intent graph schema Yjs-compatible (flat maps of objects, no deeply nested structures) so migration to Yjs is a data-layer swap when collaboration is needed. Yjs adds complexity before there's a use case.

### Product

4. ~~**Escape hatch scope:**~~ **Resolved:** Middle ground. CadQuery is the primary API for all intent graph operations. A special `custom_code` node type accepts raw Python/OCP code as a black box with defined inputs (upstream BREP shapes) and outputs (resulting shape). Custom code nodes are opaque to the graph — not agent-editable, not parameter-diffable, not previewable. This isolates escape-hatch complexity from the clean intent graph.

5. ~~**STL import and repair:**~~ **Resolved:** Include in V1. STL import via OCP's `StlAPI_Reader` + mesh repair (sewing, hole filling, normal fixing) completes the "import → prep → export" CFD workflow from day one. Accept that STL→BREP conversion is lossy — position it as a mesh repair/export tool, not a parametric modeling entry point. Add to ADR-001 V1 MVP scope and ADR-009 repair operations.

6. ~~**Meshing preview priority:**~~ **Resolved:** Keep GMSH API integration at V1.1. V1 already has a strong CFD story (surface naming + defeaturing + STL import/repair + domain creation + named export). Users can call GMSH externally on exported STEP/STL. Ship V1 sooner, add integrated meshing in a fast V1.1 follow-up.

### Agent

7. ~~**Multi-view render generation cost:**~~ **Resolved:** Adaptive approach. Default to text-only topology summaries (zero latency) for most interactions. Agent can request renders on demand via a `cad_query_render(views)` tool when spatial context is needed. The agent decides based on the nature of the request.

8. ~~**Agent tool granularity:**~~ **Resolved:** Start with ~20 tools as defined in ADR-005. Use Claude's `ToolSearch` with `defer_loading: true` to avoid context bloat. Track tool usage analytics from day one. Adjust after real user testing — merge underused tools, split overloaded ones. This is a living decision, not a fixed number.

9. ~~**Fine-tuning vs prompting:**~~ **Resolved:** Claude-only for V1. Single model, single API, simpler architecture. Well-designed tools + CadQuery docs in context should suffice. Revisit fine-tuning when per-user AI costs are too high at scale or Claude's CadQuery generation quality hits a ceiling. The tool-use architecture makes swapping in a specialist model later straightforward.

### Operations

10. ~~**gVisor vs Firecracker for Phase 1:**~~ **Resolved:** gVisor for Phase 1. OCI-compatible (`--runtime=runsc`), minimal ops change, native GKE support. 10-30% I/O overhead is negligible for CPU-bound geometry operations. Sufficient isolation for Phase 1 (accidental damage from AI code, not targeted attacks). Move to Firecracker in Phase 2 if multi-tenant scale demands it.

11. ~~**Billing model validation:**~~ **Deferred to beta launch.** Architecture supports any pricing (ADR-011). Ship with generous free tier for beta, instrument everything (AI costs, compute time, storage per user), set prices based on real unit economics.

12. ~~**GDPR data residency:**~~ **Resolved:** EU-region deployment from day one. Target market is EU engineering firms. Deploy on AWS eu-central-1 (Frankfurt) or eu-west-1 (Ireland) as the primary region. All user geometry, intent graphs, and PII stored in EU. Claude API calls go to Anthropic's infrastructure (check Anthropic's data processing terms for EU compliance). Update ADR-010 data security section accordingly.
