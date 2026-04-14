# ADR-002: User Interface Design and Layout

## Status

Proposed

## Date

2026-04-07

## Context

CadFlow is a web-based agentic CAD tool built on OpenCASCADE/CadQuery with Claude AI
as the driving intelligence. The core data model is the **intent graph** — a directed
acyclic graph where nodes represent modeling operations, edges represent dependencies,
and selectors provide query-based references to geometry (e.g., "the largest face of
body X" rather than brittle topological IDs).

The UI must serve several competing demands:

1. **CAD professionals** expect a viewport-centric layout with spatial manipulation,
   feature history, and predictable undo/redo. Decades of muscle memory from
   SolidWorks, Fusion 360, and Onshape set strong expectations.

2. **Code-CAD users** (OpenSCAD, CadQuery, Jupyter) expect a text editor, a REPL-like
   feedback loop, and the ability to parameterize geometry programmatically.

3. **AI-native interaction** introduces a third modality: conversational intent
   specification, agent-driven multi-step operations, and the need for human oversight
   of autonomous actions.

4. **The intent graph** is simultaneously a DAG (with parallelism, branching, merging)
   and a feature history (with chronological ordering). The UI must represent both
   views without forcing users into one mental model.

5. **Progressive disclosure** is critical. A beginner describing "make a box with
   rounded edges" should never see a node graph or CadQuery code unless they choose to.
   An expert should be able to drop into the DAG editor or script editor at any point.

No existing tool satisfactorily combines all three modalities (direct manipulation,
code, and AI conversation) in a single coherent interface. This ADR evaluates
approaches and proposes a layout that does.


## Research Findings

### Professional CAD UI Patterns

**Autodesk Fusion 360** uses a four-zone layout:
- Browser panel (left): hierarchical tree of components, bodies, sketches, and
  construction geometry. Supports drag-and-drop reordering and nesting.
- 3D viewport (center): dominant, resizable, supports split views.
- Timeline (bottom): a temporal, linear sequence of features with rollback scrubbing.
  This is a *second* representation of the same features shown in the browser tree —
  the dual representation lets users think hierarchically (by component) or temporally
  (by construction order).
- Toolbars (top): contextual — change based on active workspace (Model, Sketch,
  Sheet Metal, etc.).

Key insight: Fusion 360 proves that **dual representation** (tree + timeline) of the
same underlying data is not confusing — users naturally switch between them depending
on their current task.

**Dassault SolidWorks** uses:
- CommandManager ribbon (top): tab-based, context-sensitive toolbar that changes
  based on the active document type and current operation.
- Manager Pane (left): five switchable tabs — FeatureManager Design Tree,
  PropertyManager (contextual properties), ConfigurationManager, DimXpertManager,
  and DisplayManager. The PropertyManager dynamically replaces the tree when an
  operation is active, providing inline editing without modal dialogs.
- Graphics Area (center): the 3D viewport.

Key insight: SolidWorks' **dynamic panel switching** — where the left panel content
changes based on current operation — reduces panel count while keeping information
accessible. The PropertyManager pattern (inline contextual editing) avoids modal
dialog proliferation.

**PTC Onshape** uses:
- Feature List (left): a flat, chronological list of features. No hierarchy,
  no nesting — just a linear sequence. Simpler than SolidWorks or Fusion 360.
- 3D viewport (center): with contextual right-click menus and in-canvas editing
  widgets.
- Contextual panels (right): appear on demand for properties, configurations, etc.
- Tab bar (bottom): for switching between Part Studios, Assemblies, and Drawings
  within the same document.

Key insight: Onshape proves that a **flat feature list** can work for serious CAD.
The simplicity is a feature, not a limitation — it lowers the learning curve
dramatically compared to SolidWorks' five-tab manager pane.

### Code-CAD Tool UI Patterns

**OpenSCAD** uses a two-panel layout:
- Script editor (left): plain text editor for the OpenSCAD language.
- 3D preview (right): renders the geometry defined by the script.
- Console (bottom): compiler output, warnings, errors.
- Interaction model: edit code → press F5 (preview) or F6 (render). Auto-reload
  on file change is available. No direct manipulation of geometry — all changes
  go through code.

Key insight: OpenSCAD's **unidirectional data flow** (code → geometry, never
geometry → code) is simple but limiting. Users cannot click a face and modify it;
they must find the corresponding code.

