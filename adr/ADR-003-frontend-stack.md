# ADR-003: Frontend Technology Stack and Architecture

## Status
Proposed

## Date
2026-04-07

## Context

CadFlow is a web-based, agentic CAD tool built on OpenCASCADE (OCCT) via CadQuery, with Claude as the AI backbone. This ADR selects the frontend technology stack: the UI framework, 3D rendering engine, state management approach, component library, WASM geometry strategy, and overall project architecture.

The frontend must satisfy several demanding, sometimes competing requirements:

- **3D CAD viewport:** Real-time display of tessellated BREP geometry with edge overlays, selection via raycasting, clipping planes, measurement annotations, and smooth orbit/pan/zoom navigation. This is not a product configurator or game — it is a precision engineering tool.
- **Agentic interaction:** Claude drives multi-step modeling operations through a tool-calling protocol. The UI must reflect agent state (thinking, acting, waiting for confirmation), stream intermediate results, and allow the user to interrupt, undo, or redirect the agent at any point.
- **Intent graph as source of truth:** The parametric feature tree (intent graph) lives on the server. The frontend renders a derived view and must stay in sync through incremental updates, not full re-renders.
- **Parameter editing:** Every feature node in the intent graph exposes typed parameters (lengths, angles, enum selections, reference picks). The property panel must bind reactively to selected nodes and propagate edits back to the server.
- **Future collaboration:** While V1 is single-user, the architecture should not preclude real-time multi-user editing. Data structures and state flow should be CRDT-compatible from the start.
- **Small team velocity:** A solo developer or two-person team must be able to iterate quickly. The stack must have excellent tooling, documentation, AI code-generation support, and a large enough ecosystem that common problems have existing solutions.
- **Performance at scale:** Models with 50-200 features and 100k-1M triangle meshes must render at 60fps with responsive UI. State updates from parameter edits must propagate without unnecessary re-renders.

The frontend is the user's primary interface with CadFlow. A wrong choice here affects every feature built on top of it for the lifetime of the project.

## Research Findings

### UI Framework Landscape (2025-2026)

#### React (v19+)

- **Market share:** ~39.5% of web developers (State of JS 2024, Stack Overflow Developer Survey 2025). Largest ecosystem of any frontend framework by an order of magnitude.
- **AI code generation:** All major AI-powered frontend tools generate React code: v0 (Vercel), Lovable, Bolt, Claude artifacts. This means the largest volume of React training data exists across all LLMs, directly benefiting CadFlow's agentic workflow where Claude generates UI components.
- **Three.js integration:** React Three Fiber (R3F) is the gold standard for declarative Three.js in React. It maps the Three.js scene graph to React's component tree, enabling JSX-based scene composition, React-managed lifecycle, and Suspense-based asset loading. R3F is maintained by Poimandres (pmndrs), the same group behind Zustand, Jotai, and drei (a utility library with 100+ Three.js helpers). As of 2025, R3F has 28k+ GitHub stars and is used in production by Vercel, Shopify, and numerous CAD/3D web apps.
- **Component libraries:** shadcn/ui + Radix UI provide accessible, composable, unstyled primitives with Tailwind CSS styling. This combination has become the de facto standard for new React projects, offering copy-paste ownership of components without the rigidity of opinionated design systems.
- **Ecosystem depth:** React has mature solutions for every concern — routing (React Router, TanStack Router), data fetching (TanStack Query, SWR), forms (React Hook Form, Conform), tables (TanStack Table), drag-and-drop (dnd-kit), virtual scrolling (TanStack Virtual), animation (Framer Motion), and accessibility (Radix, Ariakit).
- **Downsides:** React's virtual DOM introduces overhead compared to fine-grained reactivity systems. Re-render management requires awareness (memo, useMemo, useCallback). Bundle size is larger than Svelte or Solid. JSX is verbose for simple templates.

Sources: State of JS 2024 survey results; React Three Fiber GitHub repository (pmndrs/react-three-fiber); shadcn/ui documentation; Stack Overflow Developer Survey 2025.

#### Svelte 5

- **Reactivity model:** Svelte 5 introduced runes ($state, $derived, $effect), a compile-time fine-grained reactivity system. No virtual DOM — updates compile to direct DOM mutations. Excellent performance for UI-heavy applications.
- **Three.js integration:** Threlte is Svelte's equivalent of R3F. It provides declarative Three.js components for Svelte. However, Threlte's ecosystem is roughly 1/20th the size of R3F's — fewer helpers, fewer examples, fewer community extensions. As of early 2026, Threlte has ~2k GitHub stars versus R3F's 28k+.
- **Component libraries:** Melt UI and Bits UI provide headless component primitives, but the ecosystem is far smaller than React's. shadcn-svelte exists as a port but lags behind the React original.
- **AI code generation:** Improving. Claude and GPT-4 can generate Svelte 5 code, but with notably less training data than React. v0, Lovable, and Bolt do not target Svelte. For an agentic CAD tool where the AI agent may generate or modify UI, this gap matters.
- **Ecosystem:** SvelteKit is excellent for full-stack apps. But for the long tail of specialized libraries (drag-and-drop, virtual scroll, complex tables, 3D utilities), Svelte often requires writing custom solutions or adapting non-Svelte libraries.
- **Downsides:** Smaller hiring pool. Fewer Stack Overflow answers. Less battle-tested at scale in CAD-like applications. Runes are relatively new (late 2024) and best practices are still emerging.

