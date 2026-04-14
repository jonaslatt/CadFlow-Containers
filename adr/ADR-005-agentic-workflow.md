# ADR-005: Agentic Workflow Architecture

## Status
Proposed

## Date
2026-04-07

## Context

CadFlow's core differentiator is that an AI agent (Claude) can author and modify the intent graph on behalf of the user. This ADR defines how the agent interacts with the system: what tools it has, how it receives context about the model, how users control its autonomy, and how mistakes are handled.

Key forces:
- **CadQuery is the ideal LLM target.** The Text-to-CadQuery paper (arXiv, May 2025) demonstrates 69.3% exact match with fine-tuned models and declares CadQuery "the de facto standard output format for neural text-to-CAD systems."
- **Context limits are real.** Complex CAD models can exhaust token budgets; the agent needs compact representations of geometry state.
- **Trust must be earned.** Users need control over how much initiative the agent takes, especially for destructive operations like deleting features.
- **Iteration is essential.** All LLM-CAD systems require iterative refinement loops with execution feedback.

## Research Findings

### Claude Tool Use Best Practices

From Anthropic's engineering blog on writing effective tools:
- **Naming:** Use prefix-based namespacing (`cad_sketch_create`, `cad_extrude`) — naming measurably affects evaluation performance.
- **Descriptions:** Write as if onboarding a new team member; make implicit context explicit. Longer descriptions produce better results.
- **Output formatting:** Return only "high signal" information. A `response_format` enum (detailed vs. concise) showed 65% token reduction in one case.
- **Error handling:** Replace opaque errors with actionable guidance. Errors fed back as `ToolResult` enable self-correction.
- **Tool set size:** Fewer thoughtful tools beats wrapping every API endpoint. Use `ToolSearch` for on-demand discovery.

