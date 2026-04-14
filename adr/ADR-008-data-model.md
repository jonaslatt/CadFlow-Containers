# ADR-008: Geometry Data Model and Persistence

## Status

Proposed

## Date

2026-04-07

## Context

CadFlow is a web-based agentic CAD tool built on OpenCASCADE (OCCT) / CadQuery
with Claude AI acting as the design agent. The **intent graph** is the core data
model: a directed acyclic graph (DAG) of design-intent nodes that encode *what*
the user wants, not *how* the kernel constructs it. Each node may reference
geometry, constraints, boundary conditions, materials, or simulation metadata.

We need to decide:

1. **Primary persistence format** -- how the intent graph and its associated
   geometry are stored on disk and in the database.
2. **Geometry caching strategy** -- when and how to store intermediate BREP
   results so we avoid replaying the entire graph on every load.
3. **History / versioning model** -- how to track changes over time, support
   undo/redo, and enable branching.
4. **Exchange formats** -- which formats to support for import, export, and
   browser visualization.
5. **Metadata attachment** -- where boundary conditions, materials, units, and
   simulation parameters live in the data model.
6. **Storage backend roadmap** -- what to use in Phase 1 (MVP) vs. Phase 2
   (multi-user).

These decisions are foundational. Every other subsystem -- the AI agent, the
constraint solver, the mesher, the CFD pipeline -- reads from or writes to this
data model.

### Constraints

- CadFlow targets **CFD preprocessing** as its first vertical. Boundary
  conditions on specific faces, volumetric regions, and mesh-sizing metadata
  are first-class concerns.
- The MVP is a **single-user desktop/local application**. Multi-user
  collaboration is a Phase 2 concern.
- CadQuery scripts are already a form of parametric model ("code-as-model").
  The intent graph must coexist with, and eventually supersede, raw scripts.
- Browser-side visualization requires a lightweight mesh format (glTF or
  equivalent). The full BREP stays server-side.
- We want **git-friendly** artifacts wherever possible so that designs can be
  version-controlled with standard developer tools.

---

## Research Findings

### Professional CAD Persistence Strategies

#### Onshape (Cloud-native CAD)

Onshape pioneered a **database-driven, append-only microversion** architecture
[1]. Every edit creates a new immutable microversion. Versions and branches work
like git: lightweight pointers into a DAG of microversions. There is no "save"
button -- every state is automatically persisted and addressable by ID.

Key takeaways for CadFlow:
- Append-only history is simple to implement and reason about.
- Every historical state is recoverable without explicit snapshots.
- The microversion concept maps naturally to intent-graph commits.

Sources:
- [1] Onshape engineering blog, "How Onshape Stores Your Data" (2015).
  Describes the append-only microversion architecture and git-style branching.
- [2] J. Hirschtick, keynote at COFES 2016: "Every state is a version."

#### FreeCAD (Open-source parametric CAD)

FreeCAD stores projects as `.FCStd` files, which are **ZIP archives**
containing [3]:

| File                | Purpose                                     |
|---------------------|---------------------------------------------|
| `Document.xml`      | Parametric feature definitions (the "tree") |
| `GuiDocument.xml`   | View properties, colors, visibility         |
| `*.brp`             | Cached BREP per object                      |

The cached `.brp` files are the critical insight: FreeCAD **pre-caches the BREP
output of every feature** so that opening a project does not require replaying
the entire feature tree. If a cache is missing or stale, FreeCAD regenerates
from the parametric definition.

Key takeaways for CadFlow:
- Per-node BREP caching eliminates cold-start replay.
- The cache is disposable -- the parametric definition is the source of truth.
- ZIP-archive approach is simple but not git-friendly (binary diffs).

Sources:
- [3] FreeCAD documentation, "File Format FCStd" (freecad.org/wiki).
- [4] FreeCAD source: `src/App/Document.cpp`, save/restore logic.

#### SolidWorks (Industry-standard desktop CAD)