Sources: Svelte 5 documentation (runes); Threlte GitHub repository (threlte/threlte); State of JS 2024 Svelte satisfaction and usage data.

#### SolidJS

- **Performance:** Best raw performance of any reactive framework in JS Framework Benchmark. Fine-grained reactivity with no virtual DOM, compiled signals, and near-zero overhead updates.
- **Three.js integration:** solid-three exists but is explicitly described by its maintainers as "not yet ready for production" as of early 2026. The library lacks the helper ecosystem (no equivalent to drei), has minimal documentation, and a very small contributor base.
- **Component libraries:** Kobalte provides headless primitives, roughly analogous to Radix. The ecosystem is the smallest of the three options.
- **AI code generation:** Least training data of any major framework. LLMs frequently confuse SolidJS patterns with React (since JSX syntax is shared but reactivity semantics differ fundamentally). This is a significant risk for an agentic workflow.
- **Downsides:** Smallest community, fewest production references, highest risk of hitting unsolved problems. The performance advantage over React is real but unlikely to be the bottleneck in a CAD application where GPU rendering dominates.

Sources: JS Framework Benchmark (krausest/js-framework-benchmark); solid-three GitHub repository; SolidJS ecosystem documentation.

### 3D Rendering

#### Three.js via React Three Fiber (R3F)

Three.js is the dominant WebGL library with 100k+ GitHub stars, extensive documentation, and a massive community. R3F wraps it in React's component model.

**CAD-specific precedent:**

- **three-cad-viewer:** The 3D viewer used by CadQuery's Jupyter integration. Built on Three.js. Renders tessellated BREP with edge display, supports clipping planes, measurement tools, and multiple view modes. Directly validates Three.js as viable for CadQuery geometry display. Source: bernhard-42/three-cad-viewer on GitHub.
- **Chili3D:** A full parametric CAD application built with OpenCascade.js (WASM) + Three.js + React. Demonstrates the complete pipeline from OCCT kernel in WASM through tessellation to Three.js rendering with a React UI. Source: xiangechen/chili3d on GitHub.
- **BREP.io:** A topology-aware CAD modeling tool built on Three.js. Implements face/edge/vertex selection, topology highlighting, and BREP-level interaction — exactly the kind of selection semantics CadFlow needs. Source: brep.io.
- **Zoo Modeling App (formerly KittyCAD):** Production CAD application built with React + Three.js + XState. Uses XState for command palette and modeling state machines. Demonstrates that React + Three.js scales to a real-world CAD product. Source: Zoo Design (zoo.dev), open-source modeling-app repository.

**Capabilities relevant to CadFlow:**