Sources: [Writing Effective Tools](https://www.anthropic.com/engineering/writing-tools-for-agents), [Advanced Tool Use](https://www.anthropic.com/engineering/advanced-tool-use)

### Agentic Coding Tool Architectures

| Tool | Key Pattern | Relevance to CadFlow |
|------|------------|---------------------|
| **Cursor** | Semantic diff (LLM → apply model → linter → self-correct); escalating autonomy (Tab → Cmd+K → Chat → Agent) | Escalating autonomy model directly applicable |
| **Aider** | Tree-sitter repo map; deep git integration; atomic auto-commits; architect mode for planning | Architect mode maps to intent graph planning |
| **Claude Code** | Single-threaded agent loop; built-in tools; permission model (default → acceptEdits → auto → bypass); hooks | Permission model is the template for progressive autonomy |
| **GitHub Copilot** | Issue-to-PR sub-agent workflow; async cloud execution; self-healing | Sub-agent pattern for complex multi-step CAD tasks |

Sources: [How Cursor Works](https://blog.sshh.io/p/how-cursor-ai-ide-works), [Claude Code Architecture](https://code.claude.com/docs/en/how-claude-code-works), [Copilot Coding Agent](https://github.blog/news-insights/product-news/github-copilot-meet-the-new-coding-agent/)

### Human-in-the-Loop Design

- **Preview-before-apply:** Standard HITL flow: agent proposes → pauses → human reviews → approve/reject.
- **Progressive autonomy:** Claude Code's graduated permission levels: `default` (ask for everything), `acceptEdits` (auto-approve edits), `auto` (model classifier), `bypassPermissions` (isolated only).
- **Streaming with intervention:** Claude Agent SDK supports `StreamEvent` for real-time visibility; users can inject messages mid-loop.
- **HITL evolution:** Moving from review-at-every-step to strategic validation at critical decision points.

Sources: [Permit.io: HITL for AI Agents](https://www.permit.io/blog/human-in-the-loop-for-ai-agents-best-practices-frameworks-use-cases-and-demo), [Stanford HAI: Humans in the Loop](https://hai.stanford.edu/news/humans-loop-design-interactive-ai-systems)

### LLM-Driven CAD Generation

- **Text-to-CadQuery** (May 2025): Fine-tuned on ~170K samples. Best model achieves 69.3% exact match, 1.32% invalid rate. CadQuery is "the de facto standard." ([arXiv](https://arxiv.org/html/2505.06507v1))
- **CADialogue:** Multimodal conversational CAD assistant with geometric context awareness. Modular architecture decouples prompt handling, refinement, and execution. ([ScienceDirect](https://www.sciencedirect.com/science/article/abs/pii/S0010448525001678))
- **Zoo.dev:** Free text-to-CAD with STL/STEP/glTF export. ([zoo.dev](https://zoo.dev/blog/introducing-text-to-cad))
- **Key finding:** All systems use intermediate representations (executable code, JSON); direct 3D output remains intractable. CadQuery code is the optimal representation.
- **CAD survey** (arXiv, May 2025): Recommends multi-view renders + topology summaries for providing LLMs with geometry context. ([arXiv](https://arxiv.org/html/2505.08137v1))

### Agent Memory

- **Claude Code's memory:** Hierarchical CLAUDE.md files (global, project, repo) + auto-memory for corrections and preferences. Loaded at session start.
- **Claude API Memory Tool:** CRUD on `/memories` directory. Just-in-time retrieval rather than loading everything upfront. Multi-session pattern: progress logs + feature checklists.
- **For CadFlow:** Layered memory — project constraints, session state, correction history, preference tracking.

Sources: [Claude Memory](https://code.claude.com/docs/en/memory), [Memory Tool Docs](https://platform.claude.com/docs/en/agents-and-tools/tool-use/memory-tool)

### Agent Planning Architectures

Three dominant patterns:
1. **ReAct** (Reason + Act): Interleaved reasoning and action; simple but sequential.
2. **Plan-and-Execute:** Complete plan upfront; less adaptive but lower token usage.
3. **Graph Agents (DAG-based):** Tasks as DAG with dependencies; parallel execution (LLMCompiler claims 3.6x speedup); dynamic replanning.

The DAG-based approach aligns naturally with CadFlow's intent graph — each CAD operation declares dependencies on prior geometry. ([LangChain: Planning Agents](https://blog.langchain.com/planning-agents/))

## Options Considered

### Option A: Simple Chatbot with Code Generation

Claude generates complete CadQuery scripts from natural language. No structured tools, no intent graph manipulation — just code in, geometry out.

- **Pros:** Simplest to build. Leverages Claude's strong Python generation. No tool schema maintenance.
- **Cons:** No structured interaction with the intent graph. Cannot modify individual features — must regenerate entire scripts. No preview or undo. No context about current model state beyond what fits in the prompt. Fragile: one bad generation replaces the entire model.
- **Real-world precedent:** Zoo.dev's text-to-CAD works this way. Good for one-shot generation, poor for iterative refinement.

### Option B: Full Autonomous Agent

Claude has unrestricted access to all operations with minimal human oversight. The agent plans, executes, and verifies multi-step geometry operations autonomously.

- **Pros:** Maximum agent capability. Fastest for experienced users who trust the system. Can handle complex multi-step tasks without user intervention.
- **Cons:** Dangerous for destructive operations (deleting features, boolean subtracts on wrong body). Users lose control. Mistakes compound — a wrong fillet cascades through downstream features. No natural checkpoint for user review.
- **Real-world precedent:** Claude Code's `bypassPermissions` mode — explicitly restricted to isolated container environments.

### Option C: Structured Tool-Use Agent with Progressive Autonomy (Recommended)

Domain-specific tools for intent graph manipulation, with preview-before-apply and escalating autonomy levels that users control.

- **Pros:** Structured tools produce predictable, validatable operations. Preview prevents mistakes. Users control autonomy level per session or per operation. Undo works naturally (transaction groups on the intent graph). Agent can be progressively trusted as users gain confidence.
- **Cons:** Tool schema design is upfront work. Preview adds latency (must tessellate proposed changes). Autonomy control UI adds complexity. Some operations are hard to preview (e.g., "make this look more aerodynamic").
- **Real-world precedent:** Cursor's escalating autonomy ladder (Tab → Cmd+K → Chat → Agent); Claude Code's permission model; Smashing Magazine's six agentic UX patterns (2026).

## Decision

**Option C: Structured Tool-Use Agent with Progressive Autonomy.**

### Tool Architecture

~20 domain-specific tools organized by prefix:

**Sketch operations:**
- `cad_sketch_create(plane, constraints)` — start a new sketch on a plane
- `cad_sketch_add_geometry(sketch_id, type, params)` — add line, arc, circle, rectangle
- `cad_sketch_add_constraint(sketch_id, type, params)` — dimension, coincident, tangent, etc.

**Feature operations:**
- `cad_feature_extrude(sketch_id, distance, direction, operation)` — add/cut, blind/through-all
- `cad_feature_revolve(sketch_id, axis, angle)`
- `cad_feature_fillet(edge_selector, radius)`
- `cad_feature_chamfer(edge_selector, distance)`
- `cad_feature_boolean(body_a, body_b, operation)` — union/subtract/intersect
- `cad_feature_shell(face_selector, thickness)`
- `cad_feature_hole(face_selector, diameter, depth)`
- `cad_feature_mirror(feature_ids, plane)`

**Query operations (read-only):**
- `cad_query_faces(selector)` — list faces matching a selector
- `cad_query_edges(selector)` — list edges matching a selector
- `cad_query_measure(entity_a, entity_b)` — distance, angle
- `cad_query_bounding_box()` — model extents
- `cad_query_validate()` — BRepCheck_Analyzer + watertight check
- `cad_query_topology()` — face/edge/vertex counts, solid count
- `cad_query_render(views)` — generate multi-view renders (front, top, iso) for spatial reasoning; on-demand, not every turn

**Graph operations:**
- `cad_graph_get_state()` — compact JSON of intent graph (nodes, edges, parameters)
- `cad_graph_modify_parameter(node_id, param, value)` — change a parameter
- `cad_graph_delete_node(node_id)` — remove a feature (requires confirmation)

**CFD operations:**
- `cad_cfd_name_surface(face_selector, name, bc_type)` — tag for boundary conditions
- `cad_cfd_create_domain(type, dimensions)` — bounding box or cavity extraction
- `cad_cfd_defeature(threshold)` — remove small fillets/holes below threshold
- `cad_cfd_check_watertight()` — validate for meshing readiness

**Export operations:**
- `cad_export_step(options)`, `cad_export_stl(options)`, `cad_export_brep()`

### Context Provision

The agent receives a text-only model context as a compact payload at the start of each turn. When spatial reasoning is needed, the agent calls `cad_query_render()` on demand (~1-2s latency):

```json
{
  "topology": {"faces": 24, "edges": 48, "vertices": 26, "solids": 1},
  "bounding_box": {"min": [0, 0, 0], "max": [100, 50, 30]},
  "volume": 150000.0,
  "intent_graph_summary": [
    {"id": "n1", "op": "sketch", "plane": "XY"},
    {"id": "n2", "op": "extrude", "distance": 30, "depends": ["n1"]},
    {"id": "n3", "op": "fillet", "radius": 5, "edges": ">Z", "depends": ["n2"]}
  ],
  "surface_groups": {"inlet": 1, "outlet": 1, "wall": 22},
  "validation": {"is_valid": true, "is_watertight": true}
}
```

When spatial context is needed (e.g., "fillet the top edges", "which face is the inlet?"), the agent calls `cad_query_render(["front", "top", "iso"])` to get multi-view renders included via Claude's vision capabilities. This is on-demand — most interactions (parameter tweaks, structural queries) use only the text summary above, keeping latency near zero. Follows the CAD-LLM survey recommendation for providing LLMs with geometry context.

### Progressive Autonomy

Four modes, user-configurable per session:

| Mode | Behavior | Use Case |
|------|----------|----------|
| **Suggest** (default) | Agent describes what it would do; user must explicitly approve each operation | New users, learning the tool |
| **Propose** | Agent shows a full plan with preview renders; user approves the plan as a whole | Moderate trust, reviewing multi-step operations |
| **Execute** | Agent executes operations with per-operation confirmation for destructive actions only (delete, boolean subtract) | Experienced users, routine modifications |
| **Autonomous** | Agent executes all operations without confirmation; full undo available | Power users, batch operations, automated workflows |

The autonomy level persists per session and can be changed at any time. Destructive operations always show a confirmation in Suggest and Propose modes.

### Preview-Before-Apply

For geometry-modifying operations:
1. Agent calls the tool with `preview: true`
2. Backend executes the operation on a copy of the intent graph
3. Tessellated result is sent to the frontend as a ghost overlay (semi-transparent, different color)
4. User sees before/after and approves or rejects
5. On approval, the operation is applied to the real intent graph

### Undo Architecture

Agent actions are grouped as **transaction units** on the intent graph:
- A single user request may trigger multiple tool calls (e.g., "add a hole with a fillet" = sketch + extrude-cut + fillet)
- All tool calls from one user request form a single undo unit
- Undo reverts the entire transaction, not individual operations
- Undo history is stored as append-only events on the intent graph (per ADR-008)

### Agent Memory

Layered memory system for cross-session learning:

1. **Project memory:** Design constraints, material specifications, preferred mesh parameters, naming conventions. Stored alongside the intent graph.
2. **Session memory:** Current model state, recent operations, conversation context. Managed by Claude Agent SDK's conversation context.
3. **Correction memory:** When a user rejects or modifies an agent suggestion, the correction pattern is stored. Claude's auto-memory system handles this naturally.
4. **Preference tracking:** Defaults for wall thickness, fillet radii, mesh density. Learned from user behavior over time.

### Planning Architecture

The agent uses a **DAG-based planning approach** aligned with the intent graph:
1. User request is parsed into a high-level plan (sequence of operations with dependencies)
2. Independent operations can execute in parallel (e.g., fillets on unrelated edges)
3. Plan is presented to the user in Propose mode; executed directly in Autonomous mode
4. Dynamic replanning if an operation fails (e.g., fillet radius too large — agent suggests a smaller radius)

## Consequences

### Positive
- Structured tools produce predictable, validatable operations that map cleanly to intent graph nodes
- Progressive autonomy builds user trust gradually and prevents costly mistakes
- Preview-before-apply eliminates "oops" moments for geometry modifications
- Transaction-based undo handles multi-step agent actions as atomic units
- Compact context payload keeps Claude within token limits even for complex models
- DAG-based planning aligns naturally with the intent graph architecture

### Negative / Trade-offs
- ~20 tools require careful schema design, documentation, and testing
- Preview mode doubles geometry computation (once for preview, once for apply)
- Autonomy levels add UI complexity (mode selector, per-operation confirmations)
- Agent memory across sessions requires persistence and retrieval logic
- Multi-view render generation for context adds latency (~1-2s)

### Risks and Mitigations

| Risk | Mitigation |
|------|------------|
| Agent generates invalid geometry (self-intersections, non-manifold) | Every tool call runs BRepCheck_Analyzer; invalid results are rejected with actionable error |
| Agent exhausts context with complex models | Compact topology summary instead of full graph; ToolSearch for on-demand tool loading; sub-agents for focused subtasks |
| User rejects too many agent suggestions (bad UX) | Track rejection rate; if >50% in a session, suggest the user provide more specific instructions |
| Preview latency frustrates users | Cache tessellation; use coarse preview tessellation; show loading indicator |
| Agent makes cascading mistakes (wrong fillet breaks downstream features) | Transaction undo reverts all; validation after each operation catches issues early |

## Dependencies

- **ADR-001** (Product Scope): Defines which operations the agent's tools must cover
- **ADR-002** (UI Design): Chat panel layout, autonomy mode selector, preview overlay UX
- **ADR-004** (Backend): Claude Agent SDK integration, geometry worker communication
- **ADR-008** (Data Model): Intent graph structure that tools manipulate
- **ADR-009** (CFD Preprocessing): CFD-specific tool definitions
- **ADR-010** (Security): Sandboxing for `cad_execute_code` tool