SolidWorks uses an **OLE compound document** container. The feature tree is a
construction history; opening a file replays features through the Parasolid
kernel to regenerate geometry [5]. This replay-based approach means that
SolidWorks files are tightly coupled to the kernel version.

Key takeaways for CadFlow:
- Replay-based regeneration is the industry norm but is slow for large models.
- Kernel-version coupling is a real risk (applies to OCCT as well).
- BREP caching (as FreeCAD does) mitigates the replay cost.

Sources:
- [5] SolidWorks API documentation, "Document Structure."
- [6] M. Lombard, *SolidWorks Bible* (Wiley, 2019), ch. 3: file formats.

---

### Exchange Format Landscape

#### STEP AP242

STEP AP242 is the **gold standard for CAD data exchange** [7]. It supports:
- Exact geometry (B-rep)
- Units, materials, tolerances
- Product Manufacturing Information (PMI)
- Assembly structure

Limitations: STEP does **not** preserve parametric history. A STEP file is a
snapshot of the final geometry. For CadFlow, STEP is the right choice for
interoperability with external tools (meshing, CFD solvers, other CAD systems)
but is not suitable as the primary persistence format.

Sources:
- [7] ISO 10303-242:2020, "Managed model-based 3D engineering."
- [8] CAx Implementor Forum, STEP AP242 recommended practices (2023).

#### BREP (OCCT Native)

OCCT's native BREP format stores the **exact boundary representation** in ASCII
or binary form [9]. Within the same OCCT major version, BREP round-trips are
**lossless** -- every edge, face, and tolerance value is preserved exactly.

Limitations:
- Tied to OCCT version (minor format changes between releases).
- No metadata support (no materials, units, or boundary conditions).
- ASCII format is human-readable but large; binary is compact but opaque.

For CadFlow, BREP is the right format for **per-node geometry caching** because
it preserves OCCT topology identifiers needed for face selection and boundary
condition assignment.

Sources:
- [9] OCCT documentation, "BRep Format Description" (dev.opencascade.org).
- [10] CadQuery source: `occ_impl/exporters/utils.py`, BREP export path.

#### STL (Triangulated Mesh)