- Tessellated BREP display: Three.js renders indexed BufferGeometry from server-tessellated meshes. Edges can be rendered as LineSegments with separate materials for topology-aware highlighting.
- Selection via raycasting: R3F's `useThree` hook exposes the raycaster. Face, edge, and vertex picking is well-documented. drei provides `<Select>` and `<BVH>` components for optimized selection on large meshes.
- Clipping planes: Three.js natively supports clipping planes on materials. R3F wraps this declaratively. Used in three-cad-viewer for cross-section views.
- Measurement overlays: drei's `<Html>` component renders React DOM nodes positioned in 3D space — suitable for dimension labels, angle annotations, and distance readouts.
- Performance: With instanced meshes, LOD, and BVH acceleration (drei's `<Bvh>`), Three.js handles 1M+ triangle scenes at 60fps on modern hardware.

#### Babylon.js

- Stronger in game development and product visualization (e-commerce configurators, AR try-on).
- No React integration layer equivalent to R3F. `react-babylonjs` exists but has a fraction of R3F's adoption and ecosystem.
- No existing CAD viewer built on Babylon.js that approaches the maturity of three-cad-viewer or Chili3D.
- The rendering engine is technically capable, but the CAD-specific tooling would need to be built from scratch.
- Larger bundle size than Three.js (core Babylon.js is ~1MB minified vs Three.js ~600KB).

Sources: Babylon.js documentation; react-babylonjs GitHub repository; comparison data from WebGL framework surveys.

#### Server-Side vs. Client-Side Tessellation

| Aspect | Server-side (CadQuery/OCCT) | Client-side (OpenCascade.js WASM) |
|---|---|---|
| Bundle size | None (server handles it) | 10-30MB WASM binary |
| Memory | Server-constrained (ample) | 2-4GB browser limit |
| Startup time | Instant (no WASM init) | 2-5 second WASM load |
| Model complexity | Unlimited (server scales) | Limited by browser memory |
| Offline capable | No | Yes |
| Latency | Network round-trip per operation | Instant local computation |
| Memory management | Automatic (Python GC) | Manual (.delete() required for OCCT pointers) |
| Implementation effort | Lower (Python API, existing CadQuery) | Higher (C++ bindings, manual memory) |

For CadFlow V1, server-side tessellation is the pragmatic choice: CadQuery already runs on the server, the intent graph is server-authoritative, and avoiding the 10-30MB WASM bundle and manual memory management reduces frontend complexity significantly. Client-side WASM (via OpenCascade.js or replicad) can be added later for offline mode or latency-sensitive operations like local preview during dragging.

Sources: OpenCascade.js documentation and GitHub issues (donalffons/opencascade.js); replicad documentation (sgenoud/replicad); Chili3D architecture notes; SolidType project architecture.

### State Management

#### Multi-Layer State Architecture

A CAD application has fundamentally different state domains with different update frequencies, persistence requirements, and access patterns. A single store is inadequate. Research into existing CAD web apps reveals a layered approach:

**Layer 1 — Intent Graph (Server, Source of Truth)**

The parametric feature tree. Every modeling operation is a node with typed parameters and dependency edges. This lives on the server, persisted to a database. The frontend holds a read cache synchronized via WebSocket or SSE.

Why server-authoritative: The OCCT kernel runs server-side. Evaluation (rebuild) requires the full OCCT environment. The intent graph cannot be meaningfully edited without server validation. CRDT synchronization (for future collaboration) is simpler when the authoritative copy lives in one place.

**Layer 2 — 3D Scene State (Three.js, Derived)**

The scene graph (meshes, edges, materials, transforms) is derived from the intent graph via tessellation. It lives in Three.js's own scene graph, managed by R3F. This is not application state — it is a rendering projection of the intent graph.

R3F manages this naturally: when the intent graph updates, React re-renders the R3F components, which update Three.js objects. For large models, memoization and key-based reconciliation avoid unnecessary GPU uploads.

**Layer 3 — UI State (Zustand)**

Selection, hover highlights, panel visibility, viewport camera position, toolbar mode, undo/redo stack pointers, and other ephemeral UI state. Zustand is ideal here:

- Minimal API (create a store, use a hook, done)
- No boilerplate (unlike Redux)
- Supports selectors for fine-grained subscriptions (a component reading `selectedNodeId` does not re-render when `cameraPosition` changes)
- Integrates cleanly with R3F (Zustand is by the same team, pmndrs)
- DevTools support via zustand/middleware
- Tiny bundle (~1KB)

Source: Zustand documentation (pmndrs/zustand); Zoo Modeling App source code.

**Layer 4 — Agent/Tool State (XState)**

The Claude agent's lifecycle (idle, thinking, executing tool, awaiting confirmation, error) is a classic finite state machine. XState provides:

- Visual state chart editor for designing agent flows
- Guaranteed valid transitions (cannot go from "idle" to "awaiting confirmation" without passing through "thinking" and "tool execution")
- Built-in support for invoked promises (API calls to Claude), delayed transitions (timeouts), and parallel states (agent thinking while user continues navigating)
- Used by Zoo Modeling App for their command palette and modeling tool state machines

XState v5 introduces the actor model, where each agent session is an independent actor. This maps naturally to CadFlow's model: the user spawns an agent, the agent runs as an actor with its own state, and the UI observes the actor's state reactively.

Source: XState v5 documentation (statelyai/xstate); Zoo Modeling App open-source repository (KittyCAD/modeling-app).

**Layer 5 — Parameter State (Zustand Selectors / Jotai Atoms)**

When the user selects a feature node and opens the property panel, each parameter (e.g., extrude height, fillet radius) needs individual reactivity. Zustand selectors provide this: `useStore(s => s.intentGraph.nodes[selectedId].params.height)` only re-renders when that specific height changes.

Alternatively, Jotai atoms can model per-parameter state with automatic dependency tracking. However, mixing Zustand and Jotai adds conceptual overhead. For V1, Zustand selectors are sufficient. Jotai can be introduced later if parameter editing performance demands it.

Source: Jotai documentation (pmndrs/jotai); Zustand selector patterns.

### WASM Geometry (Deferred, but Architecture-Relevant)

**OpenCascade.js** compiles the OCCT kernel to WebAssembly. It is production-viable — Chili3D and SolidType both use it. Key constraints:

- 10-30MB bundle (must lazy-load, not in critical path)
- 2-4GB memory limit in browsers (WASM linear memory)
- Manual memory management: every OCCT object must be explicitly freed with `.delete()`. Failure to do so leaks memory rapidly. This is the single biggest source of bugs in OpenCascade.js applications.
- Must run in a Web Worker to avoid blocking the main thread during expensive operations (boolean ops can take 500ms+)

**replicad** wraps OpenCascade.js in a higher-level JavaScript API inspired by CadQuery's Python API. It handles some memory management automatically and provides a more ergonomic developer experience. However, it abstracts away some OCCT capabilities that CadFlow may need.

For CadFlow V1, WASM geometry is not required — the server handles all OCCT operations. But the architecture must not preclude it. Specifically:

- The tessellation data format sent from server to client should match what OpenCascade.js would produce (indexed triangle arrays + edge arrays + face-to-triangle mappings)
- The R3F components that render geometry should accept this format agnostically, without knowing whether it came from the server or a local WASM worker
- Web Worker communication patterns (postMessage, SharedArrayBuffer, Comlink) should be considered in the API layer design

Sources: OpenCascade.js GitHub (donalffons/opencascade.js); replicad GitHub (sgenoud/replicad); Chili3D source code; SolidType architecture documentation.

### Collaboration Architecture (Future, but Constraining)

**SolidType** is the most relevant reference implementation. It is a collaborative parametric CAD tool built with:
- Yjs CRDT for real-time synchronization
- ElectricSQL for local-first persistence
- OpenCascade.js in a Web Worker for geometry
- Three.js + React for rendering

SolidType demonstrates that the combination of Yjs + React + Three.js + OCCT works for collaborative CAD. CadFlow should adopt Yjs-compatible data structures for the intent graph from the start, even though V1 is single-user.

**Figma** uses a simpler last-writer-wins per-property model rather than true CRDTs. This works for their design tool but is insufficient for parametric CAD where feature ordering matters (reordering features in the tree changes the result).

Choosing Yjs-compatible data structures (Y.Map for node parameters, Y.Array for feature ordering, Y.Doc for the full intent graph) costs nothing in V1 (Zustand can wrap plain objects that match the Yjs schema) but enables dropping in Yjs synchronization later without restructuring state.

Sources: SolidType project (MaxSchrank/SolidType on GitHub); Yjs documentation (yjs/yjs); Figma engineering blog on multiplayer architecture.

### Project Architecture

**Feature-Sliced Design (FSD)** is an architectural methodology that organizes code by business domain rather than technical type. Layers:

```
app → pages → widgets → features → entities → shared
```

Each layer can only import from layers below it (widgets import from features and entities, never the reverse). This prevents the circular dependency hell common in CAD applications where "everything depends on everything."

FSD maps well to CAD:

- **widgets/** — Composite UI panels: viewport (R3F canvas + controls), feature tree (intent graph tree view), property panel (parameter editors), agent chat (Claude interaction), toolbar
- **features/** — User-initiated flows: create shape, sketch mode, boolean operation, selection, agent-initiated modification. Each feature encapsulates its UI, state slice, and API calls.
- **entities/** — Core data models: intent graph (nodes, edges, parameters), geometry (tessellated meshes, edge arrays), agent (session, message history, tool state)
- **shared/** — Framework-level code: shadcn/ui components, API client, utilities, type definitions

Reference implementations at this scale:
- SolidType: ~70,000 lines of code, React + Three.js + OCCT WASM
- Chili3D: OCCT WASM + Three.js, modular architecture
- Zoo Modeling App: React + Three.js + XState, open-source

Sources: Feature-Sliced Design documentation (feature-sliced.design); architectural analysis of SolidType, Chili3D, and Zoo Modeling App codebases.

## Options Considered

### Option 1: React + R3F + Zustand/XState + Server-Side Geometry

**Stack:**
- UI Framework: React 19 + TypeScript
- 3D Rendering: Three.js via React Three Fiber (R3F) + drei
- Component Library: shadcn/ui + Radix UI + Tailwind CSS
- State Management: Zustand (UI state) + XState v5 (agent orchestration)
- Geometry: Server-side tessellation (CadQuery/OCCT), geometry sent as binary buffers over WebSocket
- Build Tool: Vite
- Architecture: Feature-Sliced Design

**Pros:**
- Largest ecosystem by far — almost every problem has an existing solution or library
- R3F is the most mature declarative 3D framework, with direct precedent in CAD (three-cad-viewer, Chili3D, Zoo Modeling App)
- Best AI code generation support — v0, Lovable, Bolt, and Claude all generate high-quality React code. Directly benefits the agentic workflow where Claude generates or modifies UI components.
- Zustand + XState is proven for CAD: Zoo Modeling App uses exactly this combination
- shadcn/ui provides production-quality accessible components without framework lock-in (copy-paste, not dependency)
- Server-side geometry avoids the 10-30MB WASM bundle, manual memory management, and 2-4GB memory limit in V1
- Yjs-compatible state structure can be adopted incrementally
- Vite provides fast HMR and optimized builds with first-class React support

**Cons:**
- React's virtual DOM adds overhead compared to fine-grained reactivity (Svelte, Solid). For CadFlow, this overhead is negligible relative to GPU rendering costs, but it exists.
- JSX verbosity — more lines of code than Svelte templates for equivalent UI
- Re-render management requires discipline (memo, selectors, React Compiler helps but is not magic)
- Server-side geometry adds network latency to every modeling operation (mitigated by optimistic UI and streaming)

**Real-world precedent:**
- Zoo Modeling App (zoo.dev): Production CAD tool, React + Three.js + XState, open-source
- Chili3D: OCCT WASM + Three.js + React
- three-cad-viewer: CadQuery's own viewer, Three.js
- BREP.io: Topology-aware modeling, Three.js
- SolidType: Collaborative parametric CAD, React + Three.js + OCCT WASM + Yjs

### Option 2: Svelte 5 + Threlte + Client-Side WASM (OpenCascade.js)

**Stack:**
- UI Framework: Svelte 5 + TypeScript
- 3D Rendering: Three.js via Threlte
- Component Library: shadcn-svelte + Melt UI + Tailwind CSS
- State Management: Svelte runes ($state, $derived) + custom stores
- Geometry: Client-side OpenCascade.js in Web Worker
- Build Tool: Vite + SvelteKit
- Architecture: SvelteKit route-based

**Pros:**
- Svelte 5 runes provide truly fine-grained reactivity with zero runtime overhead — ideal for per-parameter binding in the property panel
- Smaller bundle size (no runtime library shipped to client)
- Cleaner template syntax for UI-heavy components (less boilerplate than JSX)
- Client-side WASM enables offline operation and zero-latency local preview
- SvelteKit provides full-stack capabilities (API routes, SSR, form actions) out of the box

**Cons:**
- Threlte ecosystem is ~1/20th the size of R3F. Many drei equivalents do not exist in Threlte and would need to be written from scratch (BVH acceleration, instanced mesh helpers, HTML-in-3D overlays).
- AI code generation support is significantly weaker. Claude generates reasonable Svelte 5 code but with less consistency than React. v0, Lovable, and Bolt do not support Svelte. For an agentic CAD tool, this is a material disadvantage.
- Client-side WASM adds 10-30MB to initial load, requires manual memory management (.delete() on every OCCT object), and is limited to 2-4GB browser memory. These are not theoretical concerns — they are the primary source of bugs in Chili3D and SolidType.
- No CAD application of comparable scope has been built with Svelte + Threlte. The path is uncharted.
- shadcn-svelte lags behind the React version by months. Ecosystem ports are consistently behind.
- Smaller community means fewer answers on Stack Overflow, fewer blog posts, fewer examples to reference.

**Real-world precedent:**
- No production CAD tool built with Svelte + Threlte exists as of early 2026. Threlte demos include data visualization and simple 3D scenes, but nothing approaching CAD complexity.

### Option 3: React + Babylon.js + Redux Toolkit + Hybrid Geometry

**Stack:**
- UI Framework: React 19 + TypeScript
- 3D Rendering: Babylon.js via react-babylonjs
- Component Library: MUI (Material UI) or Ant Design
- State Management: Redux Toolkit (RTK) + RTK Query
- Geometry: Hybrid (server-side primary, client-side WASM for preview)
- Build Tool: Vite
- Architecture: Domain-driven folder structure

**Pros:**
- Babylon.js has a built-in inspector, physics engine, and advanced rendering features (PBR, post-processing) out of the box
- Redux Toolkit is battle-tested at massive scale (used at Meta, Spotify, etc.) with excellent DevTools
- Hybrid geometry gives the best of both worlds: server for complex operations, WASM for instant local feedback
- MUI/Ant Design provide complete, polished component sets with less customization effort

**Cons:**
- react-babylonjs has a fraction of R3F's adoption. No equivalent to drei. The declarative wrapper is less mature and less idiomatically React.
- Babylon.js has no existing CAD viewer ecosystem. three-cad-viewer, Chili3D, BREP.io — all use Three.js. Choosing Babylon.js means building all CAD-specific rendering (edge display, topology highlighting, BREP-aware selection) from scratch.
- Redux Toolkit is overkill for a small team. The boilerplate (slices, actions, reducers, selectors, thunks) slows development velocity compared to Zustand's minimal API. RTK's value proposition — predictability at scale — is not needed when the team is 1-2 people.
- MUI and Ant Design are opinionated design systems. Customizing them to match a CAD tool's dense, information-rich UI (think SolidWorks or Fusion 360, not a SaaS dashboard) fights the framework rather than leveraging it.
- Hybrid geometry doubles the implementation surface: server tessellation + WASM tessellation + synchronization between them. This complexity is not justified in V1.
- Larger combined bundle size (Babylon.js core ~1MB + MUI/Ant + Redux + potentially WASM)

**Real-world precedent:**
- No production CAD tool uses Babylon.js for BREP/parametric CAD rendering. Babylon.js is well-established in product configurators (e-commerce 3D viewers) and game-like experiences, but these are fundamentally different from engineering CAD.

## Decision

**We choose Option 1: React + React Three Fiber + Zustand/XState + server-side geometry.**

### Rationale

The decision rests on four pillars:

**1. Proven CAD precedent.** Every significant open-source web-based CAD tool built in the last three years uses Three.js for rendering: three-cad-viewer (CadQuery's own viewer), Chili3D, BREP.io, Zoo Modeling App, SolidType. React Three Fiber is the dominant way to use Three.js in React. This is not a speculative choice — it is the demonstrated industry path.

**2. AI-first development velocity.** CadFlow is an agentic tool — both for users (Claude drives modeling operations) and for developers (Claude assists in writing the codebase). React has the most AI training data, the best code generation tooling, and the most consistent LLM output of any frontend framework. When the agent generates a React component with R3F scene elements, it draws on thousands of real-world examples. Svelte 5 runes and SolidJS signals have a fraction of this training data, leading to more hallucinations and less reliable code generation.

**3. Ecosystem depth eliminates yak-shaving.** A CAD frontend needs accessible UI primitives (shadcn/ui), 3D helpers (drei), state management (Zustand), state machines (XState), drag-and-drop (dnd-kit), virtual scrolling (TanStack Virtual), and dozens of other utilities. React's ecosystem provides production-quality solutions for all of these. With Svelte or Solid, many of these would need to be built, ported, or adapted — time spent on plumbing instead of product.

**4. Pragmatic geometry strategy.** Server-side tessellation leverages the existing CadQuery/OCCT Python environment, avoids the WASM complexity tax (10-30MB bundle, manual memory management, 2-4GB memory limit), and keeps the intent graph unambiguously server-authoritative. The architecture explicitly does not preclude adding OpenCascade.js later for offline mode or local preview — the tessellation data format and R3F components are designed to be source-agnostic.

### Specific Technology Versions

| Technology | Version | Purpose |
|---|---|---|
| React | 19.x | UI framework |
| React Three Fiber | 9.x | Declarative Three.js |
| Three.js | 0.170+ | 3D rendering engine |
| drei | 10.x | R3F helper library |
| Zustand | 5.x | UI state management |
| XState | 5.x | Agent state machines |
| shadcn/ui | latest | UI component primitives |
| Radix UI | latest | Accessible headless components |
| Tailwind CSS | 4.x | Utility-first styling |
| TypeScript | 5.7+ | Type safety |
| Vite | 6.x | Build tool and dev server |
| TanStack Query | 5.x | Server state / data fetching |

### Project Structure

```
src/
  app/                    # App shell, providers, routing
    providers.tsx         # React context providers (theme, query client)
    router.tsx            # Route definitions
    layout.tsx            # Root layout (sidebar, viewport, panels)

  widgets/
    viewport/             # 3D viewport
      Viewport.tsx        # R3F Canvas wrapper
      CadScene.tsx        # Scene composition (lights, grid, axes)
      GeometryRenderer.tsx  # Renders tessellated BREP meshes
      EdgeRenderer.tsx    # Renders topology edges as LineSegments
      SelectionOverlay.tsx  # Raycasting-based pick handling
      CameraControls.tsx  # Orbit, pan, zoom controls
      ClippingPlane.tsx   # Cross-section visualization
      MeasurementLabel.tsx  # 3D-positioned HTML dimension labels

    feature-tree/         # Intent graph tree view
      FeatureTree.tsx     # Tree component with drag-to-reorder
      FeatureNode.tsx     # Individual tree node (icon, name, status)
      TreeContextMenu.tsx # Right-click actions (suppress, edit, delete)

    property-panel/       # Parameter editors
      PropertyPanel.tsx   # Panel shell with selected-node binding
      ParamEditor.tsx     # Dispatcher: routes param type to editor
      NumberInput.tsx     # Numeric parameter with unit display
      EnumSelect.tsx      # Dropdown for enum parameters
      ReferenceInput.tsx  # Geometry pick reference (face, edge)

    agent-chat/           # Claude agent interaction
      AgentChat.tsx       # Chat message list with streaming
      AgentToolCall.tsx   # Tool invocation display (what the agent is doing)
      AgentConfirm.tsx    # User confirmation prompt for destructive ops
      AgentStatus.tsx     # Thinking/acting/idle indicator

    toolbar/              # Tool selection
      Toolbar.tsx         # Tool palette (sketch, extrude, fillet, etc.)
      ToolButton.tsx      # Individual tool with icon and shortcut hint

  features/
    create-shape/         # Primitive creation flows
      useCreateBox.ts     # Box creation hook (click-drag-confirm)
      useCreateCylinder.ts
      CreateShapePreview.tsx  # Transparent preview mesh during creation

    sketch/               # 2D sketch mode
      SketchCanvas.tsx    # 2D overlay on selected plane
      SketchTools.tsx     # Line, rectangle, circle, arc tools
      ConstraintDisplay.tsx  # Visual constraint indicators

    boolean-op/           # Boolean operations
      useBooleanOp.ts     # Cut/fuse/intersect flow
      BooleanPreview.tsx  # Preview of boolean result

    select/               # Selection and picking
      useSelection.ts     # Raycasting + selection state
      SelectionHighlight.tsx  # Highlight materials for selected faces/edges

    agent-action/         # Agent-initiated modifications
      useAgentAction.ts   # Hook connecting XState actor to intent graph
      AgentActionOverlay.tsx  # Visual indicator of what agent is modifying

  entities/
    intent-graph/         # Core data model
      types.ts            # IntentNode, IntentEdge, Parameter types
      store.ts            # Zustand store for intent graph cache
      sync.ts             # WebSocket sync with server
      selectors.ts        # Derived data (selected node params, dependency chain)

    geometry/             # Tessellated mesh management
      types.ts            # TessellationResult, MeshData, EdgeData types
      store.ts            # Geometry cache (Map<nodeId, MeshData>)
      loader.ts           # Binary buffer parsing (server → Three.js BufferGeometry)

    agent/                # Agent state
      machine.ts          # XState state machine definition
      types.ts            # AgentState, AgentEvent, AgentContext types
      actor.ts            # Actor spawning and lifecycle

  shared/
    ui/                   # shadcn/ui components (copied, not imported)
      button.tsx
      dialog.tsx
      dropdown-menu.tsx
      input.tsx
      scroll-area.tsx
      tooltip.tsx
      ... (generated by shadcn CLI)

    api/                  # Server communication
      client.ts           # HTTP/WebSocket client
      types.ts            # API request/response types
      hooks.ts            # TanStack Query hooks for server state

    lib/                  # Utilities
      geometry-utils.ts   # Buffer parsing, mesh helpers
      math-utils.ts       # Vector/matrix utilities
      format-utils.ts     # Unit formatting, number display
```

## Consequences

### Positive

- **Immediate productivity:** React + R3F + Zustand is the most well-documented, most-exampled stack available for web-based 3D applications. The team can reference three-cad-viewer, Chili3D, and Zoo Modeling App for working patterns rather than inventing solutions.
- **Agent-friendly codebase:** Claude generates more correct React code than any other framework. Components, hooks, and R3F scene elements can be generated or modified by the agent with high reliability. This accelerates both development and the agentic user experience.
- **Clean state separation:** The five-layer state architecture (intent graph, scene, UI, agent, parameters) prevents the "god store" anti-pattern. Each layer has a clear owner, update frequency, and persistence model.
- **Incremental WASM adoption path:** Server-side geometry in V1 keeps the frontend simple. The tessellation data format and R3F rendering components are designed to accept geometry from any source. OpenCascade.js can be added in a Web Worker later without restructuring the frontend.
- **Collaboration-ready data model:** Structuring intent graph state as Maps and Arrays (matching Yjs Y.Map and Y.Array) means future Yjs integration is a synchronization layer addition, not a rewrite.
- **Strong typing throughout:** TypeScript + Zustand selectors + XState typegen provide end-to-end type safety from API responses through state management to component props.

### Negative

- **React re-render tax:** React's reconciliation model means the developer must think about re-renders. In a CAD app where dozens of parameters update during drag operations, poorly memoized components can cause jank. Mitigation: Zustand selectors, React.memo on expensive components, R3F's automatic invalidation (it only re-renders the canvas when the scene changes, not on every React re-render).
- **Three.js learning curve:** Three.js is a large library with its own mental model (scene graph, materials, geometry, cameras, renderers). R3F abstracts much of this, but debugging requires understanding the underlying Three.js objects. Mitigation: drei provides high-level abstractions for 90% of use cases; Three.js has the best documentation of any 3D library.
- **Server dependency for all geometry:** V1 cannot work offline. Every modeling operation requires a server round-trip. Mitigation: optimistic UI (show predicted results immediately, reconcile when server responds); WebSocket streaming for progressive mesh delivery; future WASM fallback.
- **Bundle size:** React + R3F + Three.js + drei + Zustand + XState + shadcn/ui + Tailwind CSS = estimated 250-350KB gzipped for the initial load. This is larger than a Svelte equivalent. Mitigation: code splitting (lazy-load feature modules), tree shaking (Vite eliminates unused drei helpers), and the fact that CadFlow is a professional tool where users expect a brief initial load.

### Risks and Mitigations

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| R3F performance bottleneck with large models (100k+ triangles per feature, 50+ features) | Medium | High | Use drei's `<Bvh>` for raycasting acceleration, `<Instances>` for repeated geometry, `<Lod>` for distance-based detail, and manual BufferGeometry for hot paths. Profile early with realistic model sizes. |
| Zustand store grows unwieldy as features multiply | Medium | Medium | Feature-Sliced Design enforces store slicing by domain. Each entity owns its store. Use Zustand's `subscribeWithSelector` to avoid unnecessary subscriptions. Migrate to Jotai atoms for fine-grained state if needed. |
| XState v5 actor model is relatively new (released 2024) | Low | Medium | XState v5 is stable and well-documented. The actor model is a simplification over v4, not an experimental feature. Zoo Modeling App validates it for CAD use. Fallback: use Zustand + custom state machine if XState proves problematic. |
| Three.js breaking changes in minor releases | Low | Low | Pin Three.js version. R3F and drei version-lock against Three.js. Update deliberately, not automatically. |
| Server-side tessellation latency frustrates users during rapid parameter editing | Medium | High | Debounce parameter updates (100-200ms). Show optimistic interpolated mesh during edits. Stream partial tessellation results. Implement server-side caching for unchanged features. Future: add WASM preview for instant local feedback. |
| React 19 concurrent features interact poorly with R3F | Low | Medium | R3F v9 is designed for React 19 compatibility. Use `useDeferredValue` for non-critical updates. Opt out of concurrent features in the R3F canvas subtree if needed. |

## Dependencies

### Hard Dependencies (must exist before frontend work begins)

- **Server tessellation API:** The backend must expose an endpoint that accepts intent graph node IDs and returns tessellated geometry as binary buffers (positions, normals, indices, edge positions, face-to-triangle maps). Format: Protocol Buffers or a custom binary format for minimal parsing overhead. See ADR-001 for scope of supported operations.
- **WebSocket infrastructure:** Real-time synchronization of intent graph changes (server pushes updates when the graph is modified by agent actions or parameter rebuilds). The frontend state layer depends on this.
- **Claude tool-calling API:** The agent chat widget requires a streaming API endpoint that relays Claude's tool calls and allows the frontend to send user confirmations back.

### Soft Dependencies (can be deferred, but should be planned)

- **Intent graph schema definition:** TypeScript types for intent graph nodes, edges, and parameters should be generated from a shared schema (e.g., JSON Schema, Protobuf definitions) to ensure server-client type consistency. Can start with hand-written types and add code generation later.
- **Authentication and session management:** V1 can start with a single-user local session. User auth is needed before any multi-user or deployment features.
- **OpenCascade.js WASM build:** Needed for V1 — hybrid architecture decision requires OpenCascade.js in a Web Worker for lightweight client-side operations (measurements, clipping, simple preview). Server handles heavy computation (booleans, complex features, CFD). The WASM bundle (~10-30MB) should be lazy-loaded after initial app render. Manual memory management (.delete() on every OCCT object) is required — consider a wrapper with ref-counting or a dispose pool. Reference implementations: SolidType, Chili3D.
- **Yjs integration:** The intent graph store is structured to be Yjs-compatible, but actual Yjs synchronization is a V2+ feature dependent on collaboration requirements.

### External Library Versions and Compatibility Matrix

| Library | Min Version | Depends On | Notes |
|---|---|---|---|
| React | 19.0 | — | React 19 for `use`, Actions, and improved Suspense |
| React Three Fiber | 9.0 | React 19, Three.js 0.170+ | Version-locked to Three.js range |
| drei | 10.0 | R3F 9.x | Helper library, version-locked to R3F |
| Three.js | 0.170 | — | Pin specific minor version, update deliberately |
| Zustand | 5.0 | React 18+ | No React 19-specific features needed |
| XState | 5.0 | — | Framework-agnostic, React bindings via @xstate/react |
| Tailwind CSS | 4.0 | — | CSS-first configuration (v4 uses CSS, not JS config) |
| TypeScript | 5.7+ | — | Needed for satisfies, const type params, decorator metadata |
| Vite | 6.0 | — | React plugin, WASM plugin (future) |
| TanStack Query | 5.0 | React 18+ | Server state management for non-realtime data |
