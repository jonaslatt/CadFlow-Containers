# ADR-001: Product Scope and Core Functionality

## Status
Proposed

## Date
2026-04-07

## Context

CadFlow is a web-based, agentic CAD tool built on OpenCASCADE (OCCT) via CadQuery, with Claude as the AI backbone. Before any architecture or implementation decisions can be made, we must define precisely what the product does — which modeling operations it supports, what workflows it enables, and how it serves both general-purpose CAD users and the CFD preprocessing audience.

The product must be useful from day one (MVP), while having a clear growth path toward a comprehensive parametric CAD tool. The challenge is scoping V1 tightly enough to be buildable by a small team while broadly enough to attract users and demonstrate the agentic value proposition.

Key forces at play:
- **Dual audience:** General mechanical/product engineers need standard parametric CAD; CFD/simulation engineers need geometry cleanup, defeaturing, and export tools that existing CAD tools handle poorly.
- **Agentic differentiator:** The AI agent must have enough operations to be genuinely useful, not just a gimmick.
- **CadQuery as the intent layer:** The feature set is constrained by what CadQuery/OCCT can do — but this constraint is quite generous.
- **Competition:** FreeCAD (free, desktop), Onshape (cloud, collaborative), Fusion 360 (desktop+cloud, broad feature set), OpenSCAD (code-based, limited).

## Research Findings

### What Beginners Learn First (Universal Across All CAD Tools)

Every major CAD tool — FreeCAD, Fusion 360, Onshape, SolidWorks — teaches the same foundational sequence in their "Getting Started" tutorials:

1. **Sketch on a plane** — select a reference plane (XY, XZ, YZ), draw 2D geometry (rectangle, circle, line, arc)
2. **Constrain the sketch** — add dimensions, apply geometric constraints (horizontal, vertical, coincident, tangent)
3. **Extrude** — convert 2D sketch to 3D solid
4. **Cut** — remove material using a second sketch
5. **Fillet** — round selected edges
6. **Chamfer** — bevel selected edges

This sequence — sketch → extrude → cut → fillet — is the absolute minimum for a "Hello World" CAD experience. Sources: FreeCAD Getting Started tutorials, Fusion 360 Quick Start Guide (Autodesk), Onshape Fundamentals learning path, SolidWorks Getting Started tutorials (GoEngineer).

### The SSR Design Paradigm

Academic research on parametric CAD datasets (SAGE Journals, 2024) identifies the **SSR pattern: Sketch, Sketch-based Feature, Refinement**. Every parametric model is a sequence of SSR triples:
- **S** = a 2D sketch (lines, arcs, circles, constraints)
- **S** = a sketch-based feature (extrude, revolve, sweep, loft)
- **R** = optional refinements (fillet, chamfer, shell)

Complex shapes are built by stacking SSR units with boolean operations.

### CadQuery's Feature Set

CadQuery provides a comprehensive operation set that maps directly to the intent graph concept:
- **Sketch primitives:** rect, circle, ellipse, polygon, line, arc, spline, with constraint/dimension support
- **3D operations:** extrude (with taper/twist), revolve, sweep, loft, shell, hole (with counterbore/countersink)
- **Booleans:** union, subtract, intersect
- **Modifiers:** fillet, chamfer
- **Selectors:** query-based (`faces(">Z")`, `edges("|Z")`) — no persistent topology IDs
- **Export:** STEP, STL, AMF, 3MF, SVG, VRML, glTF, VTKJS

CadQuery's selector system is a natural fit for the intent graph: selectors express *intent* about which geometry to modify, not fragile topology IDs. This is what makes the model agent-friendly and robust to topology changes. (Source: CadQuery documentation, CadQuery cheatsheet)

### CFD Preprocessing Requirements

Research into Salome-Meca, OpenFOAM (snappyHexMesh), GMSH, and commercial tools (SimScale, ANSYS SpaceClaim) reveals these critical CFD preprocessing operations:

**Geometry Cleanup (from Siemens Simcenter 5-step CFD CAD preparation workflow):**
1. Understand & organize — section views, component filtering
2. Repair geometry — find/fix invalid bodies and faces
3. Defeature — remove manufacturing details irrelevant for flow (fasteners, small fillets, pockets, gaps)
4. Create flow domain — bounding box for external flow, or cavity extraction for internal flow
5. Parameterize — capture the prep pipeline for design exploration

**Salome GEOM module repair tools:** Suppress Faces, Close Contour, Suppress Internal Wires, Suppress Holes, Sewing, Glue Faces/Edges, Remove Internal Faces, Union Faces. Critical workflow: Explode → create face Groups (inlet/outlet/wall/symmetry) → Partition to connect domains → Sew/Glue for watertightness.