STL stores **triangulated surface meshes** with no metadata [11]. It is the
input format for snappyHexMesh (OpenFOAM's meshing utility) and most 3D
printing pipelines. CadFlow must support STL export for CFD meshing workflows.

Sources:
- [11] OpenFOAM User Guide, "snappyHexMesh" -- requires STL/OBJ surface input.

#### glTF 2.0

glTF is the **"JPEG of 3D"** [12] -- a compact, GPU-ready format optimized for
browser rendering. The `EXT_mesh_features` extension supports per-face metadata
(e.g., face group IDs for boundary condition highlighting) [13].

For CadFlow, glTF is the right format for **browser-side visualization**. The
server tessellates the BREP into glTF; the client renders it with Three.js or
Babylon.js.

Sources:
- [12] Khronos Group, "glTF 2.0 Specification" (2021).
- [13] Khronos Group, "EXT_mesh_features" extension specification.

#### IGES

IGES is a **legacy format** dating to the 1980s [14]. It has known precision
issues and is being phased out by the industry in favor of STEP. CadFlow should
support IGES import (via OCCT's built-in reader) but should not invest in IGES
as an export target.

Sources:
- [14] IGES/PDES Organization, "End of IGES maintenance" announcement (2014).

---

### CadQuery Serialization Characteristics

CadQuery's defining feature is that **the script IS the parametric model** [15].
A CadQuery script is a Python program that constructs geometry through a fluent
API. This "code-as-model" approach means:

- The parametric definition is already text (Python source), which is
  inherently git-friendly.
- CadQuery can export to: STEP, STL, BREP, DXF, VRML, AMF, 3MF [16].
- BREP round-trip within the same OCCT version is lossless.
- CadQuery does **not** have a native "project file" format -- scripts are
  standalone.

CadFlow's intent graph extends the code-as-model concept: instead of a flat
script, the design is a **graph of intent nodes**, each of which may generate
CadQuery operations. The intent graph is the parametric definition; CadQuery is
the execution engine.

Sources:
- [15] CadQuery documentation, "CadQuery Concepts" (cadquery.readthedocs.io).
- [16] CadQuery source: `occ_impl/exporters/`, supported format list.

---

### Storage Backend Analysis

#### Neo4j (Graph Database)

Neo4j is purpose-built for graph data with Cypher query language [17]. However,
CadFlow's intent graphs are small -- **hundreds of nodes, not millions**. Neo4j
adds significant operational complexity (JVM, separate server process, backup
tooling) for a graph that fits comfortably in memory.

Verdict: **Overkill for CadFlow's graph size.** Revisit only if graph queries
become a bottleneck, which is unlikely given the node count.

Sources:
- [17] Neo4j documentation, "Graph Database Concepts."
- [18] D. Bechberger & J. Perryman, *Graph Databases in Action* (Manning, 2020).

#### PostgreSQL with JSONB

PostgreSQL's JSONB type supports **indexing, partial updates, and containment
queries** on JSON documents [19]. Recursive CTEs can traverse DAG structures
stored in relational tables. This is a strong fit if CadFlow already uses
PostgreSQL for user accounts, project metadata, or collaboration features.

Verdict: **Good fit for Phase 2** (multi-user, server-deployed). Not justified
for a single-user MVP.

Sources:
- [19] PostgreSQL documentation, "JSON Types" (postgresql.org/docs/16).
- [20] PostgreSQL documentation, "WITH Queries (Common Table Expressions)."

#### SQLite

SQLite offers **zero-deployment embedded storage** with full SQL support [21].
The closure table pattern handles DAG traversal. However, SQLite is
**single-writer** -- concurrent writes from the AI agent and the UI would
require careful serialization.

Verdict: **Viable for Phase 1** but adds complexity over plain files with no
clear benefit for single-user use.

Sources:
- [21] SQLite documentation, "Appropriate Uses For SQLite" (sqlite.org).
- [22] B. Karwin, *SQL Antipatterns* (Pragmatic, 2010), ch. 3: closure tables.

#### JSON Files

Plain JSON files are the **simplest possible persistence** [23]. They are:
- Human-readable and inspectable.
- Git-friendly (standard text diff and merge).
- Zero-dependency (no database server, no schema migrations).
- Easy to back up (copy the directory).

Limitations:
- No concurrent-write safety (acceptable for single-user Phase 1).
- No indexing or query optimization (acceptable for small graphs).
- Schema evolution must be handled in application code.

Verdict: **Best fit for Phase 1.** Migrate to PostgreSQL JSONB when multi-user
support is needed -- the JSON structure translates directly.

Sources:
- [23] T. Bray, "The JavaScript Object Notation (JSON) Data Interchange
  Format," RFC 8259 (2017).

---

### Versioning Strategy

The industry consensus is moving toward **text-based parametric definitions
with binary regeneration** [24]:

> "Elevate design logic into merge-friendly text; regenerate binaries in CI."

CadFlow has a structural advantage here: the intent graph IS text (JSON).
Standard `git diff` and `git merge` apply directly. Binary artifacts (BREP
caches, glTF meshes, STL exports) are derived and can be regenerated from the
intent graph at any time.

Onshape's append-only history model [1] maps cleanly to an event log:
- Each change to the intent graph is an **event** (node added, edge modified,
  parameter changed, boundary condition assigned).
- The current state is the **reduction** of all events.
- Any historical state is recoverable by replaying events up to a given point.
- Events are small, text-based, and append-only -- ideal for git.

Sources:
- [24] M. Fowler, "Event Sourcing" (martinfowler.com, 2005).
- [25] G. Young, "CQRS and Event Sourcing" (cqrs.files.wordpress.com, 2010).

---

### Metadata and Simulation Context

For CFD preprocessing, the following metadata must be first-class:

| Metadata Type          | Storage Location                        |
|------------------------|-----------------------------------------|
| Boundary conditions    | Intent graph edges on face-selector nodes |
| Materials              | Metadata on body/volume nodes           |
| Units                  | Explicit per-project, default SI        |
| Mesh sizing            | Metadata on face/edge/region nodes      |
| Simulation parameters  | Sibling document or dedicated node type |

CadQuery works in **millimeters by default** [16]. CFD solvers typically expect
**SI units (meters)**. The data model must store units explicitly and convert at
export boundaries.

OCCT provides the **OCAF/XDE framework** for attaching labels, colors,
materials, and other attributes to topological entities [26]. CadFlow can
leverage XDE for STEP export with PMI, but the intent graph (not XDE) is the
authoritative source for metadata.

Sources:
- [26] OCCT documentation, "XDE User's Guide" (dev.opencascade.org).
- [27] OpenFOAM User Guide, "Boundary Conditions" -- metadata needed for
  CFD case setup.

---

## Options Considered

### Option 1: File-based BREP/STEP with Parametric Scripts

This is the **OpenSCAD / vanilla CadQuery approach**: the parametric model is a
script file, and geometry is exported to BREP or STEP files on disk.

```
project/
  model.py          # CadQuery script (parametric definition)
  output/
    part.step       # Exported STEP geometry
    part.stl        # Exported STL mesh
```

**Advantages:**
- Simplest possible approach.
- Scripts are git-friendly.
- No custom data model to maintain.

**Disadvantages:**
- No graph structure. The script is a linear sequence of operations, not a DAG
  of intent nodes. This makes partial recomputation impossible.
- No metadata attachment points. Boundary conditions and materials cannot be
  associated with specific faces or bodies in a structured way.
- No history model beyond git commits on the script file.
- AI agent has no structured representation to reason about -- it must parse
  and modify raw Python source.
- Does not scale to assemblies or multi-body designs.

**Verdict:** Insufficient for CadFlow's intent-graph architecture. This is what
CadQuery does today; CadFlow needs to go beyond it.

---

### Option 2: Graph Database (Neo4j) with BREP Cache

Store the intent graph natively in Neo4j. Each node is a Neo4j node; each edge
is a Neo4j relationship. BREP geometry is cached in the filesystem or a blob
store, referenced by node ID.

```
Neo4j: (intent nodes) --[edges]--> (intent nodes)
Filesystem: /cache/{node_id}.brep
```

**Advantages:**
- Native graph queries (Cypher) for traversal, pathfinding, and pattern
  matching.
- Proven at scale for graph workloads.
- Rich ecosystem (visualization, monitoring, clustering).

**Disadvantages:**
- **Operationally complex.** Neo4j requires a JVM, a separate server process,
  its own backup/restore tooling, and monitoring. This is heavy for a
  single-user desktop application.
- **Overkill for the graph size.** CadFlow intent graphs have hundreds of
  nodes, not millions. In-memory traversal of a JSON DAG is effectively
  instant.
- **Not git-friendly.** Neo4j's storage is a binary format. Design history
  cannot be tracked with standard developer tools.
- **Vendor lock-in.** Neo4j's query language (Cypher) and storage engine are
  proprietary (Community Edition is GPL, Enterprise is commercial).
- **Migration friction.** Moving data in and out of Neo4j requires ETL tooling.

**Verdict:** The operational cost far exceeds the benefit at CadFlow's scale.
The graph query capabilities are not needed when the entire graph fits in a
single JSON file.

---

### Option 3: Intent Graph as JSON with BREP Caching and Append-only History (Recommended)

Store the intent graph as a **JSON document**. Cache BREP geometry **per node**
on the filesystem (following the FreeCAD pattern). Track changes via an
**append-only event log** (following the Onshape pattern).

```
project/
  intent-graph.json          # Current state of the intent graph
  events/
    000001.json              # Event: initial graph creation
    000002.json              # Event: added extrude node
    000003.json              # Event: assigned boundary condition
    ...
  cache/
    {node_id}.brep           # Cached BREP per node
    {node_id}.glb            # Cached glTF per node (for browser)
  exports/
    assembly.step            # STEP AP242 export (on demand)
    assembly.stl             # STL export (on demand)
  project.json               # Project metadata (units, materials, etc.)
```

**Advantages:**
- **Git-friendly.** The intent graph and event log are JSON text files.
  Standard `git diff` shows exactly what changed. Standard `git merge` works
  for non-conflicting edits.
- **Simple to implement.** No database server, no schema migrations, no
  deployment dependencies. Read JSON, write JSON.
- **Per-node BREP caching.** Avoids full graph replay on load. When a node
  changes, only its downstream subgraph needs recomputation. Cache misses
  trigger CadQuery re-evaluation of the affected subgraph.
- **Append-only history.** Every state is recoverable. Undo is trivial
  (revert to previous event). The event log is a natural fit for the AI
  agent's action history.
- **Structured metadata.** Boundary conditions, materials, units, and mesh
  parameters are nodes or annotations in the graph -- the AI agent can query
  and modify them through the same graph API.
- **Migration path.** JSON translates directly to PostgreSQL JSONB columns.
  The event log translates to an events table. Phase 2 migration is
  straightforward.
- **Debuggable.** A developer can open `intent-graph.json` in any text editor
  and understand the design state. BREP caches can be viewed in FreeCAD or
  any OCCT-based viewer.

**Disadvantages:**
- No concurrent-write safety (acceptable for single-user Phase 1).
- No built-in indexing (acceptable for small graphs; in-memory lookup is O(n)
  on hundreds of nodes, which is sub-millisecond).
- Schema evolution must be handled in application code (mitigated by explicit
  schema versioning in the JSON).
- BREP caches are OCCT-version-dependent (mitigated by treating caches as
  disposable and regenerating on version mismatch).

---

## Decision

**We adopt Option 3: Intent Graph as JSON with BREP Caching and Append-only
History.**

### Intent Graph Schema (Illustrative)

```json
{
  "schema_version": "0.1.0",
  "id": "project-uuid",
  "metadata": {
    "name": "Intake Manifold",
    "units": {
      "length": "mm",
      "angle": "deg",
      "si_export": true
    },
    "materials": {
      "mat-001": {
        "name": "Aluminum 6061-T6",
        "density_kg_m3": 2710,
        "roughness_m": 1.6e-6
      }
    },
    "occt_version": "7.8.1",
    "cadquery_version": "2.4.0"
  },
  "nodes": {
    "node-001": {
      "type": "sketch",
      "label": "Inlet Profile",
      "parameters": {
        "plane": "XY",
        "shapes": [
          {"type": "circle", "center": [0, 0], "radius": 25.0}
        ]
      },
      "cache": {
        "brep_hash": "sha256:abc123...",
        "brep_file": "cache/node-001.brep",
        "gltf_file": "cache/node-001.glb",
        "stale": false
      }
    },
    "node-002": {
      "type": "extrude",
      "label": "Inlet Tube",
      "parameters": {
        "distance": 100.0,
        "direction": [0, 0, 1]
      },
      "cache": {
        "brep_hash": "sha256:def456...",
        "brep_file": "cache/node-002.brep",
        "gltf_file": "cache/node-002.glb",
        "stale": false
      }
    },
    "node-003": {
      "type": "boundary_condition",
      "label": "Inlet BC",
      "parameters": {
        "bc_type": "velocity_inlet",
        "velocity_m_s": [0, 0, 5.0],
        "turbulence_model": "kOmegaSST",
        "turbulent_intensity": 0.05
      },
      "face_selector": {
        "method": "normal_filter",
        "target_node": "node-002",
        "normal": [0, 0, -1],
        "tolerance_deg": 5.0
      }
    },
    "node-004": {
      "type": "material_assignment",
      "label": "Body Material",
      "parameters": {
        "material_id": "mat-001",
        "target_node": "node-002"
      }
    }
  },
  "edges": [
    {"from": "node-001", "to": "node-002", "type": "geometry_input"},
    {"from": "node-002", "to": "node-003", "type": "face_reference"},
    {"from": "node-002", "to": "node-004", "type": "body_reference"}
  ]
}
```

### Event Log Schema (Illustrative)

```json
{
  "event_id": "evt-000002",
  "timestamp": "2026-04-07T14:23:01.456Z",
  "type": "node_added",
  "payload": {
    "node_id": "node-002",
    "node": {
      "type": "extrude",
      "label": "Inlet Tube",
      "parameters": {
        "distance": 100.0,
        "direction": [0, 0, 1]
      }
    },
    "edges_added": [
      {"from": "node-001", "to": "node-002", "type": "geometry_input"}
    ]
  },
  "agent_context": {
    "prompt": "Extrude the inlet profile 100mm in Z",
    "model": "claude-sonnet-4-20250514",
    "confidence": 0.95
  }
}
```

### Cache Invalidation Strategy

1. Each node's cache entry includes a `brep_hash` computed from the node's
   parameters and all upstream node hashes (a Merkle-style content hash).
2. When any node's parameters change, its hash changes, which propagates
   downstream through the DAG.
3. On load, compare stored hashes against recomputed hashes. Stale caches are
   either regenerated eagerly (small graphs) or lazily (large graphs, on
   access).
4. BREP caches include the OCCT version. A version mismatch marks all caches
   as stale and triggers full regeneration.

### Export Pipeline

```
Intent Graph (JSON)
  |
  v
CadQuery Evaluation (per node, cached)
  |
  +---> BREP cache (per node, on disk)
  |
  +---> STEP AP242 (full assembly, on demand, for interop)
  |
  +---> STL (per body, on demand, for snappyHexMesh)
  |
  +---> glTF 2.0 (per node, cached, for browser visualization)
         with EXT_mesh_features for face-group metadata
```

### Phased Storage Roadmap

| Phase   | Backend           | History            | Collaboration     |
|---------|-------------------|--------------------|-------------------|
| Phase 1 | JSON files + git  | Event log (files)  | Single user       |
| Phase 2 | PostgreSQL JSONB  | Events table       | Multi-user, RBAC  |
| Phase 3 | PostgreSQL + CDN  | Event sourcing     | Real-time collab  |

The Phase 1 to Phase 2 migration path is intentionally simple:
- `intent-graph.json` becomes a JSONB column in a `projects` table.
- `events/*.json` becomes rows in an `events` table.
- BREP/glTF caches move to object storage (S3 or MinIO) with the same
  content-addressable naming scheme.

---

## Consequences

### Positive

- **AI agent has structured data.** The intent graph gives Claude a typed,
  queryable representation of the design. The agent can add nodes, modify
  parameters, and assign boundary conditions through a well-defined graph API
  rather than manipulating raw source code.

- **Partial recomputation.** Per-node BREP caching means that changing a
  parameter on one node only requires recomputing that node and its downstream
  dependents. For a 50-node graph with a change near the leaves, this can
  reduce recomputation from seconds to milliseconds.

- **Full history for free.** The append-only event log provides undo/redo,
  audit trail, and the ability to replay the AI agent's reasoning for any
  historical state. This is essential for trust and debuggability in an
  agentic system.

- **Git-native versioning.** Designers and engineers can use standard git
  workflows (branches, pull requests, code review) for design collaboration.
  JSON diffs are human-readable. This aligns with the industry trend toward
  text-based parametric definitions [24].

- **Clean separation of concerns.** The intent graph owns the parametric
  definition and metadata. BREP caches own the geometry. glTF owns the
  visualization. STEP owns the interop. Each format does what it is best at.

- **Low barrier to entry.** Phase 1 requires no database, no server, no
  infrastructure. A CadFlow project is a directory of JSON and BREP files.
  It can be zipped, emailed, or pushed to GitHub.

### Negative

- **No concurrent-write safety in Phase 1.** If two processes write to the
  same JSON file simultaneously, data can be lost. This is acceptable for
  single-user use but must be addressed before multi-user support.
  Mitigation: file locking in Phase 1; PostgreSQL in Phase 2.

- **BREP caches are OCCT-version-dependent.** Upgrading OCCT may require
  regenerating all caches. Mitigation: caches are disposable by design;
  the intent graph is the source of truth; regeneration is automated.

- **Schema evolution burden.** Changes to the intent graph JSON schema must
  be handled in application code (migration functions). Mitigation: explicit
  `schema_version` field; migration functions tested in CI; the schema is
  expected to stabilize quickly after the initial design phase.

- **Large projects may outgrow JSON files.** A project with thousands of
  nodes and deep history could produce large JSON files and slow I/O.
  Mitigation: this is unlikely for Phase 1 (CFD preprocessing models are
  typically tens to hundreds of features); PostgreSQL migration is planned
  for Phase 2.

- **Event log replay cost.** Reconstructing state from a long event log is
  O(n) in the number of events. Mitigation: the current-state file
  (`intent-graph.json`) is a materialized view; the event log is for history
  and audit, not for primary reads.

### Neutral

- **CadQuery remains the execution engine.** This decision does not change
  how geometry is computed -- only how the inputs and outputs of that
  computation are stored and organized.

- **Export formats are additive.** Supporting additional export formats
  (3MF, VRML, Parasolid) in the future does not require changes to the
  data model.

---

## Dependencies

### Upstream Dependencies

| Dependency        | Version    | Role                                      |
|-------------------|------------|-------------------------------------------|
| CadQuery          | >= 2.4     | Geometry evaluation engine                |
| OCCT              | >= 7.8     | Kernel for BREP operations and export     |
| Python            | >= 3.11    | Runtime for CadQuery and graph logic      |
| OCCT BREP format  | 7.x        | Per-node geometry cache format            |

### Downstream Dependencies (Affected by This Decision)

| Component                   | Impact                                        |
|-----------------------------|-----------------------------------------------|
| ADR-002 (Intent Graph)      | This ADR defines the persistence format for    |
|                             | the intent graph specified in ADR-002.         |
| AI Agent (Claude)           | Agent reads/writes the intent graph JSON.      |
|                             | Schema changes require agent prompt updates.   |
| Browser Visualization       | Consumes glTF caches generated by this system. |
| CFD Pipeline                | Reads boundary conditions and materials from   |
|                             | intent graph metadata nodes.                   |
| Mesh Generation             | Reads STL exports and mesh-sizing metadata     |
|                             | from intent graph nodes.                       |
| STEP Import/Export           | STEP AP242 export pipeline reads the assembled |
|                             | geometry from BREP caches.                     |

### Phase 2 Migration Dependencies

| Dependency        | Purpose                                         |
|-------------------|-------------------------------------------------|
| PostgreSQL >= 16  | JSONB storage for intent graph and events table |
| S3-compatible     | Object storage for BREP and glTF caches         |
| Migration tooling | Schema migration framework (e.g., Alembic)      |

### Standards and Specifications Referenced

| Standard           | Version/Date | Relevance                             |
|--------------------|-------------|---------------------------------------|
| ISO 10303-242      | 2020        | STEP AP242 export format              |
| RFC 8259           | 2017        | JSON data interchange format          |
| glTF 2.0           | 2021        | Browser visualization format          |
| EXT_mesh_features  | 2022        | Face-group metadata in glTF           |