**CQ-editor** (the CadQuery IDE) adds:
- Script editor with CadQuery-aware completion.
- 3D viewer (using CadQuery's OCP-based renderer).
- A **debugger** that allows stepping through CadQuery operations and inspecting
  intermediate geometry states. This is unique — users can see the geometry at
  any point in the construction history by setting breakpoints.

Key insight: CQ-editor's **intermediate state inspection** is directly relevant to
CadFlow. The intent graph's nodes each produce intermediate geometry; the UI should
allow inspecting geometry at any node, not just the final result.

**jupyter-cadquery** provides:
- A Jupyter widget that renders CadQuery geometry in a sidecar panel.
- An object tree with per-object visibility toggles and color controls.
- **Non-destructive exploration**: the viewer state is independent of code execution.
  Users can hide/show bodies, rotate, zoom, and measure without re-executing code.

Key insight: **Decoupling viewer state from model state** is essential. The user
should be able to explore the 3D view (hide bodies, isolate components, measure)
without triggering recomputation.

### AI Tool UI Patterns

**Cursor** (AI code editor) established the **escalating autonomy ladder**:
1. **Tab** (passive): Ghost text suggestions that appear inline. Accept with Tab,
   dismiss by typing. Zero friction, zero interruption.
2. **Cmd+K** (inline edit): Select code, describe the change in natural language,
   see a diff preview, accept or reject. Scoped to a selection.
3. **Chat** (conversational): Side panel for longer discussions. Can reference files,
   generate code blocks, apply changes with user approval.
4. **Agent** (autonomous): Multi-step operations — reads files, writes code, runs
   tests, iterates. The user monitors and can interrupt.

Key insight: **Autonomy is not binary**. Users want different levels of AI
involvement for different tasks. The UI must support smooth transitions between
"AI suggests" and "AI acts."

**GitHub Copilot** follows a similar ladder but is more tightly integrated into
VS Code's existing UI paradigms. Its Chat panel is a side panel that can be
docked, floated, or inlined. Copilot Workspace (2025) introduced a plan-edit-review
loop where the AI proposes a multi-file change plan, the user reviews and edits the
plan, then the AI executes it.

**Vercel v0.dev** pioneered the **generate-then-refine** loop for UI components:
1. User describes intent in natural language.
2. AI generates a complete artifact (React component).
3. User evaluates the result visually in a live preview.
4. User refines via follow-up chat messages, pointing at specific elements.

Key insight: The **artifact-centric conversation** pattern — where chat messages
reference and modify a visible artifact — maps directly to CAD. The 3D viewport is
the artifact; chat messages describe modifications to it.

### Agentic UI Research

**Progressive disclosure** (Nielsen, 1995): "Defer advanced or rarely needed
features to a secondary screen, making applications easier to learn and less
error-prone." In CadFlow, this means: show the feature list by default, offer
the node graph on demand; show the 3D result by default, offer the CadQuery code
on demand.

**Mixed-initiative interaction** (Horvitz, "Principles of Mixed-Initiative User
Interfaces," CHI 1999): Key principles relevant to CadFlow:
- The agent should operate **non-modally** — it should not block the user from
  doing other things while it works.
- **Human always wins conflicts** — if the user and the agent are both trying to
  modify the same geometry, the user's action takes precedence.
- **Visual attribution** — the UI must make clear which parts of the model were
  created by the human and which by the AI.
- **Memory of interaction** — the agent should remember what the user has done
  and not repeat suggestions that were rejected.

**Smashing Magazine's "Six Agentic UX Patterns"** (February 2026) codified
emerging best practices:

1. **Intent Preview**: Before the agent acts, show a preview of what it intends to
   do. In CadFlow: show a ghosted/transparent preview of proposed geometry before
   committing it to the intent graph.
2. **Autonomy Dial**: Let users configure how much autonomy the agent has, on a
   per-task or per-domain basis. In CadFlow: "always ask before adding fillets"
   vs. "auto-apply chamfers under 2mm."
3. **Explainable Rationale**: The agent should explain *why* it chose a particular
   approach. In CadFlow: "I used a loft instead of an extrude because the cross
   sections differ" — shown as a tooltip or expandable note on the operation node.
4. **Confidence Signal**: Visual indication of the agent's confidence in its
   action. In CadFlow: color-coded operation nodes (green = high confidence,
   yellow = uncertain, red = needs human review).
5. **Action Audit & Undo**: Every agent action must be auditable and undoable.
   In CadFlow: the intent graph *is* the audit trail. Each AI-generated node is
   tagged with its provenance (prompt, reasoning, confidence).
6. **Escalation Pathway**: Clear mechanism for the agent to ask the user for
   help when it is stuck. In CadFlow: the agent can mark a node as "needs
   human input" and surface it in the chat.

**Undo in agentic contexts** presents a unique challenge. When an agent performs a
multi-step operation (e.g., "add mounting holes" involves creating a sketch, adding
circles, extruding cuts, and adding chamfers), undo must treat the entire sequence
as **one unit**. The staged workflow — **preview → confirm → commit** — ensures
users see the full result before it enters the undo history as a single item.


### Intent Graph Visualization Research

The intent graph is CadFlow's core data model. How it is visualized determines
whether users understand their model's structure.

**SideFX Houdini** uses a full node graph editor:
- Nodes represent operations, wires represent data flow.
- Subnetworks allow collapsing groups of nodes into a single "subnet" node.
- Network boxes provide visual grouping without collapsing.
- **Zoom-level-dependent detail**: zoomed out, nodes show only names; zoomed in,
  they show parameter values and mini-previews.
- The node graph is the *primary* interface — there is no separate feature list.

Key insight: Houdini proves that a node graph can be the primary interface for a
procedural modeling tool. But Houdini's learning curve is notoriously steep — a
direct consequence of graph-first design.

**Grasshopper** (Rhino's visual programming environment):
- Color-coded node health: gray = OK, orange = missing required inputs,
  red = error/exception.
- Built-in search for finding components by name or category.
- **Profiler**: per-component execution time displayed as a bar overlay on the node.
  Critical for identifying bottleneck operations.
- Wire display options: straight, curved, hidden. Users can simplify visual clutter.

Key insight: Grasshopper's **health coloring** is immediately applicable to CadFlow.
Nodes in the intent graph should show their state: valid (computed successfully),
stale (upstream changed, needs recompute), error (failed), or pending (waiting for
AI or user input).

**Blender Geometry Nodes**:
- Introduced a **spreadsheet viewer** for inspecting geometry data at any point in
  the node graph: vertex positions, face normals, attribute values.
- Nodes have sockets typed by geometry domain (mesh, curve, point cloud, etc.).
- Group nodes allow reuse and abstraction.

Key insight: The **spreadsheet/inspector** pattern — tabular geometry data at any
node — is valuable for debugging. CadFlow should allow inspecting the BREP topology
(faces, edges, vertices, shells) at any node in the intent graph.

**Traditional feature trees** (SolidWorks FeatureManager, Onshape Feature List):
- Simple linear list of operations.
- Familiar to all CAD users.
- **Hides parallel dependencies** — a feature tree implies sequential execution even
  when operations are independent (e.g., two holes on different faces could be
  computed in parallel).
- Supports rollback: "roll back to feature #5" suppresses all later features.

Key insight: The feature tree's simplicity is both its strength and weakness. For
CadFlow, it should be the **default** view, with the full DAG available on demand
for users who need to understand or exploit parallelism.


## Options Considered

### Option 1: Traditional CAD Layout (SolidWorks/Onshape Clone + Chat Panel)

Take a standard CAD layout — feature tree (left), 3D viewport (center), properties
(right) — and bolt on an AI chat panel as an additional side panel or bottom drawer.

**Layout:**
- Left panel: Feature tree (linear list)
- Center: 3D viewport
- Right panel: Property editor (contextual)
- Additional panel: Chat (docked right or bottom)
- Top: Ribbon toolbar

**Precedent:** This is roughly what Siemens NX with "NX X" AI assistant does —
a conventional CAD interface with a chat widget added. Also similar to how
SolidWorks' "3D Creator" role on the 3DEXPERIENCE platform integrates an AI
assistant as a sidebar.

**Pros:**
- Immediately familiar to CAD professionals. Zero learning curve for the spatial
  layout.
- Proven information architecture — decades of usability testing behind the
  SolidWorks/Onshape layout.
- Chat panel is unobtrusive; users who don't want AI can ignore it entirely.
- Straightforward to implement — many React CAD viewer libraries assume this layout.

**Cons:**
- AI is a **second-class citizen**. The chat panel competes for screen space with
  properties and the feature tree. On a typical 1920x1080 display, adding a chat
  panel means either the viewport shrinks or a panel is hidden.
- No escalating autonomy — the chat panel is always "conversational mode." There is
  no inline suggestion mode, no agent mode, no autonomy dial.
- The linear feature tree cannot represent the intent graph's DAG structure.
  Parallel branches, conditional features, and selector-based references are
  invisible.
- Code-CAD users have no code view. The tool is purely GUI-driven.
- Mixed-initiative interaction is awkward — the AI's contributions appear only in
  chat, not visually attributed in the feature tree or viewport.

**Verdict:** Familiar but fundamentally limited. Treats AI as an add-on rather than
a core interaction modality.

### Option 2: Code-First Layout (OpenSCAD/CQ-editor Style + AI Overlay)

Prioritize the code editor as the primary interface, with the 3D viewport as a
preview panel. AI assists through inline code suggestions (Cursor/Copilot-style).

**Layout:**
- Left: CadQuery script editor (primary)
- Right: 3D preview viewport
- Bottom: Console / REPL output
- AI: Inline ghost text (Tab), inline edit (Cmd+K), chat panel (toggle)

**Precedent:** CQ-editor, OpenSCAD, and Cursor. The "CAD as code" philosophy is
well-established in the maker/engineering community. Zoo's KittyCAD (Text-to-CAD)
uses a similar code-first approach with AI generation.

**Pros:**
- Full power of CadQuery is directly accessible. Users can write arbitrary Python,
  use loops, conditionals, and parameterization.
- AI assistance maps cleanly to code: suggestions, completions, and edits are
  well-understood interaction patterns (proven by Cursor and Copilot).
- The script *is* the single source of truth — no ambiguity between what the user
  sees and what generates the model.
- Version control (git) works naturally on text files.
- The intent graph can be inferred from the code's AST/execution trace.

**Cons:**
- **Excludes non-programmers entirely.** A mechanical engineer who uses SolidWorks
  daily may have no Python experience. Requiring code literacy eliminates a large
  part of the target audience.
- Direct manipulation (click-drag-rotate a feature, click a face to add a fillet)
  is either absent or requires complex bidirectional code-geometry sync.
- The 3D viewport is secondary — users spend most time reading/writing code, not
  inspecting geometry. This inverts the priority for spatial reasoning tasks.
- The intent graph is hidden inside code structure. Understanding dependencies
  requires reading code, not looking at a visual representation.
- AI-generated code can be opaque. A 50-line CadQuery script generated by Claude
  is harder to audit than a 5-node intent graph.

**Verdict:** Powerful for experts, exclusionary for everyone else. The code-first
approach works well as an *optional mode* but fails as the *primary* interface for
a tool targeting broad adoption.

### Option 3: Hybrid Agentic Layout (Recommended)

Combine a CAD-native viewport-centric design with AI-native interaction patterns:
escalating autonomy, progressive disclosure, and mixed-initiative control. The
intent graph serves as both the feature list (simple view) and the node graph
(advanced view).

**Layout:**
- Left panel: Intent tree / feature list (default: Onshape-style flat list;
  expandable to Grasshopper-style node graph)
- Center: 3D viewport (dominant, >=50% of screen area always)
- Right panel: Contextual properties / inspector (appears on demand, SolidWorks
  PropertyManager-style)
- Bottom: Split between Agent Chat and Code Editor (toggleable, collapsible,
  tabbable)
- Top: Contextual toolbar (changes based on active operation, Fusion 360-style)

**AI Interaction Model — Escalating Autonomy:**
1. **Suggest** (passive): Ghost geometry in the viewport. "You might want a fillet
   here" shown as a transparent overlay. Accept with click, dismiss with Esc.
2. **Propose** (inline): User describes an operation in the chat or via Cmd+K in
   the viewport. AI proposes a set of intent graph nodes. Shown as a diff/preview
   in the feature list with "Accept / Modify / Reject" controls.
3. **Act with confirmation** (default for multi-step): AI executes a sequence of
   operations but pauses before committing. Full preview in viewport with ghosted
   geometry. User reviews and confirms.
4. **Autonomous** (opt-in, per-operation): For trusted/repetitive operations, the
   AI acts without confirmation. User configures this per operation type via the
   autonomy dial.

**Precedent:** No single tool does all of this today, but the individual patterns
are proven:
- Layout: Fusion 360 + Onshape (viewport-centric, contextual panels)
- AI interaction: Cursor's autonomy ladder + v0.dev's artifact-centric refinement
- Intent graph dual view: Houdini's node graph + SolidWorks' feature tree
- Progressive disclosure: Nielsen's principle applied throughout
- Mixed-initiative: Horvitz's CHI 1999 principles

**Pros:**
- **Viewport is king.** CAD is fundamentally spatial; the 3D view is always
  dominant. No panel can reduce it below 50% of screen area.
- **Multiple entry points for every task.** Want a fillet? Click the face (direct
  manipulation), type in the chat ("fillet the top edges at 2mm"), write code
  (`cq.Workplane(...).fillet(2)`), or let the AI suggest it. All four paths
  produce the same intent graph node.
- **Progressive disclosure works at every level.** Beginner: feature list + viewport
  + chat. Intermediate: add properties panel and code view. Advanced: full node
  graph with spreadsheet inspector.
- **Escalating autonomy** respects user trust. New users start in "propose" mode
  (AI always asks); as trust builds, they can grant more autonomy.
- **The intent graph is the unifying abstraction.** Every interaction — GUI click,
  chat command, code statement, AI action — produces intent graph nodes. The graph
  is the single source of truth, and every view (feature list, node graph, code,
  timeline) is a projection of it.
- **Undo is coherent.** Agent multi-step operations are grouped as single undo
  units in the intent graph. Preview-before-commit means users see the full
  result before it enters the undo stack.
- **Visual attribution.** Nodes in the intent graph carry provenance: human-created
  (blue), AI-created (purple), or mixed (gradient). This is visible in both the
  feature list and node graph views.

**Cons:**
- **Implementation complexity.** Supporting four interaction modalities (GUI, chat,
  code, AI agent) that all converge on the same intent graph is architecturally
  demanding. Each modality needs its own input parsing, validation, and
  graph-mutation logic.
- **Screen real estate pressure.** Five zones (left, center, right, bottom, top)
  on a 1920x1080 display means aggressive panel collapsing is needed. The
  default state must show only left + center + top, with right and bottom
  panels appearing on demand.
- **Node graph can overwhelm.** Full DAG visualization adds complexity that not
  all users need. Mitigation: it is hidden by default, shown only when the user
  explicitly requests it (progressive disclosure).
- **AI ghost geometry in the viewport can be confusing.** Users may mistake
  suggested geometry for actual geometry. Mitigation: strong visual
  differentiation (transparency, dashed edges, distinct color) and a clear
  "Suggestion" badge.

**Verdict:** The most complex to build, but the only option that treats direct
manipulation, code, and AI as first-class peers while respecting CAD UI conventions.


## Decision

We adopt **Option 3: Hybrid Agentic Layout**.

### Layout Specification

```
+-----------------------------------------------------------------------+
|  [Contextual Toolbar]                              [View] [Settings]  |
+------------------+-----------------------------------+----------------+
|                  |                                   |                |
|  Intent Tree     |        3D Viewport                | Properties /   |
|  (Feature List   |        (dominant, >=50%)          | Inspector      |
|   or Node Graph) |                                   | (on demand)    |
|                  |                                   |                |
|  [Onshape-style  |  - Direct manipulation            | - Parameter    |
|   flat list      |  - Ghost geometry for AI          |   editor       |
|   default]       |    suggestions                    | - Selector     |
|                  |  - Selection highlighting         |   debugger     |
|  [Expandable to  |  - Measurement overlay            | - BREP         |
|   Grasshopper-   |                                   |   inspector    |
|   style DAG]     |                                   |                |
|                  |                                   |                |
+------------------+-----------------+-----------------+----------------+
|  Agent Chat                        | Code Editor (CadQuery DSL)       |
|  (conversational + suggestions)    | (optional, toggleable)           |
|                                    |                                  |
|  [Escalating autonomy controls]    | [Syntax highlighting, AI inline] |
+------------------------------------+----------------------------------+
```

### Default State (Beginner)

Only three zones visible on first launch:
1. **Left panel** — Intent tree as a flat feature list (Onshape-style).
   Width: 240px, collapsible.
2. **Center** — 3D viewport. Fills remaining space. Minimum 50% of total width.
3. **Top** — Contextual toolbar. Shows tools relevant to current selection/mode.

The bottom panel (chat + code) slides up from the bottom when the user presses
`/` (chat shortcut), clicks the chat icon, or when the AI needs to communicate.
The right panel appears when the user selects an object and clicks "Properties"
or double-clicks a feature in the intent tree.

### Intent Graph Visualization

The left panel supports two modes, toggled by a switch at the panel header:

**Feature List Mode (default):**
- Flat chronological list of operations, like Onshape.
- Each entry shows: operation icon, name, status indicator (Grasshopper-style
  health colors: gray = OK, orange = stale/recomputing, red = error, blue =
  selected, purple dashed border = AI-generated).
- Drag-and-drop reordering (where topologically valid).
- Right-click context menu: Edit, Suppress, Delete, "Show in Graph," "Show Code."
- Rollback scrubber: drag a horizontal bar to roll the model back to any point
  in the feature list (Fusion 360 timeline pattern).

**Node Graph Mode (advanced, opt-in):**
- Full DAG visualization using a force-directed or hierarchical (Sugiyama) layout.
- Nodes show operation name, mini-preview thumbnail, and health color.
- Edges show data flow (geometry) and selector references.
- Zoom-level-dependent detail (Houdini pattern): zoomed out shows only names;
  zoomed in shows parameters and previews.
- Subgraph collapsing: multi-step AI operations can be collapsed into a single
  "agent action" group node, expandable on click.
- Profiler overlay (Grasshopper pattern): per-node computation time shown as a
  bar, helping users identify bottleneck operations.
- Spreadsheet/inspector (Blender GN pattern): click any node's output port to
  open a tabular view of the BREP topology at that point (face count, edge
  count, vertex count, surface areas, etc.).

### AI Interaction Design

**Escalating Autonomy Ladder:**

| Level | Trigger | AI Behavior | User Action | UI Indicator |
|-------|---------|-------------|-------------|--------------|
| Suggest | AI-initiated | Ghost geometry in viewport, subtle | Accept (click) / Dismiss (Esc) | Transparent overlay, pulse animation |
| Propose | User asks via chat or Cmd+K | AI creates draft nodes in intent graph | Accept / Modify / Reject buttons | Dashed-border nodes in feature list |
| Act+Confirm | User requests multi-step action | AI executes fully, pauses before commit | Review preview, Confirm / Rollback | Full preview with "Commit" button |
| Autonomous | User pre-authorizes | AI acts and commits without pausing | Monitor in activity feed, undo if needed | Brief toast notification |

**Per-Operation Autonomy Dial:**
Users can configure autonomy level per operation *type*. Example settings:
- Fillets/chamfers under 2mm: Autonomous (auto-apply)
- Sketch creation: Propose (always show draft first)
- Boolean operations: Act+Confirm (always preview)
- Delete operations: Always confirm (safety constraint, non-overridable)

This is configured in a settings panel and stored as part of the user's
preferences, not the model.

**Mixed-Initiative Interaction:**

Following Horvitz (CHI 1999), the system observes these principles:

1. **Non-modal agent operation.** The AI works in the background. The user can
   continue modeling while the AI processes a request. A subtle progress
   indicator in the bottom bar shows agent activity. The user is never blocked.

2. **Human always wins.** If the user manually edits a feature that the AI is
   also modifying, the user's edit takes precedence. The AI detects the conflict,
   abandons its in-progress change, and surfaces a message: "I noticed you
   modified [feature]. I've discarded my proposed change. Would you like me to
   continue from your version?"

3. **Visual attribution.** Every node in the intent graph carries a provenance
   tag:
   - **Human-created**: default styling (no special indicator).
   - **AI-created**: purple left border + small AI icon.
   - **AI-modified** (human node edited by AI): gradient border (user color →
     purple).
   - **Human-modified** (AI node edited by human): gradient border (purple →
     user color).

   This attribution is visible in the feature list, node graph, and code view
   (as comments). It provides the "Action Audit" pattern from Smashing Magazine's
   agentic UX framework.

4. **"Continue from here" handoff.** At any node in the intent graph, the user can
   right-click and select "AI: Continue from here." This tells the agent to treat
   that node as the starting point for its next action, enabling seamless
   human-to-AI handoff mid-workflow.

5. **Escalation pathway.** When the AI is uncertain (confidence below a configured
   threshold), it marks the relevant node(s) as "Needs Review" (yellow highlight)
   and surfaces a message in the chat: "I'm not sure about [operation]. Here's
   what I tried and why I'm uncertain: [rationale]. Could you review?" This
   implements both the Confidence Signal and Escalation Pathway patterns.

### Code View

The bottom-right panel provides an optional CadQuery code view:

- **Read-only by default.** Shows the CadQuery DSL equivalent of the current intent
  graph. Syntax-highlighted, with line-by-line mapping to intent graph nodes
  (clicking a line highlights the corresponding node; clicking a node scrolls to
  the corresponding line).
- **Editable on toggle.** Power users can switch to edit mode. Code changes are
  parsed back into intent graph mutations. Parse errors are shown inline (red
  underline + tooltip).
- **AI inline assistance.** In edit mode, Cursor-style ghost text suggestions are
  available. Cmd+K allows describing an edit in natural language.
- **Hidden by default.** Beginners never see this panel unless they explicitly
  open it. The toggle is in the bottom bar: `[Chat] [Code] [Chat + Code]`.

### Undo/Redo Design

Undo in CadFlow must handle three cases:

1. **Single human operation.** Standard undo: remove the last node from the intent
   graph and recompute. Straightforward.

2. **Multi-step AI operation.** The AI's sequence of nodes is wrapped in a
   **transaction group**. Undo reverts the entire group as one unit. The group
   is visible in the feature list as an expandable item (e.g., "AI: Add mounting
   holes (4 operations)"). Expanding shows the individual operations for
   inspection, but undo/redo treats them as atomic.

3. **Mixed human+AI sequence.** If the user manually modified an AI-generated node
   and then undoes, only the user's modification is reverted (the AI node returns
   to its original AI-generated state). The undo stack respects chronological
   order of *edits*, not *nodes*.

The **preview-before-commit** pattern (required for Act+Confirm and recommended
for Propose) ensures that users see the full result of an AI action before it
enters the undo history. This prevents the frustrating pattern of "undo, undo,
undo, undo" to reverse a multi-step AI action that was committed incrementally.

### Responsive Layout Behavior

| Viewport Width | Layout Adaptation |
|---------------|-------------------|
| >= 1920px | All five zones available simultaneously |
| 1440-1919px | Right panel overlays viewport (drawer) instead of taking fixed space |
| 1024-1439px | Left panel collapses to icons-only rail; bottom panel is full-width (no split) |
| < 1024px | Not supported for modeling; read-only 3D viewer with chat |

### Keyboard-Driven Interaction

Following Cursor's keyboard-centric design:
- `/` — Open chat input (focus bottom panel)
- `Cmd+K` / `Ctrl+K` — Inline AI edit (context-sensitive: in viewport, operates
  on selection; in code editor, operates on selected code)
- `Tab` — Accept AI suggestion (ghost geometry or ghost code)
- `Esc` — Dismiss AI suggestion / cancel current operation
- `Cmd+Z` / `Ctrl+Z` — Undo (respects transaction groups)
- `Cmd+Shift+Z` / `Ctrl+Shift+Z` — Redo
- `G` — Toggle intent graph mode (feature list ↔ node graph)
- `C` — Toggle code panel
- `Space` — Toggle properties panel for selected object


## Consequences

### Positive

- **Broad accessibility.** Beginners interact via chat and the feature list;
  intermediates use direct manipulation and the properties panel; experts use the
  node graph and code editor. No user is forced into a modality that doesn't
  match their skill level.

- **AI as a first-class modality.** Unlike Option 1 (chat bolted on) or Option 2
  (AI as code assistant), the Hybrid layout gives AI interaction dedicated UI
  patterns (ghost geometry, autonomy dial, provenance attribution) that are
  deeply integrated with the modeling workflow.

- **Intent graph as unifying abstraction.** Every panel is a different view of the
  same underlying data structure. This means changes propagate consistently: an
  edit in the code view updates the feature list, the node graph, and the 3D
  viewport simultaneously. There is no synchronization ambiguity.

- **Extensible.** New interaction modalities (voice, AR/VR, haptic) can be added
  as additional input channels that produce intent graph mutations, without
  redesigning the UI layout.

- **Auditable AI.** The provenance-tagged intent graph provides a complete record
  of what the AI did, why (rationale attached to nodes), and with what confidence.
  This satisfies emerging regulatory interest in AI traceability for engineering
  artifacts.

### Negative

- **High implementation cost.** Five zones, four interaction modalities, two intent
  graph views, responsive layout behavior, and an escalating autonomy system
  represent significant frontend engineering effort. The MVP must aggressively
  scope what ships first (see Dependencies).

- **Performance risk.** Rendering ghost geometry in the viewport alongside actual
  geometry, while maintaining responsive panel resizing and real-time node graph
  layout, demands careful performance budgeting. WebGPU may be required for
  complex models.

- **Cognitive load risk.** Despite progressive disclosure, the *existence* of five
  zones and four modalities means documentation, tutorials, and onboarding must
  be carefully designed. A user who accidentally opens the node graph view may be
  overwhelmed.

### Risks and Mitigations

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| Ghost geometry confused with real geometry | Medium | High | Strong visual differentiation (transparency, dashed edges, "Suggestion" badge). User testing to validate. |
| Autonomy dial too complex to configure | Medium | Medium | Ship with sensible defaults. Most users will never change per-operation settings. Advanced settings behind "Show advanced" toggle. |
| Code ↔ intent graph round-tripping has edge cases | High | Medium | Start with read-only code view. Editable code view is a later milestone. Restrict editable code to a CadQuery subset that maps cleanly to intent graph operations. |
| Panel layout feels cramped on 1080p displays | Medium | High | Aggressive defaults: only left + center + top visible initially. All other panels are on-demand. Test on 1080p early and often. |
| Feature list cannot represent all DAG structures | Low | Low | Feature list shows topological sort of the DAG. Parallel branches appear sequentially (with a visual "parallel" marker). For full DAG comprehension, users switch to node graph mode. |
| AI suggestions are distracting/annoying | Medium | High | Suggestions are off by default. Users opt into suggestion mode. Frequency is throttled. Dismiss is always one keypress (Esc). |


## Dependencies

- **ADR-001 (Product Scope):** Confirms the target user personas and the intent
  graph as the core data model. This ADR's layout decisions assume the personas
  and architecture defined there.

- **Intent graph engine (backend):** The UI depends on a backend that can: create/
  read/update/delete intent graph nodes, compute geometry at any node, report
  node health/status, and support transaction groups for multi-step undo.

- **3D rendering library:** The viewport requires a WebGL/WebGPU-based renderer
  capable of displaying BREP geometry (not just meshes), ghost/transparent
  overlays, selection highlighting, and measurement annotations. Candidates:
  three.js with opencascade.js tessellation, CadQuery WASM viewer, or a custom
  renderer on WebGPU.

- **Node graph UI library:** The advanced DAG view requires a performant node graph
  renderer. Candidates: React Flow, xyflow, or a custom implementation using
  d3-dag for layout.

- **Frontend framework:** The panel layout assumes a modern component framework
  (React) with a flexible docking/panel system. Candidates: allotment (split
  panes), react-resizable-panels, or a custom layout manager.

### Implementation Phasing

Given the complexity, the UI should be built incrementally:

**Phase 1 (MVP):**
- Left panel: flat feature list (read-only)
- Center: 3D viewport with basic navigation (orbit, pan, zoom)
- Bottom: Chat panel (full-width, no code editor)
- AI interaction: Propose mode only (AI always shows draft, user accepts/rejects)
- Undo: single-operation undo only

**Phase 2:**
- Properties panel (right, on-demand)
- Feature list becomes interactive (edit, suppress, reorder)
- Code view (read-only)
- AI interaction: Add Act+Confirm mode
- Undo: transaction groups for multi-step AI operations

**Phase 3:**
- Node graph view (toggle from feature list)
- Code view becomes editable with round-tripping
- AI interaction: Full escalating autonomy ladder including Suggest and Autonomous
- Ghost geometry preview in viewport
- Visual attribution (provenance tags)

**Phase 4:**
- Autonomy dial (per-operation configuration)
- BREP spreadsheet inspector
- Profiler overlay on node graph
- Responsive layout for smaller screens