**snappyHexMesh (OpenFOAM) geometry requirements:**
- Input: STL (ASCII preferred), OBJ, VTK. Files in `constant/triSurface/`
- Each STL solid name becomes a patch in the final mesh
- Multi-region STL: patch name = `surfaceName_regionName`
- Watertight surfaces strongly recommended (verified via `surfaceCheck`)
- **Key implication:** CadFlow must support naming individual faces/groups and exporting them as separate STL solids or named regions. This is THE critical CFD preprocessing feature.

**GMSH integration:** Supports STEP, IGES, BRep import via OpenCASCADE kernel. Uses Physical Groups for boundary conditions. Physical Groups map directly to boundary condition regions in the solver.

**Export format comparison:**
| Format | Preserves | CFD Use |
|--------|-----------|---------|
| STEP | Exact B-Rep geometry, topology | Best for simulation quality |
| STL | Faceted approximation, solid names | Required by snappyHexMesh |
| BREP | Exact B-Rep (OCCT native) | Used by Salome, GMSH |

### Onshape's Collaboration Model

Onshape's success validates browser-based CAD. Key features that drive adoption:
- Real-time simultaneous editing (Google Docs for CAD)
- Git-style version control with branching and merging
- Zero-install, any-device access
- Granular permissions and audit trails
- Integrated PDM (no separate data management system)

CadFlow's intent-graph architecture could enable even better version control than Onshape — diffs on the intent graph rather than binary geometry.

### Code-Based CAD: The Hybrid Opportunity

A PLOS ONE paper (2019) comparing OpenSCAD and FreeCAD Python scripting found that code-based CAD excels when *someone else generates the code* and the user modifies parameters. This maps directly to CadFlow's vision: Claude generates CadQuery code from natural language, the user sees visual results and modifies parameters, and the intent graph provides a middle abstraction.

Advantages of code-based CAD: version control friendly, parametric by nature, reproducible, automatable, LLM-friendly. The 2025 Text-to-CadQuery paper (arXiv) demonstrates LLMs generating CadQuery scripts from natural language.

## Options Considered

### Option A: Minimal Sketch-and-Extrude MVP

Support only the absolute basics: sketch (rectangle, circle, line), extrude (add/cut), fillet, chamfer. No CFD-specific features. No boolean operations beyond cut-extrude.

- **Pros:** Fastest to build. Clear scope. Enough for a "Hello World" demo.
- **Cons:** Not useful for real work. No CFD differentiation. Agent has too few operations to demonstrate value. Users will bounce after 10 minutes.
- **Real-world precedent:** OpenSCAD started minimal but had a unique code-CAD niche. CadFlow doesn't have that luxury — it needs to compete on workflows.

### Option B: Full Parametric CAD Feature Parity (V1 = FreeCAD Part Design)

Support the complete CadQuery operation set from day one: all sketch primitives, extrude, revolve, sweep, loft, shell, hole, booleans, patterns, mirror, assemblies, plus full CFD preprocessing.

- **Pros:** Immediately competitive. Users can do real work. Full agent capability.
- **Cons:** Too large for a small team to build in a reasonable timeframe. Quality will suffer across the board. Testing surface area is enormous. Assemblies alone are a multi-month effort.
- **Real-world precedent:** FreeCAD has been in development for 20+ years and still has UX issues. Trying to match it from scratch is unrealistic.

### Option C: Tiered MVP with CFD Differentiation (Recommended)

Define three tiers with working software at each stage. V1 MVP focuses on the core SSR workflow plus the CFD-specific features that differentiate CadFlow from free alternatives.

**V1 MVP — Core Modeling + CFD Preprocessing:**

Modeling operations:
- Sketch: line, arc, circle, rectangle, polygon, dimension constraints, geometric constraints (horizontal, vertical, coincident, tangent)
- Extrude: add and cut, blind and through-all
- Revolve: around axis
- Fillet and Chamfer
- Boolean: union, subtract, intersect
- Shell (hollow out)
- Hole (simple cylindrical, counterbore)
- Mirror

CFD-specific operations:
- Face/surface naming and grouping (for boundary conditions)
- Multi-solid named STL export (one solid per named group)
- STEP and BREP export
- STL import with mesh repair (sewing, hole filling, normal fixing)
- Watertight validation check
- Basic defeaturing (suppress fillets below threshold, fill small holes)
- Bounding box / flow domain creation (for external aero setups)

