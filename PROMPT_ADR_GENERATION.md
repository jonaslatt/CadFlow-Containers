# Prompt: Architecture Decision Records for an Agentic CAD Tool

## Context and Strategic Vision

You are an architecture team tasked with writing Architecture Decision Records (ADRs) for **CadFlow** — a web-based, agentic CAD tool built on OpenCASCADE (OCCT) via CadQuery, with Claude as the AI backbone.

### Core Concept

CadFlow replaces fragile topology references with a **semantic intent graph** that generates geometry:

- **Nodes:** operations (sketch, extrude, fillet, hole, boolean, chamfer, shell, loft, sweep...)
- **Edges:** dependencies between features
- **Selectors:** query-based references (e.g., `faces(">Z")`, `edges("|Z")`) — no persistent face/edge IDs
- **Parameters:** dimensions, constraints, materials
- **Rebuild:** deterministic regeneration from parameters

```
Intent Graph → Regeneration → OCCT Geometry
```

The CadQuery DSL is the intent layer; OCP/OCCT is the execution layer. An agent layer (Claude) authors and modifies the intent graph on behalf of the user.

**Escape hatch:** low-level OCP/pythonOCC operations are allowed but isolated from the intent graph.

### Target Audience

The target audience is situated in the two following categories
    - Mechanical / product engineers looking for a general-purpose entry-level tool in their field.
    - Engineers and researchers who perform **CAD as pre-processing for CFD simulations** — they need to create, simplify, defeaturing, and prepare geometry for meshing.

---

## Instructions for the ADR-Writing Process

### Process Model

You will operate as a system of specialized agents:

1. **Research Agent** — For each ADR topic, conduct deep web research before writing. Search for:
   - Official documentation and user guides of professional CAD tools (FreeCAD, Fusion 360, SolidWorks, Onshape, OpenSCAD, BRL-CAD, Salome-Meca)
   - Tutorials and workflow demonstrations for these tools
   - Academic papers on CAD/CFD preprocessing workflows
   - Open-source CAD project architectures (FreeCAD, CadQuery, Solvespace, Salome)
   - State of the art in agentic UI design and AI-assisted design tools
   - WebGL/WebGPU 3D viewer technology comparisons
   - Cloud-based CAD architectures (Onshape's architecture is a key reference)
   - Relevant community discussions (CAD forums, CFD forums, Discourse, Reddit r/cad, r/CFD, r/3Dprinting)

   **Do not skip research.** Each ADR must reference specific findings from real tools and real documentation. Vague generalities are unacceptable.

2. **Author Agent** — Write each ADR following the structure defined below. For each decision:
   - Identify and describe **at least 3 concrete options**
   - Evaluate each option with specific pros, cons, and references to real-world usage
   - Make a clear recommendation with rationale
   - Identify risks and mitigations

3. **Review Agent** — After each ADR is drafted, critically review it against these criteria:
   - **Depth:** Does it reflect genuine research, or is it superficial? Are claims backed by specific references?
   - **Options coverage:** Were viable alternatives genuinely considered, or was the outcome predetermined?
   - **Feasibility:** Can a small team (or an AI agent) actually implement this? Are there hidden complexities?
   - **Consistency:** Does this ADR contradict or create tension with other ADRs?
   - **CFD focus:** Does the decision adequately serve the CFD preprocessing use case?
   - **Agentic fit:** Does the decision support AI-assisted workflows, or does it inadvertently make them harder?

   If the review finds flaws, **hand the ADR back to the Author Agent with specific feedback**. The Author must revise and resubmit. Iterate until the Review Agent approves.

### ADR Format

Each ADR must follow this structure:

```markdown
# ADR-NNN: [Title]

## Status
Proposed

## Date
[Date]

## Context
[Why this decision is needed. What forces are at play.]

## Research Findings
[Specific findings from researching existing tools, documentation, tutorials, 
papers, and community discussions. Cite sources.]

## Options Considered

### Option A: [Name]
- Description
- Pros
- Cons
- Real-world precedent

### Option B: [Name]
...

### Option C: [Name]
...

## Decision
[The chosen option and clear rationale]

## Consequences
- Positive consequences
- Negative consequences / trade-offs
- Risks and mitigations

## Dependencies
[Which other ADRs this depends on or influences]
```

---

## ADR Topics

Write one ADR for each of the following topics. Process them in order — later ADRs may reference earlier ones.

### ADR-001: Product Scope and Core Functionality

**Research directive:** Search for and study tutorials, user guides, and feature lists of FreeCAD, Fusion 360, Onshape, SolidWorks, OpenSCAD, Salome-Meca, and CadQuery. Look specifically at:
- What operations do beginners learn first? What does a "getting started" tutorial cover?
- What are the most common workflows in parametric CAD?
- What does CFD preprocessing require? (geometry cleanup, defeaturing, surface extraction, boolean simplification, watertight checks, STL/STEP export)
- What do Salome-Meca and GMSH users need from a geometry tool?
- What workflows does Onshape offer that make it popular for collaboration?

**Questions to answer:**
- What modeling operations must V1 support? (sketch, extrude, revolve, loft, sweep, boolean, fillet, chamfer, shell, hole, pattern, mirror — which subset is the MVP?)
- What CFD-specific operations must V1 support? (defeaturing, geometry simplification, bounding box/domain creation, surface naming/grouping for boundary conditions, export to STL/STEP/BREP, watertight validation)
- What are the 5-8 core workflows a user should be able to complete end-to-end?
- How to define feature parity tiers (V1 MVP, V1.1, V2) so the product is useful from day one?
- How to position the product to appeal broadly while serving CFD users deeply?

### ADR-002: User Interface Design and Layout

**Research directive:** Search for UI/UX patterns in:
- Professional CAD tools (Fusion 360's timeline, SolidWorks' feature tree, Onshape's UI)
- Code-based CAD tools (OpenSCAD, CadQuery's Jupyter integration, ImplicitCAD)
- AI-assisted design tools (Cursor, GitHub Copilot, v0.dev, Galileo AI)
- Research on agentic UI patterns (human-in-the-loop, progressive disclosure, mixed-initiative interaction)

**Questions to answer:**
- How should the main layout be organized? (3D viewport, feature tree/intent graph, property panel, agent chat, code view, console)
- How to combine interactive (click-to-select, drag, direct manipulation) and agentic (chat, natural language, AI-suggested operations) UI modes seamlessly?
- When should the agent take initiative vs. wait for the user? How to handle the spectrum from "do exactly what I say" to "figure out the best approach"?
- How to visualize the intent graph in a way that's intuitive for both beginners and power users?
- How to handle the dual nature of the tool: visual CAD + code (CadQuery DSL)? Should users see the code? Always? Optionally?
- How to keep the UI simple for 80% of tasks while still providing access to advanced features?
- How should undo/redo work in an agentic context (undo an agent's multi-step action as one unit)?

### ADR-003: Frontend Technology Stack and Architecture

**Research directive:** Search for:
- Comparative analysis of React vs. Svelte vs. SolidJS for complex interactive applications
- Three.js vs. Babylon.js vs. CadPac/OpenCascade.js for CAD visualization
- State management approaches for complex parametric models (Zustand, Jotai, Redux Toolkit, XState)
- WASM-based geometry kernels in the browser (OpenCascade.js, replicad)
- Real-time collaboration architectures (CRDTs, OT) used by tools like Figma and Onshape

**Questions to answer:**
- Which UI framework? (React, Svelte, SolidJS, or other) — considering ecosystem maturity, component libraries, developer availability, and AI code generation quality
- Which 3D rendering library? (Three.js + custom, Babylon.js, or a CAD-specific viewer) — considering BREP rendering, edge display, selection, measurement, section views
- How to handle geometry visualization? Server-side tessellation (send meshes to browser) vs. client-side WASM (OpenCascade.js)?
- State management architecture — how to keep the intent graph, 3D scene, UI state, and agent state synchronized?
- Code architecture: folder structure, module boundaries, key abstractions
- How to structure the codebase so an AI agent can work on it effectively? (clear module boundaries, explicit interfaces, good test coverage)

### ADR-004: Backend Architecture and Communication

**Research directive:** Search for:
- Onshape's cloud architecture and how they handle geometry computation
- CadQuery server/runner architectures (cq-server, CQ-editor, jupyter-cadquery)
- WebSocket vs. SSE vs. REST polling for real-time geometry updates
- Claude API integration patterns (streaming, tool use, callbacks, multi-turn)
- Sandboxed code execution environments (Docker, Firecracker, gVisor, Pyodide)

**Questions to answer:**
- How to architect the backend? (monolith, microservices, or serverless — for a small team)
- How to run CadQuery/OCCT safely in the cloud? (containerized workers, sandboxing, resource limits, timeout handling)
- How to structure the Claude integration? (direct API, tool use for CAD operations, streaming responses, multi-turn modeling sessions, agent memory)
- Communication protocol between frontend and backend: REST for CRUD, WebSocket for real-time geometry updates, SSE for agent streaming — or a unified approach?
- How to handle geometry data transfer efficiently? (BREP serialization, tessellation format, compression, incremental updates)
- How to manage user sessions and persist the intent graph?
- How to handle errors gracefully? (OCCT kernel crashes, Claude timeouts, invalid geometry)
- Authentication and multi-tenancy (even if simple in V1)

### ADR-005: Agentic Workflow Architecture

**Research directive:** Search for:
- Claude tool use / function calling best practices and patterns
- Agentic coding tools architectures (Cursor, Aider, Claude Code, Copilot Workspace)
- Human-in-the-loop AI system design patterns
- Papers on LLM-driven CAD/3D generation (if any exist)

**Questions to answer:**
- How should the agent interact with the intent graph? (generate CadQuery code, manipulate graph nodes directly, or both?)
- What tools should Claude have access to? (create_sketch, extrude, fillet, boolean, query_geometry, validate, export, search_documentation, run_code...)
- How to give Claude sufficient context about the current model state without exceeding context limits?
- How to handle agent mistakes? (preview before apply, undo, confirmation for destructive operations)
- How to implement "agentic memory" — should the agent remember user preferences, past designs, common patterns across sessions?
- How to handle multi-step operations where the agent needs to reason about geometry intermediate states?
- How to let the user correct the agent mid-operation and have the agent learn from corrections?

### ADR-006: Testing Strategy and Quality Assurance

**Research directive:** Search for:
- Testing strategies for CAD/geometry software (how does FreeCAD test? CadQuery's test suite?)
- Testing strategies for AI/LLM-integrated applications
- Visual regression testing for 3D applications
- E2E testing for complex web applications with WebGL content

**Questions to answer:**
- How to test the backend geometry operations? (unit tests against known OCCT results, property-based testing for geometric invariants, regression tests for specific models)
- How to test the frontend? (component tests, E2E with Playwright, visual regression, accessibility)
- How to test the agent integration? (mock responses, golden-file tests, evaluation harnesses for agent quality)
- How to test the intent graph? (graph validity, rebuild determinism, selector stability)
- How to validate that geometry is correct? (watertight checks, manifold validation, comparison against reference geometry)
- What CI/CD pipeline to use and what gates must pass before merge?
- How to handle flaky tests in an AI-integrated system?

### ADR-007: Software Development Process and AI-Assisted Development

**Research directive:** Search for:
- Best practices for AI-assisted software development (Claude Code, Cursor workflows)
- Monorepo vs. polyrepo for full-stack projects
- Git workflow for small teams with AI agents contributing code
- Claude Code extensions, MCP servers, and custom slash commands for project-specific workflows
- Documentation-driven development, ADR-driven development

**Questions to answer:**
- How to organize the repository? (monorepo with workspaces, folder structure, shared types)
- Git branching strategy and commit conventions?
- How to structure the development so Claude Code can be maximally effective? (CLAUDE.md conventions, task decomposition, test-first development)
- What Claude Code extensions or MCP servers would benefit this project? (GitHub MCP, database MCP, custom CAD MCP server?)
- How to phase the implementation? (what to build first, second, third — with working software at each stage)
- Code review process when an AI agent writes most of the code?
- How to maintain architectural coherence as the codebase grows with AI assistance?

### ADR-008: Geometry Data Model and Persistence

**Research directive:** Search for:
- How Onshape and Fusion 360 handle parametric model persistence
- STEP, BREP, and other geometry exchange formats
- STL import and export
- CadQuery model serialization approaches
- Graph database vs. document store for DAG structures

**Questions to answer:**
- How to serialize and persist the intent graph? (JSON, a graph database, a document store, plain CadQuery scripts?)
- How to handle versioning and undo history of the intent graph?
- How to support import/export with standard CAD formats? (STEP, IGES, STL, OBJ, BREP, glTF for visualization)
- How to handle large assemblies and model complexity?
- How to diff and merge intent graphs (for collaboration or version control)?
- What metadata to store alongside geometry? (materials, boundary condition labels, simulation parameters, units)

### ADR-009: CFD Preprocessing Workflows

**Research directive:** Search for:
- Salome-Meca geometry preprocessing workflows
- OpenFOAM geometry preparation best practices (snappyHexMesh requirements, STL quality)
- GMSH integration patterns and geometry requirements
- SimScale, ANSYS, and COMSOL geometry import/preparation documentation
- Common geometry problems in CFD (dirty geometry, gaps, overlaps, small features, non-manifold edges)

**Questions to answer:**
- What are the critical CFD preprocessing operations? (defeaturing, surface naming, domain creation, refinement zones, boundary layer regions, interface detection)
- How to integrate with meshing tools? (export formats, mesh quality feedback loops)
- How to help users identify and fix geometry problems that would cause meshing failures?
- How to support common CFD setups? (external aerodynamics, internal flow, heat transfer, multiphase)
- How to name/tag surfaces so boundary conditions can be applied consistently across re-generations?
- Should the tool include meshing preview or delegate entirely to external tools?
- How can the agent assist with CFD-specific tasks? (suggest defeaturing, auto-create bounding domains, recommend mesh settings)

### ADR-010: Security, Sandboxing, and Resource Management

**Research directive:** Search for:
- Sandboxed code execution best practices (running user-provided CadQuery code safely)
- Cloud cost management for compute-intensive geometry operations
- Rate limiting and abuse prevention for AI-integrated tools
- OCCT memory safety considerations
- User data safety and confidentiality considerations

**Questions to answer:**
- How to sandbox user/agent-generated CadQuery code execution?
- Resource limits: CPU, memory, time per geometry operation?
- How to prevent and handle OCCT crashes (segfaults in the geometry kernel)?
- How to manage Claude API costs and prevent abuse?
- Data privacy: where is user geometry and user stored, who can access it?
- Data security: who to handle and communicate security measures for user data?
- How to handle concurrent users on shared compute infrastructure?

### ADR-011: User management, Billing

**Research directive:** Search for:
- SAAS software user management best practices
- User management tools (keeping track of user needs, issues, satisfaction, continued product purchases)
- Billing infrastructure (invoicing, credit card payments, banking)
- Financial control of income and expense in SAAS software

**Questions to answer:**
- How to keep an overview over users, the cash-flow generated by users, their needs and satisfaction ?
- How to make sure user requests and complaints are handled efficiently ?
- How to scale with an increasing number of users while limiting the financial risk ?
- How to set up a payment system ?
- How to make sure the expenses (cloud backend, IA backend) cannot exceed the income stream and lead to a risky situation ?
- How to keep a solid overview over the finances of the product ?

---

## Final Deliverable

Produce all ADRs as a single document, clearly separated. After all ADRs are written and reviewed, include a final section:

### ADR Summary Matrix

A table showing:
| ADR | Key Decision | Primary Trade-off | Confidence Level |
|-----|-------------|-------------------|-----------------|

And a **dependency graph** showing how the ADRs relate to each other.

### Open Questions

List any significant questions that emerged during the process that are not resolved by the ADRs and require further investigation or prototyping.