Agent capabilities:
- Natural language → CadQuery code generation
- Geometry query and inspection ("what faces are parallel to Z?")
- Parameter modification via intent graph
- Preview before apply
- Undo agent actions as a single unit

Core workflows supported end-to-end:
1. Design a simple mechanical part from a text description
2. Import STEP or STL → defeature/repair → name surfaces → export STL for OpenFOAM
3. Create a parametric part → modify dimensions via chat
4. Create external flow domain around imported geometry
5. Validate geometry for meshing readiness

**V1.1 — Extended Modeling:**
- Sweep and Loft
- Linear and circular patterns
- Draft/taper on extrude
- Reference planes (offset, angled)
- Advanced sketch constraints (symmetry, perpendicular, equal)
- Sketch fillet and chamfer (2D)
- More defeaturing tools (suppress features, simplify geometry)
- Refinement zone creation for CFD

**V2 — Advanced:**
- Assemblies (multi-body, constraints)
- Sheet metal operations
- Surface operations (trim, extend, thicken)
- Multi-section sweep
- Variable fillet
- Real-time collaboration (Onshape-style)
- Meshing preview integration (GMSH)

- **Pros:** Buildable scope for a small team. Useful from day one for both audiences. CFD features are a genuine differentiator (no free tool does this well in a browser). Agent has enough operations to demonstrate real value. Clear upgrade path.
- **Cons:** V1 lacks sweep/loft, which some users will miss. Assemblies deferred to V2 limits multi-body workflows. Some CFD users may want GMSH integration sooner.
- **Real-world precedent:** Onshape launched with a focused feature set and expanded rapidly. Fusion 360 started as "Inventor Fusion" with limited capabilities. Both succeeded by being useful (not complete) from day one.

## Decision

**Option C: Tiered MVP with CFD Differentiation.**

The V1 MVP includes the core SSR modeling workflow (sketch, extrude, revolve, fillet, chamfer, boolean, shell, hole, mirror) plus the CFD preprocessing features that differentiate CadFlow (surface naming/grouping, named STL export, defeaturing, watertight validation, flow domain creation). This provides 5 complete end-to-end workflows on day one.

The rationale:
1. **CFD preprocessing is the differentiator.** No free, browser-based tool does this well. Salome-Meca is powerful but has a steep learning curve and no AI assistance. Exporting named STL regions for snappyHexMesh is a pain point that CadFlow can solve elegantly.
2. **The modeling subset covers ~80% of basic parts.** The SSR research shows that extrude + revolve + fillet + chamfer + boolean handles the vast majority of simple-to-moderate parts.
3. **The agent needs enough operations to be useful.** With ~15 modeling operations + CFD tools + geometry queries, Claude has sufficient tools to demonstrate genuine value.
4. **Sweep, loft, and patterns are deferred but close.** CadQuery supports them natively; the V1.1 timeline is short.

## Consequences

### Positive
- Focused scope enables quality implementation over breadth
- CFD preprocessing creates a defensible niche from day one
- Surface naming/grouping is architecturally foundational — building it early means it's deeply integrated
- The tiered approach produces working software at each stage
- Intent graph versioning enables better design iteration than file-based CAD tools

### Negative / Trade-offs
- Users needing sweep or loft operations cannot use CadFlow until V1.1
- No assembly support until V2 limits multi-part workflows
- Competing with FreeCAD on general-purpose features is a losing game initially — the CFD angle must be the primary value proposition
- Some CFD users may prefer to stay with Salome-Meca until meshing integration (V2) is available

### Risks and Mitigations
| Risk | Mitigation |
|------|------------|
| MVP feature set too thin for retention | Focus on polish and agent quality over feature count; 5 complete workflows > 20 half-working features |
| CFD audience too niche for growth | Position CFD as the deep use case but market as "AI-powered parametric CAD" broadly |
| CadQuery limitations block a needed feature | Escape hatch to raw OCP/OCCT for edge cases; contribute upstream fixes |
| Agent quality insufficient at launch | Invest heavily in tool definitions and prompt engineering; ship with "suggest" mode (preview before apply) |

## Dependencies

- **ADR-002** (UI Design): The feature set determines what UI elements are needed (feature tree depth, property panels, CFD-specific panels)
- **ADR-003** (Frontend): Visualization requirements depend on what geometry operations we support
- **ADR-004** (Backend): The operation set determines the CadQuery execution environment requirements
- **ADR-005** (Agentic Workflow): The tool set for Claude is directly derived from this feature scope
- **ADR-008** (Data Model): The intent graph schema must represent all V1 operations
- **ADR-009** (CFD Preprocessing): Detailed CFD workflow design depends on the scope defined here
